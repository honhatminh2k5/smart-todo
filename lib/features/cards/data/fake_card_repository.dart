import 'dart:async';

import '../domain/card_rules.dart';
import 'card_model.dart';
import 'card_repository.dart';

/// Triển khai [CardRepository] hoàn toàn trong bộ nhớ.
///
/// Phục vụ preview khi chưa cấu hình Firebase và test không cần Firestore.
/// Dữ liệu mẫu dùng cùng board/list với `FakeListRepository`.
class FakeCardRepository implements CardRepository {
  FakeCardRepository({bool seed = true, this.currentUserId = 'preview_user'}) {
    if (seed) _seed();
  }

  /// uid được ghi vào `createdBy` khi tạo card.
  final String currentUserId;

  /// Khi khác `null`, mọi thao tác ghi ném lỗi này (giả lập mất kết nối).
  Object? writeError;

  // boardId -> cardId -> card (gồm cả card đã lưu trữ)
  final Map<String, Map<String, TaskCardModel>> _cards = {};
  final Map<String, List<CardLabel>> _labels = {};
  final Map<String, List<BoardMember>> _members = {};
  final Map<String, StreamController<void>> _changes = {};
  int _nextId = 0;

  // ---------------------------------------------------------------------------
  // Seed data
  // ---------------------------------------------------------------------------

