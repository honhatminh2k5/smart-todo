import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_todo/features/cards/data/card_model.dart';
import 'package:smart_todo/features/cards/data/fake_card_repository.dart';
import 'package:smart_todo/features/cards/presentation/providers/card_providers.dart';

void main() {
  group('CardsController', () {
    const boardId = 'thesis_board';
    late FakeCardRepository repo;
    late ProviderContainer container;
    late CardsController cards;

    setUp(() {
      repo = FakeCardRepository();
      container = ProviderContainer(
        overrides: [cardRepositoryProvider.overrideWithValue(repo)],
      );
      cards = container.read(cardsControllerProvider);
    });

    tearDown(() {
      container.dispose();
      repo.dispose();
    });

    Future<BoardCardsSnapshot> snapshot() =>
        repo.watchBoardCards(boardId).first;

    Future<List<String>> titlesIn(String listId) async =>
        (await snapshot()).cardsInList(listId).map((c) => c.title).toList();

    Future<TaskCardModel> card(String id) async =>
        (await repo.watchCard(boardId: boardId, cardId: id).first)!;

    test('boardCardsProvider groups active cards by list', () async {
      final sub = container.listen(boardCardsProvider(boardId), (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final value = sub.read().value!;
      expect(value.cardsInList('list_todo').map((c) => c.id), [
        'card_read',
        'card_outline',
      ]);
      expect(value.cardsInList('list_doing').map((c) => c.id), ['card_erd']);
      sub.close();
    });

    test(
      'createCard appends to the end of the list and records creator',
      () async {
        final error = await cards.createCard(
          boardId: boardId,
          listId: 'list_todo',
          title: '  Viết chương 2  ',
          cardsInList: (await snapshot()).cardsInList('list_todo'),
        );

        expect(error, isNull);
        final todo = (await snapshot()).cardsInList('list_todo');
        expect(todo.last.title, 'Viết chương 2');
        expect(todo.last.position, 2048 + 1024);
        expect(todo.last.createdBy, 'preview_user');
        expect(todo.last.isCompleted, isFalse);
      },
    );

    test(
      'createCard returns the validation message for an empty title',
      () async {
        final error = await cards.createCard(
          boardId: boardId,
          listId: 'list_todo',
          title: '   ',
          cardsInList: const [],
        );

        expect(error, 'Tiêu đề thẻ không được để trống.');
        expect(await titlesIn('list_todo'), hasLength(2));
      },
    );

    test('setCompleted toggles completion', () async {
      await cards.setCompleted(
        boardId: boardId,
        cardId: 'card_outline',
        isCompleted: true,
      );
      expect((await card('card_outline')).isCompleted, isTrue);

      await cards.setCompleted(
        boardId: boardId,
        cardId: 'card_outline',
        isCompleted: false,
      );
      expect((await card('card_outline')).isCompleted, isFalse);
    });

    test('archiveCard hides the card from the board but keeps it', () async {
      await cards.archiveCard(boardId: boardId, cardId: 'card_erd');

      expect((await snapshot()).cardsInList('list_doing'), isEmpty);
      expect((await card('card_erd')).isArchived, isTrue);
    });

    test('deleteCard removes the card permanently', () async {
      await cards.deleteCard(boardId: boardId, cardId: 'card_erd');

      expect(
        await repo.watchCard(boardId: boardId, cardId: 'card_erd').first,
        isNull,
      );
    });

    test('moveCard reorders inside a list with one write', () async {
      final todo = (await snapshot()).cardsInList('list_todo');
      final error = await cards.moveCard(
        boardId: boardId,
        card: todo.last,
        toListId: 'list_todo',
        targetCards: todo,
        index: 0,
      );

      expect(error, isNull);
      expect(await titlesIn('list_todo'), [
        'Phác thảo chương 1',
        'Đọc tài liệu tham khảo',
      ]);
      expect((await card('card_outline')).position, 512);
    });

    test('moveCard moves a card to another list', () async {
      final current = await snapshot();
      await cards.moveCard(
        boardId: boardId,
        card: current.cardsInList('list_todo').first,
        toListId: 'list_doing',
        targetCards: current.cardsInList('list_doing'),
        index: 1,
      );

      expect(await titlesIn('list_doing'), [
        'Thiết kế ERD',
        'Đọc tài liệu tham khảo',
      ]);
      expect(await titlesIn('list_todo'), ['Phác thảo chương 1']);
    });

    test('moveCard is a no-op when dropped at its own position', () async {
      final todo = (await snapshot()).cardsInList('list_todo');
      final before = await card('card_read');

      await cards.moveCard(
        boardId: boardId,
        card: todo.first,
        toListId: 'list_todo',
        targetCards: todo,
        index: 0,
      );

      expect((await card('card_read')).updatedAt, before.updatedAt);
    });

    test('moveCard renumbers the list when positions are too close', () async {
      await repo.moveCard(
        boardId: boardId,
        cardId: 'card_outline',
        toListId: 'list_todo',
        position: 1024 + 1e-7,
      );
      final current = await snapshot();
      await cards.moveCard(
        boardId: boardId,
        card: current.cardsInList('list_doing').single,
        toListId: 'list_todo',
        targetCards: current.cardsInList('list_todo'),
        index: 1,
      );

      final todo = (await snapshot()).cardsInList('list_todo');
      expect(todo.map((c) => c.id), ['card_read', 'card_erd', 'card_outline']);
      expect(todo.map((c) => c.position), [1024, 2048, 3072]);
    });

    test('write errors are reported as a friendly message (UC05 8a)', () async {
      repo.writeError = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      );

      final error = await cards.setCompleted(
        boardId: boardId,
        cardId: 'card_read',
        isCompleted: true,
      );

      expect(error, startsWith('Không kết nối được Firestore'));
      expect((await card('card_read')).isCompleted, isFalse);
    });
  });
}
