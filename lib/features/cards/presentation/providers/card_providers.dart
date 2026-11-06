import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_todo/features/cards/data/card_model.dart';
import 'package:smart_todo/features/cards/data/card_repository.dart';
import 'package:smart_todo/features/cards/data/fake_card_repository.dart';
import 'package:smart_todo/features/cards/data/firestore_card_repository.dart';
import 'package:smart_todo/features/cards/domain/card_rules.dart';
import 'package:smart_todo/features/lists/presentation/providers/list_providers.dart';

/// Provider cung cấp [CardRepository].
///
/// Dùng [FirestoreCardRepository] khi Firebase đã cấu hình và người dùng đã
/// đăng nhập; ngược lại dùng [FakeCardRepository] (preview / test).
final cardRepositoryProvider = Provider<CardRepository>((ref) {
  final userId = ref.watch(currentUserIdProvider).asData?.value;
  if (Firebase.apps.isNotEmpty && userId != null) {
    return FirestoreCardRepository();
  }
  final repo = FakeCardRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

/// Card chưa lưu trữ của một board, thời gian thực (UC05 bước 2, 8).
final boardCardsProvider = StreamProvider.family<BoardCardsSnapshot, String>((
  ref,
  boardId,
) {
  return ref.watch(cardRepositoryProvider).watchBoardCards(boardId);
});

/// Một card cụ thể; giá trị `null` nghĩa là card đã bị xóa (UC05 3g).
final cardDetailProvider =
    StreamProvider.family<TaskCardModel?, ({String boardId, String cardId})>((
      ref,
      key,
    ) {
      return ref
          .watch(cardRepositoryProvider)
          .watchCard(boardId: key.boardId, cardId: key.cardId);
    });

/// Nhãn của board, theo ID.
final boardLabelsProvider =
    StreamProvider.family<Map<String, CardLabel>, String>((ref, boardId) {
      return ref
          .watch(cardRepositoryProvider)
          .watchLabels(boardId)
          .map((labels) => {for (final label in labels) label.id: label});
    });

/// Thành viên của board, theo uid.
final boardMembersProvider =
    StreamProvider.family<Map<String, BoardMember>, String>((ref, boardId) {
      return ref
          .watch(cardRepositoryProvider)
          .watchMembers(boardId)
          .map((members) => {for (final member in members) member.uid: member});
    });

/// Chuyển lỗi thành thông báo tiếng Việt dễ hiểu.
String describeCardError(Object error) {
  if (error is ArgumentError) {
    return error.message?.toString() ?? error.toString();
  }
  if (error is StateError) return error.message;
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return 'Bạn không có quyền thực hiện thao tác này.';
      case 'not-found':
        return 'Thẻ không còn tồn tại.';
      case 'unavailable':
      case 'network-request-failed':
      case 'deadline-exceeded':
        return 'Không kết nối được Firestore. '
            'Hãy kiểm tra mạng rồi thử lại.';
    }
    return 'Firestore báo lỗi: ${error.message ?? error.code}';
  }
  return error.toString().replaceFirst('Exception: ', '');
}

/// Thực hiện thao tác ghi card. Mỗi hàm trả về thông báo lỗi, hoặc `null`
/// khi thành công, để giao diện tự hiển thị.
class CardsController {
  CardsController(this._repository);

  final CardRepository _repository;

  /// Firestore giữ thao tác ghi trong hàng đợi khi mất mạng nên Future không
  /// kết thúc; quá thời gian này thì báo cho người dùng (UC05 8a).
  static const writeTimeout = Duration(seconds: 10);

  static const queuedOfflineMessage =
      'Không kết nối được Firestore. Thay đổi đã lưu trên máy và sẽ đồng bộ '
      'khi có mạng trở lại.';

  Future<String?> _run(
    Future<void> Function() action, {
    String timeoutMessage = queuedOfflineMessage,
  }) async {
    try {
      await action().timeout(writeTimeout);
      return null;
    } on TimeoutException {
      return timeoutMessage;
    } catch (error) {
      return describeCardError(error);
    }
  }

  /// Thêm card vào cuối list (UC05 bước 5–7). [cardsInList] là các card hiện
  /// có của list, theo thứ tự hiển thị.
  Future<String?> createCard({
    required String boardId,
    required String listId,
    required String title,
    required List<TaskCardModel> cardsInList,
  }) {
    final last = cardsInList.isEmpty ? null : cardsInList.last;
    return _run(
      () => _repository.createCard(
        boardId: boardId,
        listId: listId,
        title: title,
        position: positionBetween(last?.position, null)!,
      ),
    );
  }

  Future<String?> renameCard({
    required String boardId,
    required String cardId,
    required String title,
  }) => _run(
    () =>
        _repository.renameCard(boardId: boardId, cardId: cardId, title: title),
  );

  Future<String?> setCompleted({
    required String boardId,
    required String cardId,
    required bool isCompleted,
  }) => _run(
    () => _repository.setCompleted(
      boardId: boardId,
      cardId: cardId,
      isCompleted: isCompleted,
    ),
  );

  Future<String?> archiveCard({
    required String boardId,
    required String cardId,
  }) => _run(() => _repository.archiveCard(boardId: boardId, cardId: cardId));

  /// Xóa cần đọc dữ liệu con từ máy chủ nên không có gì được xếp hàng khi
  /// quá thời gian chờ.
  Future<String?> deleteCard({
    required String boardId,
    required String cardId,
  }) => _run(
    () => _repository.deleteCard(boardId: boardId, cardId: cardId),
    timeoutMessage:
        'Không kết nối được Firestore. Hãy kiểm tra mạng rồi thử lại.',
  );

  /// Thả [card] vào vị trí [index] của list [toListId] (kéo thả).
  ///
  /// [targetCards] là các card hiện có của list đích theo thứ tự hiển thị (có
  /// thể chứa chính [card]); [index] tính trên danh sách đã bỏ [card].
  /// Chỉ ghi một document, trừ khi phải đánh số lại cả list.
  Future<String?> moveCard({
    required String boardId,
    required TaskCardModel card,
    required String toListId,
    required List<TaskCardModel> targetCards,
    required int index,
  }) async {
    final others = targetCards.where((c) => c.id != card.id).toList();
    final target = index.clamp(0, others.length);

    if (card.listId == toListId &&
        targetCards.indexWhere((c) => c.id == card.id) == target) {
      return null;
    }

    final before = target > 0 ? others[target - 1].position : null;
    final after = target < others.length ? others[target].position : null;
    final position = positionBetween(before, after);
    if (position != null) {
      return _run(
        () => _repository.moveCard(
          boardId: boardId,
          cardId: card.id,
          toListId: toListId,
          position: position,
        ),
      );
    }

    final ordered = [...others.map((c) => c.id)]..insert(target, card.id);
    return _run(
      () => _repository.reorderCards(
        boardId: boardId,
        listId: toListId,
        orderedCardIds: ordered,
      ),
    );
  }
}

final cardsControllerProvider = Provider<CardsController>((ref) {
  return CardsController(ref.watch(cardRepositoryProvider));
});
