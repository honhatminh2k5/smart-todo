/// Quy tắc nghiệp vụ dùng chung cho card (UC05).
///
/// Giao diện, `FirestoreCardRepository` và `FakeCardRepository` cùng gọi các
/// hàm ở đây để kiểm tra giống nhau và khớp với `firestore.rules`.
library;

/// Độ dài tối đa của tiêu đề card (UC05 bước 6).
const int kCardTitleMaxLength = 200;

/// Khoảng cách `position` giữa hai card liền kề
/// (xem `docs/firestore-access-patterns.md` § 5).
const double kCardPositionStep = 1024.0;

/// Hai vị trí liền kề sát nhau hơn mức này thì phải đánh số lại cả list.
const double kMinPositionGap = 0.000001;

/// Trả về thông báo lỗi nếu tiêu đề không hợp lệ (UC05 5a), `null` nếu hợp lệ.
String? validateCardTitle(String? raw) {
  final title = raw?.trim() ?? '';
  if (title.isEmpty) return 'Tiêu đề thẻ không được để trống.';
  if (title.length > kCardTitleMaxLength) {
    return 'Tiêu đề thẻ tối đa $kCardTitleMaxLength ký tự.';
  }
  return null;
}

/// Làm sạch tiêu đề; ném [ArgumentError] nếu không hợp lệ.
String normalizeCardTitle(String raw) {
  final error = validateCardTitle(raw);
  if (error != null) throw ArgumentError(error);
  return raw.trim();
}

/// Vị trí mới khi chèn giữa [before] và [after] (`null` nếu không có phần tử).
///
/// Trả về `null` khi hai vị trí quá sát nhau: lúc đó phải đánh số lại cả list.
double? positionBetween(double? before, double? after) {
  if (before == null && after == null) return kCardPositionStep;
  if (after == null) return before! + kCardPositionStep;
  final lower = before ?? 0;
  if (after - lower < kMinPositionGap) return null;
  return (lower + after) / 2;
}

/// Trạng thái hạn chót hiển thị trên thẻ (`firestore-access-patterns.md` § 6).
enum CardDueStatus { completed, none, overdue, dueSoon, normal }

CardDueStatus dueStatusOf({
  required bool isCompleted,
  required DateTime? dueAt,
  required DateTime now,
}) {
  if (isCompleted) return CardDueStatus.completed;
  if (dueAt == null) return CardDueStatus.none;
  if (dueAt.isBefore(now)) return CardDueStatus.overdue;
  if (!dueAt.isAfter(now.add(const Duration(hours: 24)))) {
    return CardDueStatus.dueSoon;
  }
  return CardDueStatus.normal;
}
