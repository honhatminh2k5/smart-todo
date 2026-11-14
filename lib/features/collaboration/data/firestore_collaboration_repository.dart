import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../boards/data/boards_repository.dart';
import '../../cards/data/card_model.dart';
import '../domain/collaboration_rules.dart';
import 'collaboration_models.dart';
import 'collaboration_repository.dart';

/// Triển khai [CollaborationRepository] dùng Cloud Firestore.
///
/// Không có Cloud Functions (quyết định D8): mọi thao tác nhiều bước do app
/// thực hiện bằng batch/transaction, `firestore.rules` làm lưới an toàn.
/// Các điều kiện Rules không tự kiểm tra được (access patterns § 8) được đọc
/// thẳng từ máy chủ trước khi ghi, vì bộ nhớ đệm có thể đã lỗi thời (§ 9).
class FirestoreCollaborationRepository implements CollaborationRepository {
  FirestoreCollaborationRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  static const _fromServer = GetOptions(source: Source.server);

  /// Số card tối đa được gỡ người được giao trong một batch. Chia nhỏ để không
  /// chạm giới hạn truy cập tài liệu của Rules (`firestore-security.md` R1).
  static const _unassignBatchSize = 100;

  /// Transaction cần mạng; quá thời gian này thì báo lỗi kết nối (UC06 10a).
  static const _transactionTimeout = Duration(seconds: 10);

  DocumentReference<Map<String, dynamic>> _board(String boardId) =>
      _firestore.collection('boards').doc(boardId);

  DocumentReference<Map<String, dynamic>> _card(
    String boardId,
    String cardId,
  ) => _board(boardId).collection('cards').doc(cardId);

  @override
  String? get currentUserId => _auth.currentUser?.uid;

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  @override
  Stream<BoardSummary?> watchBoard(String boardId) {
    return _board(boardId).snapshots().map(
      (document) =>
          document.exists ? BoardSummary.fromDocument(document) : null,
    );
  }

