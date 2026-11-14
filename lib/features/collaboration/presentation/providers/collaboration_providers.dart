import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../boards/data/boards_repository.dart';
import '../../../cards/data/card_model.dart';
import '../../../lists/presentation/providers/list_providers.dart';
import '../../data/collaboration_models.dart';
import '../../data/collaboration_repository.dart';
import '../../data/fake_collaboration_repository.dart';
import '../../data/firestore_collaboration_repository.dart';
import '../../domain/collaboration_rules.dart';

/// Provider cung cấp [CollaborationRepository].
///
/// Dùng [FirestoreCollaborationRepository] khi Firebase đã cấu hình và người
/// dùng đã đăng nhập; ngược lại dùng [FakeCollaborationRepository] (preview /
/// test). Lời mời trong bản giả không gieo sẵn để không hiện nhầm lúc mở app.
final collaborationRepositoryProvider = Provider<CollaborationRepository>((
  ref,
) {
  final userId = ref.watch(currentUserIdProvider).asData?.value;
  if (Firebase.apps.isNotEmpty && userId != null) {
    return FirestoreCollaborationRepository();
  }
  final repo = FakeCollaborationRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

/// uid người đang đăng nhập theo repository đang dùng.
final collaboratorIdProvider = Provider<String?>((ref) {
  return ref.watch(collaborationRepositoryProvider).currentUserId;
});

// Các luồng dưới đây tự hủy khi không còn màn hình nào dùng, để không giữ
// kênh nghe Firestore của mọi board/thẻ đã từng mở.

/// Board đang mở (tên, Owner, `memberIds`), thời gian thực.
final collaborationBoardProvider = StreamProvider.autoDispose
    .family<BoardSummary?, String>((ref, boardId) {
      return ref.watch(collaborationRepositoryProvider).watchBoard(boardId);
    });

/// Thành viên của board, Owner đứng đầu (UC06 bước 2).
final boardCollaboratorsProvider = StreamProvider.autoDispose
    .family<List<BoardMember>, String>((ref, boardId) {
      return ref.watch(collaborationRepositoryProvider).watchMembers(boardId);
    });

/// Lời mời đang chờ của board; chỉ Owner mới được đọc (UC06 bước 2).
final pendingInvitationsProvider = StreamProvider.autoDispose
    .family<List<BoardInvitation>, String>((ref, boardId) {
      return ref
          .watch(collaborationRepositoryProvider)
          .watchPendingInvitations(boardId);
    });

/// Lời mời đang chờ gửi tới email của người đang đăng nhập (UC06 bước 6–7).
final myInvitationsProvider = StreamProvider.autoDispose<List<BoardInvitation>>(
  (ref) {
    return ref.watch(collaborationRepositoryProvider).watchMyInvitations();
  },
);

/// Bình luận của một card, theo thời gian tạo (UC06 1d).
final cardCommentsProvider = StreamProvider.autoDispose
    .family<List<CardComment>, ({String boardId, String cardId})>((ref, key) {
      return ref
          .watch(collaborationRepositoryProvider)
          .watchComments(boardId: key.boardId, cardId: key.cardId);
    });

/// Thông báo khi mất kết nối với thao tác cần máy chủ xác nhận (UC06 10a).
const kCollaborationOfflineMessage =
    'Không kết nối được Firestore. Hãy kiểm tra Internet rồi thử lại.';

/// Chuyển lỗi thành thông báo tiếng Việt dễ hiểu.
String describeCollaborationError(Object error) {
  if (error is CollaborationException) return error.message;
  if (error is ArgumentError) {
    return error.message?.toString() ?? error.toString();
  }
  if (error is StateError) return error.message;
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return 'Bạn không có quyền thực hiện thao tác này.';
      case 'not-found':
        return 'Dữ liệu không còn tồn tại.';
      case 'unavailable':
      case 'network-request-failed':
      case 'deadline-exceeded':
        return kCollaborationOfflineMessage;
    }
    return 'Firestore báo lỗi: ${error.message ?? error.code}';
  }
  return error.toString().replaceFirst('Exception: ', '');
}

/// Thực hiện thao tác ghi của UC06. Mỗi hàm trả về thông báo lỗi, hoặc `null`
/// khi thành công, để giao diện tự hiển thị.
class CollaborationController {
  CollaborationController(this._repository);

  final CollaborationRepository _repository;

  /// Firestore giữ thao tác ghi trong hàng đợi khi mất mạng nên Future không
  /// kết thúc; quá thời gian này thì báo cho người dùng (UC06 10a).
  static const writeTimeout = Duration(seconds: 12);

  static const queuedOfflineMessage =
      'Không kết nối được Firestore. Thay đổi đã lưu trên máy và sẽ đồng bộ '
      'khi có mạng trở lại.';

  Future<String?> _run(
    Future<void> Function() action, {
    String timeoutMessage = kCollaborationOfflineMessage,
  }) async {
    try {
      await action().timeout(writeTimeout);
      return null;
    } on TimeoutException {
      return timeoutMessage;
    } catch (error) {
      return describeCollaborationError(error);
    }
  }

  Future<String?> inviteMember({
    required String boardId,
    required String email,
  }) => _run(() => _repository.inviteMember(boardId: boardId, email: email));

  Future<String?> cancelInvitation({
    required String boardId,
    required String normalizedEmail,
  }) => _run(
    () => _repository.cancelInvitation(
      boardId: boardId,
      normalizedEmail: normalizedEmail,
    ),
  );

  Future<String?> acceptInvitation(BoardInvitation invitation) =>
      _run(() => _repository.acceptInvitation(invitation));

  Future<String?> declineInvitation(BoardInvitation invitation) =>
      _run(() => _repository.declineInvitation(invitation));

  Future<String?> removeMember({
    required String boardId,
    required String memberUid,
  }) => _run(
    () => _repository.removeMember(boardId: boardId, memberUid: memberUid),
  );

  Future<String?> leaveBoard(String boardId) =>
      _run(() => _repository.leaveBoard(boardId));

  /// Bình luận được xếp hàng khi mất mạng và tự gửi khi có mạng lại.
  Future<String?> addComment({
    required String boardId,
    required String cardId,
    required String body,
  }) => _run(
    () => _repository.addComment(boardId: boardId, cardId: cardId, body: body),
    timeoutMessage: queuedOfflineMessage,
  );

  Future<String?> editComment({
    required String boardId,
    required String cardId,
    required String commentId,
    required String body,
  }) => _run(
    () => _repository.editComment(
      boardId: boardId,
      cardId: cardId,
      commentId: commentId,
      body: body,
    ),
    timeoutMessage: queuedOfflineMessage,
  );

  Future<String?> deleteComment({
    required String boardId,
    required String cardId,
    required String commentId,
  }) => _run(
    () => _repository.deleteComment(
      boardId: boardId,
      cardId: cardId,
      commentId: commentId,
    ),
  );
}

final collaborationControllerProvider = Provider<CollaborationController>((
  ref,
) {
  return CollaborationController(ref.watch(collaborationRepositoryProvider));
});
