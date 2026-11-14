/// Quy tắc nghiệp vụ dùng chung cho Cộng tác nhóm (UC06).
///
/// Giao diện, `FirestoreCollaborationRepository` và
/// `FakeCollaborationRepository` cùng gọi các hàm ở đây để kiểm tra giống
/// nhau và khớp với `firestore.rules`.
library;

/// Độ dài tối đa của email (giới hạn của `firestore.rules`).
const int kEmailMaxLength = 254;

/// Độ dài tối đa của một bình luận (UC06 1d).
const int kCommentMaxLength = 2000;

/// Độ dài tối đa của tên được sao chép vào lời mời, thành viên, bình luận.
const int kDisplayNameMaxLength = 100;

/// Giống biểu thức `^[^@ ]+@[^@ ]+[.][^@ ]+$` trong `firestore.rules`, chặt
/// hơn một chút (không cho mọi loại khoảng trắng).
final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Thông báo khi lời mời đã bị Owner hủy hoặc đã được trả lời (UC06 9a).
const String kInvitationNoLongerValid =
    'Lời mời không còn hiệu lực. Có thể Owner đã hủy lời mời này.';

/// Lỗi nghiệp vụ có thông báo hiển thị thẳng cho người dùng.
class CollaborationException implements Exception {
  const CollaborationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Email chuẩn hóa: bỏ khoảng trắng đầu/cuối và viết thường (quy ước Q9).
/// Đây cũng là ID của tờ lời mời `invitations/{normalizedEmail}`.
String normalizeEmail(String email) => email.trim().toLowerCase();

/// Trả về thông báo lỗi nếu email mời không hợp lệ (UC06 4a), `null` nếu
/// hợp lệ.
String? validateInviteEmail(String? raw) {
  final email = raw?.trim() ?? '';
  if (email.isEmpty) return 'Hãy nhập email người được mời.';
  if (email.length > kEmailMaxLength || !_emailPattern.hasMatch(email)) {
    return 'Email không đúng định dạng.';
  }
  return null;
}

/// Trả về thông báo lỗi nếu nội dung bình luận không hợp lệ (UC06 1d),
/// `null` nếu hợp lệ.
String? validateCommentBody(String? raw) {
  final body = raw?.trim() ?? '';
  if (body.isEmpty) return 'Nội dung bình luận không được để trống.';
  if (body.length > kCommentMaxLength) {
    return 'Bình luận tối đa $kCommentMaxLength ký tự.';
  }
  return null;
}

/// Làm sạch nội dung bình luận; ném [ArgumentError] nếu không hợp lệ.
String normalizeCommentBody(String raw) {
  final error = validateCommentBody(raw);
  if (error != null) throw ArgumentError(error);
  return raw.trim();
}

/// Tên hiển thị để sao chép vào lời mời, thành viên, bình luận (quyết định
/// D10): tên tài khoản, hoặc email khi chưa đặt tên; cắt còn 100 ký tự.
String displayNameFor({String? displayName, String? email}) {
  final name = displayName?.trim() ?? '';
  final fallback = name.isNotEmpty ? name : (email?.trim() ?? '');
  if (fallback.isEmpty) return 'Thành viên';
  return fallback.length > kDisplayNameMaxLength
      ? fallback.substring(0, kDisplayNameMaxLength)
      : fallback;
}
