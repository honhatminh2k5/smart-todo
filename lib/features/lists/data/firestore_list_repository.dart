import 'package:cloud_firestore/cloud_firestore.dart';

import 'list_model.dart';
import 'list_repository.dart';

/// Triển khai [ListRepository] dùng Cloud Firestore.
///
/// Mọi List nằm trong subcollection: `boards/{boardId}/lists/{listId}`.
/// Quyền hạn được kiểm soát ở server thông qua Firestore Security Rules.
class FirestoreListRepository implements ListRepository {
  FirestoreListRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Subcollection `lists` của board: `boards/{boardId}/lists`.
  CollectionReference<Map<String, dynamic>> _lists(String boardId) =>
      _firestore.collection('boards').doc(boardId).collection('lists');

  /// Kiểm tra và làm sạch tên danh sách: 1–100 ký tự (UC04 § 4.6).
  String _validateName(String name) {
    final clean = name.trim();
    if (clean.isEmpty || clean.length > 100) {
      throw ArgumentError('Tên danh sách phải có từ 1 đến 100 ký tự.');
    }
    return clean;
  }

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  /// Lấy Stream các List đang hoạt động (`archivedAt == null`),
  /// được sắp xếp tăng dần theo `position`.
  @override
  Stream<List<TaskListModel>> getListsByBoardId(String boardId) {
    return _lists(boardId)
        .where('archivedAt', isNull: true)
        .orderBy('position')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map(TaskListModel.fromDocument).toList(),
        );
  }

  @override
  Stream<List<TaskListModel>> getArchivedListsByBoardId(String boardId) {
    return _lists(boardId)
        // `isNotEqualTo: null` is not reliable for this stream on all
        // Firestore emulator/FlutterFire combinations. Archived documents
        // always contain a Timestamp, so use a Timestamp range instead.
        .where(
          'archivedAt',
          isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(0),
        )
        .snapshots()
        .map((snapshot) {
          final archived =
              snapshot.docs
                  .where(
                    (document) => document.data()['archivedAt'] is Timestamp,
                  )
                  .map(TaskListModel.fromDocument)
                  .toList()
                ..sort((a, b) => a.position.compareTo(b.position));
          return archived;
        });
  }

  /// Tương thích ngược với [getListsByBoardId].
  @override
  Stream<List<TaskListModel>> watchLists(String boardId) =>
      getListsByBoardId(boardId);

  // ---------------------------------------------------------------------------
  // Write — Create
  // ---------------------------------------------------------------------------

  /// Tạo List mới trong `boards/{boardId}/lists/{listId}`.
  ///
  /// Nếu [position] không truyền vào, repository tự động gán position lớn hơn
  /// list hiện tại lớn nhất 1000.0 (theo quyết định Q8 trong firestore-schema.md).
  ///
  /// Thiết lập:
  /// - `createdAt`: `FieldValue.serverTimestamp()`
  /// - `updatedAt`: `FieldValue.serverTimestamp()`
  /// - `archivedAt`: `null`
  @override
  Future<String> createList({
    required String boardId,
    required String name,
    double? position,
  }) async {
    final cleanName = _validateName(name);

    double targetPosition = position ?? 0.0;
    if (position == null) {
      final lastSnap = await _lists(
        boardId,
      ).orderBy('position', descending: true).limit(1).get();

      final lastPosition = lastSnap.docs.isEmpty
          ? 0.0
          : (lastSnap.docs.first.data()['position'] as num?)?.toDouble() ?? 0.0;
      targetPosition = lastPosition + 1000.0;
    }

    final docRef = _lists(boardId).doc();
    await docRef.set({
      'name': cleanName,
      'position': targetPosition,
      'archivedAt': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return docRef.id;
  }

  // ---------------------------------------------------------------------------
  // Write — Update
  // ---------------------------------------------------------------------------

  /// Cập nhật các trường được chỉ định của List.
  ///
  /// Tuyệt đối **không ghi đè `createdAt`**. Luôn gán `updatedAt = serverTimestamp()`.
  @override
  Future<void> updateList({
    required String boardId,
    required String listId,
    String? name,
    double? position,
    DateTime? archivedAt,
    bool clearArchivedAt = false,
  }) async {
    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (name != null) {
      updates['name'] = _validateName(name);
    }
    if (position != null) {
      updates['position'] = position;
    }
    if (clearArchivedAt) {
      updates['archivedAt'] = null;
    } else if (archivedAt != null) {
      updates['archivedAt'] = Timestamp.fromDate(archivedAt);
    }

    await _lists(boardId).doc(listId).update(updates);
  }

  /// Đổi tên List — helper gọi [updateList].
  @override
  Future<void> renameList({
    required String boardId,
    required String listId,
    required String newName,
  }) async {
    final cleanName = _validateName(newName);
    await updateList(boardId: boardId, listId: listId, name: cleanName);
  }

  // ---------------------------------------------------------------------------
  // Write — Delete / Archive / Restore
  // ---------------------------------------------------------------------------

  /// Xóa List (soft-delete).
  ///
  /// Theo Firestore Rules (`allow delete: if false`) và Schema § 4.6
  /// ("List không bị xóa, chỉ lưu trữ"), thao tác xóa ở đây đánh dấu
  /// `archivedAt = serverTimestamp()` thay vì xóa cứng document khỏi Firestore.
  ///
  /// ⚠️ **Vấn đề Card liên quan**:
  /// Phương thức này KHÔNG xóa hoặc thay đổi bất kỳ Card nào thuộc List này.
  /// Do đó, các Card thuộc list vẫn tồn tại trên Firestore với `listId` cũ.
  /// Ở giai đoạn tích hợp Card (UC05), cần quyết định phương án cascade:
  /// archive hàng loạt Card cùng lúc hoặc xử lý hiển thị phù hợp.
  @override
  Future<void> deleteList({required String boardId, required String listId}) =>
      archiveList(boardId: boardId, listId: listId);

  /// Lưu trữ List (soft-delete) bằng cách đặt `archivedAt = serverTimestamp()`.
  @override
  Future<void> archiveList({
    required String boardId,
    required String listId,
  }) async {
    await _lists(boardId).doc(listId).update({
      'archivedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Khôi phục List đã lưu trữ bằng cách đặt `archivedAt = null`.
  @override
  Future<void> unarchiveList({
    required String boardId,
    required String listId,
  }) async {
    final document = _lists(boardId).doc(listId);
    await document.update({
      'archivedAt': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ---------------------------------------------------------------------------
  // Write — Reorder
  // ---------------------------------------------------------------------------

  /// Sắp xếp lại thứ tự danh sách các List theo [orderedListIds].
  ///
  /// Cập nhật lại `position = (index + 1) * 1000.0` và `updatedAt` trong
  /// một atomic batch duy nhất để đảm bảo tính nhất quán và tối ưu số lượt ghi.
  /// `createdAt` được giữ nguyên.
  @override
  Future<void> reorderLists({
    required String boardId,
    required List<String> orderedListIds,
  }) async {
    if (orderedListIds.isEmpty) return;

    final batch = _firestore.batch();
    for (var i = 0; i < orderedListIds.length; i++) {
      final ref = _lists(boardId).doc(orderedListIds[i]);
      batch.update(ref, {
        'position': (i + 1) * 1000.0,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}
