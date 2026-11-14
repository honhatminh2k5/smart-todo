import 'card_model.dart';

/// Contract của data layer cho chức năng Quản lý card (UC05).
///
/// Hai implementation:
/// - [FirestoreCardRepository]: kết nối Cloud Firestore.
/// - [FakeCardRepository]: dữ liệu trong bộ nhớ cho preview và test.
abstract interface class CardRepository {
  /// Mọi card chưa lưu trữ của board qua **một** kênh nghe; giao diện tự nhóm
  /// theo `listId` (truy vấn B trong `firestore-access-patterns.md`).
  Stream<BoardCardsSnapshot> watchBoardCards(String boardId);

  /// Một card cụ thể; phát `null` khi card đã bị xóa (UC05 3g).
  Stream<TaskCardModel?> watchCard({
    required String boardId,
    required String cardId,
  });

  /// Nhãn của board, dùng để vẽ chip nhãn trên thẻ.
  Stream<List<CardLabel>> watchLabels(String boardId);

  /// Thành viên của board, dùng để vẽ avatar người được giao.
  Stream<List<BoardMember>> watchMembers(String boardId);

  /// Tạo card ở [position] trong list (W9). Tiêu đề được trim và kiểm tra
  /// 1–200 ký tự. Trả về ID card mới.
  Future<String> createCard({
    required String boardId,
    required String listId,
    required String title,
    required double position,
  });

  /// Sửa tiêu đề card (W10).
  Future<void> renameCard({
    required String boardId,
    required String cardId,
    required String title,
  });

  /// Đánh dấu hoặc bỏ đánh dấu hoàn thành (W11).
  Future<void> setCompleted({
    required String boardId,
    required String cardId,
    required bool isCompleted,
  });

  /// Lưu trữ card: card bị ẩn khỏi board nhưng không bị xóa (W13).
  Future<void> archiveCard({required String boardId, required String cardId});

  /// Xóa vĩnh viễn card cùng checklist và bình luận trong một batch (W14).
  Future<void> deleteCard({required String boardId, required String cardId});

  /// Chuyển card sang [toListId] (có thể là list hiện tại) tại [position] (W12).
  Future<void> moveCard({
    required String boardId,
    required String cardId,
    required String toListId,
    required double position,
  });

  /// Giao card cho [memberUid] ([assigned] = `true`) hoặc bỏ giao (W16,
  /// UC06 1b). Chỉ được chọn thành viên hiện tại của board (luật I3).
  Future<void> setAssignee({
    required String boardId,
    required String cardId,
    required String memberUid,
    required bool assigned,
  });

  /// Đánh số lại `position` của các card trong list theo [orderedCardIds]
  /// trong một batch; dùng khi hai vị trí liền kề quá sát nhau.
  Future<void> reorderCards({
    required String boardId,
    required String listId,
    required List<String> orderedCardIds,
  });
}