  @override
  Stream<List<BoardMember>> watchMembers(String boardId) {
    return _board(boardId)
        .collection('members')
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(BoardMember.fromDocument).toList()
                ..sort(compareMembers),
        );
  }

  /// Truy vấn D: chỉ Owner đọc được lời mời của board.
  @override
  Stream<List<BoardInvitation>> watchPendingInvitations(String boardId) {
    return _board(boardId)
        .collection('invitations')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(BoardInvitation.fromDocument).toList()
                ..sort(BoardInvitation.newestFirst),
        );
  }

  /// Truy vấn E: Rules chỉ cho truy vấn nhóm khi có đúng điều kiện
  /// `normalizedEmail == email của mình`; cần chỉ mục trong
  /// `firestore.indexes.json`.
  @override
  Stream<List<BoardInvitation>> watchMyInvitations() {
    final email = _auth.currentUser?.email;
    if (email == null || email.trim().isEmpty) {
      return Stream.value(const <BoardInvitation>[]);
    }
    return _firestore
        .collectionGroup('invitations')
        .where('normalizedEmail', isEqualTo: normalizeEmail(email))
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(BoardInvitation.fromDocument).toList()
                ..sort(BoardInvitation.newestFirst),
        );
  }

  @override
  Stream<List<CardComment>> watchComments({
    required String boardId,
    required String cardId,
  }) {
    return _card(boardId, cardId)
        .collection('comments')
        .orderBy('createdAt')
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(CardComment.fromDocument).toList()
                ..sort(CardComment.oldestFirst),
        );
  }

  // ---------------------------------------------------------------------------
  // Lời mời (W26–W29)
  // ---------------------------------------------------------------------------

  @override
  Future<void> inviteMember({
    required String boardId,
    required String email,
  }) async {
    final user = _requireUser();
    final formatError = validateInviteEmail(email);
    if (formatError != null) throw ArgumentError(formatError);
    final cleanEmail = email.trim();
    final normalized = normalizeEmail(cleanEmail);

    final boardRef = _board(boardId);
    final board = await boardRef.get(_fromServer);
    final boardData = board.data();
    if (boardData == null) {
      throw const CollaborationException('Board không còn tồn tại.');
    }
    if (boardData['ownerId'] != user.uid) {
      throw const CollaborationException('Chỉ Owner mới được mời thành viên.');
    }

    // UC06 4a: Rules không duyệt được cả `members`, app phải tự so email.
    final members = await boardRef.collection('members').get(_fromServer);
    final isMember = members.docs.any(
      (member) =>
          normalizeEmail(member.data()['email'] as String? ?? '') == normalized,
    );
    if (isMember) {
      throw CollaborationException('$cleanEmail đã là thành viên của board.');
    }

    final invitationRef = boardRef.collection('invitations').doc(normalized);
    final existing = await invitationRef.get(_fromServer);
    if (existing.data()?['status'] == 'pending') {
      throw CollaborationException(
        'Đã có lời mời đang chờ gửi tới $cleanEmail.',
      );
    }

    // Mời lại người từng từ chối/bị xóa: ghi đè tờ cũ về 'pending' (Q12).
    await invitationRef.set({
      'email': cleanEmail,
      'normalizedEmail': normalized,
      'invitedBy': user.uid,
      'inviterName': displayNameFor(
        displayName: user.displayName,
        email: user.email,
      ),
      'boardName': boardData['name'],
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> cancelInvitation({
    required String boardId,
    required String normalizedEmail,
  }) async {
    _requireUser();
    final invitationRef = _board(
      boardId,
    ).collection('invitations').doc(normalizedEmail);
    await _firestore.runTransaction((transaction) async {
      final invitation = await transaction.get(invitationRef);
      final status = invitation.data()?['status'];
      if (!invitation.exists) return;
      if (status != 'pending') {
        throw CollaborationException(
          status == 'accepted'
              ? 'Người này đã chấp nhận lời mời nên không hủy được.'
              : 'Lời mời đã được trả lời nên không hủy được.',
        );
      }
      transaction.delete(invitationRef);
    }, timeout: _transactionTimeout);
  }

  /// W28: ba thao tác ghi trong một transaction. Rules kiểm tra lời mời còn
  /// 'pending' theo trạng thái trước khi ghi, nên lời mời đã bị hủy làm cả
  /// transaction bị từ chối (UC06 9a).
  @override
  Future<void> acceptInvitation(BoardInvitation invitation) async {
    final user = _requireUser();
    final email = user.email ?? '';
    if (normalizeEmail(email) != invitation.normalizedEmail) {
      throw const CollaborationException(
        'Lời mời này không gửi tới email của bạn.',
      );
    }

    final boardRef = _board(invitation.boardId);
    final invitationRef = boardRef
        .collection('invitations')
        .doc(invitation.normalizedEmail);
    final memberRef = boardRef.collection('members').doc(user.uid);

    await _respond(() {
      return _firestore.runTransaction((transaction) async {
        final current = await transaction.get(invitationRef);
        if (current.data()?['status'] != 'pending') {
          throw const CollaborationException(kInvitationNoLongerValid);
        }
        transaction.update(invitationRef, {
          'status': 'accepted',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        transaction.set(memberRef, {
          'role': 'member',
          'displayName': displayNameFor(
            displayName: user.displayName,
            email: email,
          ),
          'email': email,
          'joinedAt': FieldValue.serverTimestamp(),
        });
        transaction.update(boardRef, {
          'memberIds': FieldValue.arrayUnion([user.uid]),
        });
      }, timeout: _transactionTimeout);
    });
  }

  @override
  Future<void> declineInvitation(BoardInvitation invitation) async {
    _requireUser();
    final invitationRef = _board(
      invitation.boardId,
    ).collection('invitations').doc(invitation.normalizedEmail);

    await _respond(() {
      return _firestore.runTransaction((transaction) async {
        final current = await transaction.get(invitationRef);
        if (current.data()?['status'] != 'pending') {
          throw const CollaborationException(kInvitationNoLongerValid);
        }
        transaction.update(invitationRef, {
          'status': 'declined',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }, timeout: _transactionTimeout);
    });
  }

  /// Lời mời đã bị xóa thì Rules từ chối cả việc đọc lẫn ghi; báo cho người
  /// dùng là lời mời không còn hiệu lực thay vì "không có quyền".
  Future<void> _respond(Future<void> Function() action) async {
    try {
      await action();
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied' || error.code == 'not-found') {
        throw const CollaborationException(kInvitationNoLongerValid);
      }
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Thành viên (W30–W31)
  // ---------------------------------------------------------------------------

  @override
  Future<void> removeMember({
    required String boardId,
    required String memberUid,
  }) async {
    final user = _requireUser();
    final board = await _board(boardId).get(_fromServer);
    final data = board.data();
    if (data == null) {
      throw const CollaborationException('Board không còn tồn tại.');
    }
    if (data['ownerId'] != user.uid) {
      throw const CollaborationException('Chỉ Owner mới được xóa thành viên.');
    }
    if (memberUid == data['ownerId']) {
      throw const CollaborationException('Không thể xóa Owner khỏi board.');
    }
    if (!_memberIdsOf(data).contains(memberUid)) {
      throw const CollaborationException(
        'Người này không còn là thành viên của board.',
      );
    }
    await _detachMember(boardId: boardId, memberUid: memberUid);
  }

  @override
  Future<void> leaveBoard(String boardId) async {
    final user = _requireUser();
    final board = await _board(boardId).get(_fromServer);
    final data = board.data();
    if (data == null) {
      throw const CollaborationException('Board không còn tồn tại.');
    }
    if (data['ownerId'] == user.uid) {
      throw const CollaborationException('Owner không thể rời board.');
    }
    if (!_memberIdsOf(data).contains(user.uid)) {
      throw const CollaborationException(
        'Bạn không còn là thành viên của board.',
      );
    }
    await _detachMember(boardId: boardId, memberUid: user.uid);
  }

  /// Gỡ [memberUid] khỏi `assigneeIds` của mọi card (kể cả card đã lưu trữ,
  /// luật I3), rồi xóa `members/{uid}` và bớt khỏi `memberIds` (luật I2).
  ///
  /// Thường chỉ cần một batch. Nếu phải chia nhỏ, card được gỡ trước và
  /// tư cách thành viên bị xóa ở batch cuối, nên dừng giữa chừng vẫn không
  /// có card giao cho người đã rời (`firestore-security.md` § 6).
  Future<void> _detachMember({
    required String boardId,
    required String memberUid,
  }) async {
    final boardRef = _board(boardId);
    final assigned = await boardRef
        .collection('cards')
        .where('assigneeIds', arrayContains: memberUid)
        .get(_fromServer);
    final cards = assigned.docs.map((doc) => doc.reference).toList();
    final unassign = {
      'assigneeIds': FieldValue.arrayRemove([memberUid]),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    var start = 0;
    while (cards.length - start > _unassignBatchSize) {
      final batch = _firestore.batch();
      final end = math.min(start + _unassignBatchSize, cards.length);
      for (final card in cards.sublist(start, end)) {
        batch.update(card, unassign);
      }
      await batch.commit();
      start = end;
    }

    final batch = _firestore.batch();
    for (final card in cards.sublist(start)) {
      batch.update(card, unassign);
    }
    batch.delete(boardRef.collection('members').doc(memberUid));
    batch.update(boardRef, {
      'memberIds': FieldValue.arrayRemove([memberUid]),
    });
    await batch.commit();
  }

  // ---------------------------------------------------------------------------
  // Bình luận (W23–W25)
  // ---------------------------------------------------------------------------

  @override
  Future<void> addComment({
    required String boardId,
    required String cardId,
    required String body,
  }) async {
    final cleanBody = normalizeCommentBody(body);
    final user = _requireUser();
    final cardRef = _card(boardId, cardId);
    final commentRef = cardRef.collection('comments').doc();

    // Card bị xóa trong lúc gửi thì cả batch thất bại, không để lại bình luận
    // mồ côi.
    final batch = _firestore.batch()
      ..set(commentRef, {
        'authorId': user.uid,
        'authorName': displayNameFor(
          displayName: user.displayName,
          email: user.email,
        ),
        'body': cleanBody,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      })
      ..update(cardRef, {
        'commentCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    await batch.commit();
  }

  @override
  Future<void> editComment({
    required String boardId,
    required String cardId,
    required String commentId,
    required String body,
  }) async {
    final cleanBody = normalizeCommentBody(body);
    _requireUser();
    await _card(boardId, cardId).collection('comments').doc(commentId).update({
      'body': cleanBody,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Dùng transaction để bộ đếm chỉ giảm khi bình luận thật sự còn tồn tại
  /// (hai người cùng xóa một bình luận không làm `commentCount` lệch).
  @override
  Future<void> deleteComment({
    required String boardId,
    required String cardId,
    required String commentId,
  }) async {
    _requireUser();
    final cardRef = _card(boardId, cardId);
    final commentRef = cardRef.collection('comments').doc(commentId);
    await _firestore.runTransaction((transaction) async {
      final comment = await transaction.get(commentRef);
      if (!comment.exists) {
        throw const CollaborationException('Bình luận không còn tồn tại.');
      }
      final card = await transaction.get(cardRef);
      final count = (card.data()?['commentCount'] as num?)?.toInt() ?? 0;
      transaction.delete(commentRef);
      if (card.exists) {
        transaction.update(cardRef, {
          'commentCount': math.max(0, count - 1),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }, timeout: _transactionTimeout);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  User _requireUser() {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Bạn cần đăng nhập trước khi thực hiện thao tác này.');
    }
    return user;
  }

  static List<String> _memberIdsOf(Map<String, dynamic> board) =>
      (board['memberIds'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false);
}
