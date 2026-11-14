import 'package:cloud_firestore/cloud_firestore.dart';

import '../../cards/data/card_model.dart';

/// Trạng thái lời mời (`docs/firestore-schema.md` § 4.4).
enum InvitationStatus {
  pending,
  accepted,
  declined;

  static InvitationStatus parse(Object? value) => switch (value) {
    'accepted' => InvitationStatus.accepted,
    'declined' => InvitationStatus.declined,
    _ => InvitationStatus.pending,
  };
}

/// Lời mời vào board: `boards/{boardId}/invitations/{normalizedEmail}`.
///
/// Dùng cho cả màn hình Thành viên của Owner (UC06 bước 2) và màn hình Lời
/// mời của người được mời (bước 7). `boardName`, `inviterName` là bản sao để
/// người được mời đọc được khi chưa là thành viên.
class BoardInvitation {
  const BoardInvitation({
    required this.boardId,
    required this.email,
    required this.normalizedEmail,
    required this.invitedBy,
    required this.inviterName,
    required this.boardName,
    this.status = InvitationStatus.pending,
    this.createdAt,
    this.updatedAt,
  });

  /// ID board cha, lấy từ đường dẫn của tờ lời mời.
  final String boardId;

  /// Email Owner đã nhập (giữ nguyên chữ hoa/thường).
  final String email;

  /// Email đã chuẩn hóa, cũng là ID của tờ lời mời.
  final String normalizedEmail;
  final String invitedBy;
  final String inviterName;
  final String boardName;
  final InvitationStatus status;

  /// Giờ máy chủ; `null` khi thao tác ghi chưa được máy chủ xác nhận.
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isPending => status == InvitationStatus.pending;

  factory BoardInvitation.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    final email = data['email'] as String? ?? document.id;
    return BoardInvitation(
      boardId: document.reference.parent.parent?.id ?? '',
      email: email,
      normalizedEmail: data['normalizedEmail'] as String? ?? document.id,
      invitedBy: data['invitedBy'] as String? ?? '',
      inviterName: data['inviterName'] as String? ?? '',
      boardName: data['boardName'] as String? ?? '(Chưa có tên)',
      status: InvitationStatus.parse(data['status']),
      createdAt: _toDateTime(data['createdAt']),
      updatedAt: _toDateTime(data['updatedAt']),
    );
  }

  BoardInvitation copyWith({
    InvitationStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? invitedBy,
    String? inviterName,
    String? boardName,
    String? email,
  }) {
    return BoardInvitation(
      boardId: boardId,
      email: email ?? this.email,
      normalizedEmail: normalizedEmail,
      invitedBy: invitedBy ?? this.invitedBy,
      inviterName: inviterName ?? this.inviterName,
      boardName: boardName ?? this.boardName,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Lời mời mới nhất lên trước; lời mời vừa gửi (chưa có giờ máy chủ) ở đầu.
  static int newestFirst(BoardInvitation a, BoardInvitation b) {
    final aTime = a.createdAt;
    final bTime = b.createdAt;
    if (aTime == null || bTime == null) {
      if (aTime != bTime) return aTime == null ? -1 : 1;
      return a.normalizedEmail.compareTo(b.normalizedEmail);
    }
    final byTime = bTime.compareTo(aTime);
    return byTime != 0
        ? byTime
        : a.normalizedEmail.compareTo(b.normalizedEmail);
  }
}

/// Bình luận của card: `boards/{boardId}/cards/{cardId}/comments/{commentId}`.
class CardComment {
  const CardComment({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.body,
    this.createdAt,
    this.updatedAt,
  });

  final String id;

  /// uid tác giả, không đổi.
  final String authorId;

  /// Tên tác giả lúc viết (bản sao để hiển thị, quyết định D10).
  final String authorName;

  /// Nội dung 1–2000 ký tự.
  final String body;

  /// Giờ máy chủ; `null` khi bình luận đang chờ gửi lên máy chủ.
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Chưa được máy chủ xác nhận (vừa gửi hoặc đang mất mạng).
  bool get isPending => createdAt == null;

  /// `updatedAt > createdAt` nghĩa là đã chỉnh sửa (schema § 5).
  bool get isEdited {
    final created = createdAt;
    final updated = updatedAt;
    return created != null && updated != null && updated.isAfter(created);
  }

  factory CardComment.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return CardComment(
      id: document.id,
      authorId: data['authorId'] as String? ?? '',
      authorName: data['authorName'] as String? ?? '',
      body: data['body'] as String? ?? '',
      createdAt: _toDateTime(data['createdAt']),
      updatedAt: _toDateTime(data['updatedAt']),
    );
  }

  CardComment copyWith({String? body, DateTime? updatedAt}) => CardComment(
    id: id,
    authorId: authorId,
    authorName: authorName,
    body: body ?? this.body,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// Thứ tự thời gian tạo; bình luận đang chờ gửi xếp sau cùng.
  static int oldestFirst(CardComment a, CardComment b) {
    final aTime = a.createdAt;
    final bTime = b.createdAt;
    if (aTime == null || bTime == null) {
      if (aTime != bTime) return aTime == null ? 1 : -1;
      return a.id.compareTo(b.id);
    }
    final byTime = aTime.compareTo(bTime);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  }
}

/// Owner đứng đầu, sau đó theo tên (không phân biệt hoa/thường).
int compareMembers(BoardMember a, BoardMember b) {
  if (a.role != b.role) return a.role == 'owner' ? -1 : 1;
  final byName = a.displayName.toLowerCase().compareTo(
    b.displayName.toLowerCase(),
  );
  return byName != 0 ? byName : a.uid.compareTo(b.uid);
}

DateTime? _toDateTime(Object? value) =>
    value is Timestamp ? value.toDate() : null;
