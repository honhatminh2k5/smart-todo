import '../../boards/data/boards_repository.dart';
import '../../cards/data/card_model.dart';
import 'collaboration_models.dart';

/// Contract của data layer cho Cộng tác nhóm (UC06): thành viên, lời mời và
/// bình luận. Giao việc cho thành viên (W16) là thao tác ghi card nên nằm ở
/// `CardRepository.setAssignee`.
///
/// Hai implementation:
/// - [FirestoreCollaborationRepository]: kết nối Cloud Firestore.
/// - [FakeCollaborationRepository]: dữ liệu trong bộ nhớ cho preview và test.
abstract interface class CollaborationRepository {
  /// uid người đang đăng nhập, `null` nếu chưa đăng nhập.
  String? get currentUserId;

  /// Thông tin board (tên, Owner, `memberIds`); phát `null` khi board không
  /// tồn tại. Phát lỗi `permission-denied` khi người dùng mất quyền truy cập.
  Stream<BoardSummary?> watchBoard(String boardId);

  /// Thành viên của board kèm vai trò, Owner đứng đầu (UC06 bước 2).
  Stream<List<BoardMember>> watchMembers(String boardId);

  /// Lời mời đang chờ của board, chỉ Owner đọc được (UC06 bước 2).
  Stream<List<BoardInvitation>> watchPendingInvitations(String boardId);

  /// Lời mời đang chờ gửi tới email của người đang đăng nhập (UC06 bước 6–7).
  Stream<List<BoardInvitation>> watchMyInvitations();

  /// Owner mời [email] vào board (UC06 bước 3–5, W26). Kiểm tra email hợp lệ,
  /// chưa là thành viên và chưa có lời mời đang chờ (4a).
  Future<void> inviteMember({required String boardId, required String email});

  /// Owner hủy lời mời đang chờ (UC06 2a, W27).
  Future<void> cancelInvitation({
    required String boardId,
    required String normalizedEmail,
  });

  /// Người được mời chấp nhận (UC06 bước 8–9, W28). Ném
  /// [CollaborationException] khi lời mời không còn hiệu lực (9a).
  Future<void> acceptInvitation(BoardInvitation invitation);

  /// Người được mời từ chối (UC06 8a, W29).
  Future<void> declineInvitation(BoardInvitation invitation);

  /// Owner xóa Member khỏi board và khỏi người được giao của mọi card
  /// (UC06 2b–2c, W30).
  Future<void> removeMember({
    required String boardId,
    required String memberUid,
  });

  /// Member tự rời board; Owner không được rời (UC06 2d, W31).
  Future<void> leaveBoard(String boardId);

  /// Bình luận của card theo thứ tự thời gian tạo (UC06 1d).
  Stream<List<CardComment>> watchComments({
    required String boardId,
    required String cardId,
  });

  /// Gửi bình luận và tăng `commentCount` của card trong một batch (W23).
  Future<void> addComment({
    required String boardId,
    required String cardId,
    required String body,
  });

  /// Tác giả sửa nội dung bình luận của mình (W24).
  Future<void> editComment({
    required String boardId,
    required String cardId,
    required String commentId,
    required String body,
  });

  /// Tác giả hoặc Owner xóa bình luận và giảm `commentCount` (W25).
  Future<void> deleteComment({
    required String boardId,
    required String cardId,
    required String commentId,
  });
}
