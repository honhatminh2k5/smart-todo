import 'list_model.dart';

/// Contract của data layer cho chức năng quản lý List (UC04).
///
/// Hai implementation tồn tại song song:
/// - [FirestoreListRepository]: dùng trong production (kết nối Cloud Firestore).
/// - [FakeListRepository]: dùng trong preview / demo / test khi không có Firebase.
///
/// Các tầng trên (Provider, StateNotifier/Notifier, UI) chỉ phụ thuộc vào
/// [ListRepository] interface, không phụ thuộc trực tiếp vào implementation cụ thể.
abstract interface class ListRepository {
  /// Lấy Stream danh sách các List **đang hoạt động** (chưa lưu trữ) của một board,
  /// được sắp xếp tăng dần theo [TaskListModel.position].
  Stream<List<TaskListModel>> getListsByBoardId(String boardId);

  /// Lấy Stream các List đã lưu trữ (`archivedAt != null`) của một board,
  /// được sắp xếp tăng dần theo [TaskListModel.position].
  Stream<List<TaskListModel>> getArchivedListsByBoardId(String boardId);

  /// Tương thích ngược với [getListsByBoardId].
  Stream<List<TaskListModel>> watchLists(String boardId);

  /// Tạo một List mới trong board.
  ///
  /// [name] sẽ được trim và kiểm tra độ dài 1–100 ký tự trước khi ghi.
  /// Nếu [position] không được truyền, repository tự động đặt vị trí ở cuối
  /// danh sách (`max(position) + 1000.0`).
  ///
  /// Trả về ID của List vừa được tạo.
  Future<String> createList({
    required String boardId,
    required String name,
    double? position,
  });

  /// Cập nhật thông tin List (tên, thứ tự vị trí, trạng thái lưu trữ).
  ///
  /// Chỉ cập nhật các trường được truyền vào và `updatedAt`.
  /// Tuyệt đối **không ghi đè** `createdAt`.
  Future<void> updateList({
    required String boardId,
    required String listId,
    String? name,
    double? position,
    DateTime? archivedAt,
    bool clearArchivedAt = false,
  });

  /// Đổi tên List (helper thuận tiện gọi `updateList`).
  Future<void> renameList({
    required String boardId,
    required String listId,
    required String newName,
  });

  /// Xóa một List khỏi board.
  ///
  /// Theo Firestore Rules (`allow delete: if false`) và Schema § 4.6,
  /// List không bị xóa vật lý mà thực hiện soft-delete (đặt `archivedAt`).
  ///
  /// ⚠️ **Quan trọng**: Phương thức này chỉ thao tác trên document của List,
  /// **KHÔNG** tự ý xóa hoặc thay đổi các Card thuộc List trong giai đoạn này.
  /// Việc xử lý các Card liên quan sẽ được quyết định ở giai đoạn tích hợp Card (UC05).
  Future<void> deleteList({required String boardId, required String listId});

  /// Lưu trữ một List (soft-delete, tương đương [deleteList]).
  Future<void> archiveList({required String boardId, required String listId});

  /// Khôi phục một List đã lưu trữ.
  ///
  /// Đặt lại `archivedAt = null` và cập nhật `updatedAt`.
  Future<void> unarchiveList({required String boardId, required String listId});

  /// Sắp xếp lại thứ tự các List theo danh sách ID [orderedListIds].
  ///
  /// Repository tính toán lại `position = (index + 1) * 1000.0` cho từng list
  /// và ghi đồng thời (batch) trong một thao tác.
  Future<void> reorderLists({
    required String boardId,
    required List<String> orderedListIds,
  });
}
