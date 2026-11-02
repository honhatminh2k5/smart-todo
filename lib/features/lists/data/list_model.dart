import 'package:cloud_firestore/cloud_firestore.dart';

/// Model đại diện cho một cột (List) trong board.
///
/// Đường dẫn Firestore: `boards/{boardId}/lists/{listId}`.
/// `boardId` không nằm trong document fields vì đã được xác định bởi
/// đường dẫn subcollection — khác với [Card] vốn cần lưu `boardId` riêng.
///
/// Quy ước tên trường tuân theo § 4.6 của `docs/firestore-schema.md`:
/// - `archivedAt == null`  → list đang hoạt động (chưa lưu trữ).
/// - `archivedAt != null`  → list đã lưu trữ; giá trị là thời điểm lưu trữ.
class TaskListModel {
  const TaskListModel({
    required this.id,
    required this.name,
    required this.position,
    required this.archivedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Document ID do Firestore tự sinh (`doc()` không truyền id).
  final String id;

  /// Tên danh sách — 1 đến 100 ký tự (đã trim khi ghi).
  final String name;

  /// Số thứ tự sắp xếp từ trái sang phải trong board.
  /// Kiểu `double` cho phép chèn giữa hai vị trí không cần ghi lại toàn bộ
  /// danh sách (xem Q8 trong firestore-schema.md).
  final double position;

  /// Thời điểm lưu trữ; `null` khi list đang hoạt động.
  final DateTime? archivedAt;

  /// Thời điểm tạo — do server ghi (`FieldValue.serverTimestamp()`).
  /// Có thể `null` ngay sau khi document được tạo trước khi server phản hồi.
  final DateTime? createdAt;

  /// Thời điểm cập nhật cuối — do server ghi.
  final DateTime? updatedAt;

  /// Trả về `true` nếu list đang trong trạng thái lưu trữ.
  bool get isArchived => archivedAt != null;

  // ---------------------------------------------------------------------------
  // Deserialization — Firestore → Dart
  // ---------------------------------------------------------------------------

  /// Tạo [TaskListModel] từ một document snapshot.
  ///
  /// Sử dụng [QueryDocumentSnapshot] để tương thích với kết quả truy vấn
  /// (`collection.where(...).snapshots()`), khớp với pattern của [BoardSummary].
  factory TaskListModel.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    return TaskListModel(
      id: document.id,
      name: data['name'] as String? ?? '(Chưa có tên)',
      position: (data['position'] as num?)?.toDouble() ?? 0.0,
      archivedAt: _toDateTime(data['archivedAt']),
      createdAt: _toDateTime(data['createdAt']),
      updatedAt: _toDateTime(data['updatedAt']),
    );
  }

  // ---------------------------------------------------------------------------
  // Serialization — Dart → Firestore
  // ---------------------------------------------------------------------------

  /// Trả về [Map] để ghi lên Firestore.
  ///
  /// Document ID **không** được đưa vào map — ID được Firestore quản lý
  /// qua đường dẫn document, không phải qua trường dữ liệu.
  ///
  /// Dùng khi tạo mới hoặc ghi đè (`set`). Khi chỉ cập nhật một phần,
  /// repository nên dùng `update({...})` thay vì gọi hàm này.
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'position': position,
      'archivedAt': archivedAt != null ? Timestamp.fromDate(archivedAt!) : null,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'updatedAt': updatedAt != null
          ? Timestamp.fromDate(updatedAt!)
          : FieldValue.serverTimestamp(),
    };
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Chuyển an toàn một giá trị Firestore [Timestamp] hoặc `null` thành
  /// [DateTime]? — tránh lỗi khi trường vắng mặt hoặc kiểu không đúng.
  static DateTime? _toDateTime(Object? value) {
    if (value is Timestamp) return value.toDate();
    return null;
  }

  @override
  String toString() =>
      'TaskListModel(id: $id, name: $name, position: $position, '
      'isArchived: $isArchived)';
}
