import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/card_rules.dart';
import 'card_model.dart';
import 'card_repository.dart';

/// Triển khai [CardRepository] dùng Cloud Firestore.
///
/// Card nằm trong `boards/{boardId}/cards/{cardId}`; quyền được kiểm tra bởi
/// Security Rules (chỉ thành viên board được đọc/ghi).
class FirestoreCardRepository implements CardRepository {
  FirestoreCardRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  /// Một batch Firestore chứa tối đa 500 thao tác ghi.
  static const _maxBatchWrites = 500;

  DocumentReference<Map<String, dynamic>> _board(String boardId) =>
      _firestore.collection('boards').doc(boardId);

  CollectionReference<Map<String, dynamic>> _cards(String boardId) =>
      _board(boardId).collection('cards');

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  @override
  Stream<BoardCardsSnapshot> watchBoardCards(String boardId) {
    return _cards(boardId)
        .where('archivedAt', isNull: true)
        // Nhận cả thay đổi metadata để biết khi nào dữ liệu chỉ còn từ bộ nhớ
        // đệm (mất kết nối, UC05 8a).
        .snapshots(includeMetadataChanges: true)
        .map(
          (snapshot) => BoardCardsSnapshot(
            cards: snapshot.docs.map(TaskCardModel.fromDocument).toList(),
            isFromCache: snapshot.metadata.isFromCache,
          ),
        );
  }

  @override
  Stream<TaskCardModel?> watchCard({
    required String boardId,
    required String cardId,
  }) {
    return _cards(boardId)
        .doc(cardId)
        .snapshots()
        .map(
          (document) =>
              document.exists ? TaskCardModel.fromDocument(document) : null,
        );
  }

  @override
  Stream<List<CardLabel>> watchLabels(String boardId) {
    return _board(boardId)
        .collection('labels')
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(CardLabel.fromDocument).toList()
                ..sort((a, b) => a.name.compareTo(b.name)),
        );
  }

  @override
  Stream<List<BoardMember>> watchMembers(String boardId) {
    return _board(boardId)
        .collection('members')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map(BoardMember.fromDocument).toList(),
        );
  }

  // ---------------------------------------------------------------------------
  // Write
  // ---------------------------------------------------------------------------

  /// Ghi đủ 16 trường theo W9; Rules từ chối nếu thiếu hoặc thừa trường.
  @override
  Future<String> createCard({
    required String boardId,
    required String listId,
    required String title,
    required double position,
  }) async {
    final cleanTitle = normalizeCardTitle(title);
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('Bạn cần đăng nhập để tạo thẻ.');
    }

    final document = _cards(boardId).doc();
    await document.set({
      'boardId': boardId,
      'listId': listId,
      'title': cleanTitle,
      'description': '',
      'position': position,
      'isCompleted': false,
      'assigneeIds': <String>[],
      'labelIds': <String>[],
      'dueAt': null,
      'archivedAt': null,
      'commentCount': 0,
      'checklistTotal': 0,
      'checklistDone': 0,
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return document.id;
  }

  @override
  Future<void> renameCard({
    required String boardId,
    required String cardId,
    required String title,
  }) async {
    await _cards(boardId).doc(cardId).update({
      'title': normalizeCardTitle(title),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> setCompleted({
    required String boardId,
    required String cardId,
    required bool isCompleted,
  }) async {
    await _cards(boardId).doc(cardId).update({
      'isCompleted': isCompleted,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> archiveCard({
    required String boardId,
    required String cardId,
  }) async {
    await _cards(boardId).doc(cardId).update({
      'archivedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Firestore không tự xóa subcollection, nên xóa checklist và bình luận cùng
  /// batch với card (W14). Rules chỉ cho xóa bình luận của người khác khi card
  /// cha bị xóa trong cùng batch.
  ///
  /// Dữ liệu con được đọc thẳng từ máy chủ: bộ nhớ đệm có thể thiếu mục, để
  /// lại dữ liệu mồ côi. Khi mất mạng thao tác này báo lỗi thay vì xếp hàng.
  @override
  Future<void> deleteCard({
    required String boardId,
    required String cardId,
  }) async {
    final card = _cards(boardId).doc(cardId);
    const fromServer = GetOptions(source: Source.server);
    final checklist = await card.collection('checklist').get(fromServer);
    final comments = await card.collection('comments').get(fromServer);

    final children = [...checklist.docs, ...comments.docs];
    if (children.length + 1 > _maxBatchWrites) {
      throw StateError('Thẻ có quá nhiều mục con để xóa trong một lần.');
    }

    final batch = _firestore.batch();
    for (final child in children) {
      batch.delete(child.reference);
    }
    batch.delete(card);
    await batch.commit();
  }

  @override
  Future<void> moveCard({
    required String boardId,
    required String cardId,
    required String toListId,
    required double position,
  }) async {
    await _cards(boardId).doc(cardId).update({
      'listId': toListId,
      'position': position,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// `arrayUnion`/`arrayRemove` để hai người cùng giao việc không ghi đè
  /// lựa chọn của nhau. Rules từ chối uid không thuộc `memberIds`.
  @override
  Future<void> setAssignee({
    required String boardId,
    required String cardId,
    required String memberUid,
    required bool assigned,
  }) async {
    await _cards(boardId).doc(cardId).update({
      'assigneeIds': assigned
          ? FieldValue.arrayUnion([memberUid])
          : FieldValue.arrayRemove([memberUid]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> reorderCards({
    required String boardId,
    required String listId,
    required List<String> orderedCardIds,
  }) async {
    if (orderedCardIds.isEmpty) return;
    if (orderedCardIds.length > _maxBatchWrites) {
      throw StateError('List có quá nhiều thẻ để sắp xếp lại trong một lần.');
    }

    final batch = _firestore.batch();
    for (var i = 0; i < orderedCardIds.length; i++) {
      batch.update(_cards(boardId).doc(orderedCardIds[i]), {
        'listId': listId,
        'position': (i + 1) * kCardPositionStep,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}
