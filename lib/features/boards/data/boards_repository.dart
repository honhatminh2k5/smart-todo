import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Small model used by the board list and archived-board screen.
class BoardSummary {
  const BoardSummary({
    required this.id,
    required this.name,
    required this.description,
    required this.ownerId,
    required this.memberIds,
    required this.updatedAt,
    required this.archivedAt,
  });

  final String id;
  final String name;
  final String description;
  final String ownerId;
  final List<String> memberIds;
  final DateTime? updatedAt;
  final DateTime? archivedAt;

  bool get isArchived => archivedAt != null;

  factory BoardSummary.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final updatedAtValue = data['updatedAt'];
    final archivedAtValue = data['archivedAt'];

    return BoardSummary(
      id: document.id,
      name: data['name'] as String? ?? '(Chưa có tên)',
      description: data['description'] as String? ?? '',
      ownerId: data['ownerId'] as String? ?? '',
      memberIds: (data['memberIds'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      updatedAt: updatedAtValue is Timestamp ? updatedAtValue.toDate() : null,
      archivedAt: archivedAtValue is Timestamp
          ? archivedAtValue.toDate()
          : null,
    );
  }
}

class BoardsRepository {
  BoardsRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _boards =>
      _firestore.collection('boards');

  /// Watches every board the user belongs to. The Firestore query deliberately
  /// includes memberIds so it is compatible with firestore.rules.
  Stream<List<BoardSummary>> watchMyBoards(String uid) {
    return _boards.where('memberIds', arrayContains: uid).snapshots().map((
      snapshot,
    ) {
      final boards = snapshot.docs.map(BoardSummary.fromDocument).toList();
      boards.sort((a, b) {
        final aDate = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
      return boards;
    });
  }

  /// Kept for compatibility with any existing screen that only needs active boards.
  Stream<List<BoardSummary>> watchMyActiveBoards(String uid) {
    return watchMyBoards(
      uid,
    ).map((boards) => boards.where((board) => !board.isArchived).toList());
  }

  Future<String> createBoard({
    required String name,
    required String description,
  }) async {
    final user = _requireSignedInUser();
    final cleanName = _validateName(name);
    final cleanDescription = _validateDescription(description);

    final email = user.email?.trim().toLowerCase() ?? '';
    final displayName = (user.displayName?.trim().isNotEmpty ?? false)
        ? user.displayName!.trim()
        : email;
    if (email.isEmpty || displayName.isEmpty) {
      throw StateError('Tài khoản cần có email và tên hiển thị hợp lệ.');
    }

    final boardRef = _boards.doc();
    final memberRef = boardRef.collection('members').doc(user.uid);
    final batch = _firestore.batch();

    batch.set(boardRef, {
      'name': cleanName,
      'description': cleanDescription,
      'ownerId': user.uid,
      'memberIds': [user.uid],
      'archivedAt': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Keep the board and its Owner member record consistent in one atomic write.
    batch.set(memberRef, {
      'role': 'owner',
      'displayName': displayName,
      'email': email,
      'joinedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
    return boardRef.id;
  }

  /// Updates only the editable information fields. Security Rules remain the
  /// authority for verifying that the current user is the Owner.
  Future<void> updateBoard({
    required String boardId,
    required String name,
    required String description,
  }) async {
    _requireSignedInUser();
    final cleanName = _validateName(name);
    final cleanDescription = _validateDescription(description);

    await _boards.doc(boardId).update({
      'name': cleanName,
      'description': cleanDescription,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Archives a board instead of deleting it, so that it can be restored later.
  Future<void> archiveBoard(String boardId) async {
    _requireSignedInUser();
    await _boards.doc(boardId).update({
      'archivedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Restores an archived board to the active list.
  Future<void> restoreBoard(String boardId) async {
    _requireSignedInUser();
    await _boards.doc(boardId).update({
      'archivedAt': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  User _requireSignedInUser() {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Bạn cần đăng nhập trước khi thực hiện thao tác này.');
    }
    return user;
  }

  String _validateName(String name) {
    final cleanName = name.trim();
    if (cleanName.isEmpty || cleanName.length > 100) {
      throw ArgumentError('Tên board phải có từ 1 đến 100 ký tự.');
    }
    return cleanName;
  }

  String _validateDescription(String description) {
    final cleanDescription = description.trim();
    if (cleanDescription.length > 500) {
      throw ArgumentError('Mô tả board không được dài quá 500 ký tự.');
    }
    return cleanDescription;
  }
}