  void _seed() {
    const boardId = 'thesis_board';
    final created = DateTime(2026, 10, 1);

    _labels[boardId] = const [
      CardLabel(id: 'label_urgent', name: 'Gấp', color: 0xFFE53935),
      CardLabel(id: 'label_docs', name: 'Tài liệu', color: 0xFF1E88E5),
    ];
    _members[boardId] = const [
      BoardMember(
        uid: 'preview_user',
        displayName: 'Người dùng xem trước',
        email: 'preview@example.com',
        role: 'owner',
      ),
      BoardMember(
        uid: 'member_an',
        displayName: 'Nguyễn An',
        email: 'an@example.com',
        role: 'member',
      ),
    ];

    _cards[boardId] = {
      for (final card in [
        TaskCardModel(
          id: 'card_read',
          boardId: boardId,
          listId: 'list_todo',
          title: 'Đọc tài liệu tham khảo',
          position: 1024,
          labelIds: const ['label_docs'],
          assigneeIds: const ['preview_user'],
          dueAt: DateTime(2026, 12, 15, 17),
          commentCount: 2,
          checklistTotal: 3,
          checklistDone: 1,
          createdBy: 'preview_user',
          createdAt: created,
          updatedAt: created,
        ),
        TaskCardModel(
          id: 'card_outline',
          boardId: boardId,
          listId: 'list_todo',
          title: 'Phác thảo chương 1',
          position: 2048,
          createdBy: 'preview_user',
          createdAt: created,
          updatedAt: created,
        ),
        TaskCardModel(
          id: 'card_erd',
          boardId: boardId,
          listId: 'list_doing',
          title: 'Thiết kế ERD',
          position: 1024,
          labelIds: const ['label_urgent'],
          assigneeIds: const ['member_an'],
          createdBy: 'member_an',
          createdAt: created,
          updatedAt: created,
        ),
        TaskCardModel(
          id: 'card_topic',
          boardId: boardId,
          listId: 'list_done',
          title: 'Đặt tên đề tài',
          position: 1024,
          isCompleted: true,
          createdBy: 'preview_user',
          createdAt: created,
          updatedAt: created,
        ),
      ])
        card.id: card,
    };
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Map<String, TaskCardModel> _boardCards(String boardId) =>
      _cards.putIfAbsent(boardId, () => {});

  Stream<T> _watch<T>(String boardId, T Function() read) async* {
    final changes = _changes.putIfAbsent(
      boardId,
      () => StreamController<void>.broadcast(),
    );
    yield read();
    yield* changes.stream.map((_) => read());
  }

  void _emit(String boardId) {
    final changes = _changes[boardId];
    if (changes != null && !changes.isClosed) changes.add(null);
  }

  void _checkWritable() {
    final error = writeError;
    if (error != null) throw error;
  }

  TaskCardModel _find(String boardId, String cardId) {
    final card = _boardCards(boardId)[cardId];
    if (card == null) throw StateError('Thẻ không còn tồn tại.');
    return card;
  }

  void _put(TaskCardModel card) {
    _boardCards(card.boardId)[card.id] = card;
    _emit(card.boardId);
  }

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  @override
  Stream<BoardCardsSnapshot> watchBoardCards(String boardId) => _watch(
    boardId,
    () => BoardCardsSnapshot(
      cards: _boardCards(
        boardId,
      ).values.where((card) => !card.isArchived).toList(),
    ),
  );

  @override
  Stream<TaskCardModel?> watchCard({
    required String boardId,
    required String cardId,
  }) => _watch(boardId, () => _boardCards(boardId)[cardId]);

  @override
  Stream<List<CardLabel>> watchLabels(String boardId) =>
      _watch(boardId, () => _labels[boardId] ?? const []);

  @override
  Stream<List<BoardMember>> watchMembers(String boardId) =>
      _watch(boardId, () => _members[boardId] ?? const []);

  // ---------------------------------------------------------------------------
  // Write
  // ---------------------------------------------------------------------------

  @override
  Future<String> createCard({
    required String boardId,
    required String listId,
    required String title,
    required double position,
  }) async {
    final cleanTitle = normalizeCardTitle(title);
    _checkWritable();
    final now = DateTime.now();
    final card = TaskCardModel(
      id: 'card_${_nextId++}',
      boardId: boardId,
      listId: listId,
      title: cleanTitle,
      position: position,
      createdBy: currentUserId,
      createdAt: now,
      updatedAt: now,
    );
    _put(card);
    return card.id;
  }

  @override
  Future<void> renameCard({
    required String boardId,
    required String cardId,
    required String title,
  }) async {
    final cleanTitle = normalizeCardTitle(title);
    _checkWritable();
    _put(
      _find(
        boardId,
        cardId,
      ).copyWith(title: cleanTitle, updatedAt: DateTime.now()),
    );
  }

  @override
  Future<void> setCompleted({
    required String boardId,
    required String cardId,
    required bool isCompleted,
  }) async {
    _checkWritable();
    _put(
      _find(
        boardId,
        cardId,
      ).copyWith(isCompleted: isCompleted, updatedAt: DateTime.now()),
    );
  }

  @override
  Future<void> archiveCard({
    required String boardId,
    required String cardId,
  }) async {
    _checkWritable();
    final now = DateTime.now();
    _put(_find(boardId, cardId).copyWith(archivedAt: now, updatedAt: now));
  }

  @override
  Future<void> deleteCard({
    required String boardId,
    required String cardId,
  }) async {
    _checkWritable();
    _find(boardId, cardId);
    _boardCards(boardId).remove(cardId);
    _emit(boardId);
  }

  @override
  Future<void> moveCard({
    required String boardId,
    required String cardId,
    required String toListId,
    required double position,
  }) async {
    _checkWritable();
    _put(
      _find(boardId, cardId).copyWith(
        listId: toListId,
        position: position,
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> reorderCards({
    required String boardId,
    required String listId,
    required List<String> orderedCardIds,
  }) async {
    _checkWritable();
    final cards = _boardCards(boardId);
    for (var i = 0; i < orderedCardIds.length; i++) {
      final card = cards[orderedCardIds[i]];
      if (card == null) continue;
      cards[card.id] = card.copyWith(
        listId: listId,
        position: (i + 1) * kCardPositionStep,
        updatedAt: DateTime.now(),
      );
    }
    _emit(boardId);
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  void dispose() {
    for (final changes in _changes.values) {
      changes.close();
    }
    _changes.clear();
  }
}
