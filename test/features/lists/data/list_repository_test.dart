import 'package:flutter_test/flutter_test.dart';
import 'package:smart_todo/features/boards/domain/board_models.dart';
import 'package:smart_todo/features/lists/data/fake_list_repository.dart';

void main() {
  group('FakeListRepository (ListRepository implementation)', () {
    late FakeListRepository repository;
    const boardId = 'thesis_board';

    setUp(() {
      repository = FakeListRepository();
    });

    tearDown(() {
      repository.dispose();
    });

    test('getListsByBoardId returns active lists ordered by position', () async {
      final stream = repository.getListsByBoardId(boardId);

      final lists = await stream.first;
      expect(lists.length, 3);
      expect(lists[0].name, 'Cần làm');
      expect(lists[0].position, 1000.0);
      expect(lists[1].name, 'Đang làm');
      expect(lists[1].position, 2000.0);
      expect(lists[2].name, 'Hoàn thành');
      expect(lists[2].position, 3000.0);
      expect(lists.every((l) => !l.isArchived), isTrue);
    });

    test('createList adds a new list with calculated position and timestamps', () async {
      final newId = await repository.createList(
        boardId: boardId,
        name: 'Kiểm thử',
      );

      expect(newId, isNotEmpty);

      final lists = await repository.getListsByBoardId(boardId).first;
      expect(lists.length, 4);

      final created = lists.firstWhere((l) => l.id == newId);
      expect(created.name, 'Kiểm thử');
      expect(created.position, 4000.0); // max (3000) + 1000
      expect(created.archivedAt, isNull);
      expect(created.createdAt, isNotNull);
      expect(created.updatedAt, isNotNull);
    });

    test('updateList updates fields without overwriting createdAt', () async {
      final initialLists = await repository.getListsByBoardId(boardId).first;
      final target = initialLists.first;
      final originalCreatedAt = target.createdAt;

      await Future<void>.delayed(const Duration(milliseconds: 10));

      await repository.updateList(
        boardId: boardId,
        listId: target.id,
        name: 'Cần làm gấp',
      );

      final updatedLists = await repository.getListsByBoardId(boardId).first;
      final updated = updatedLists.firstWhere((l) => l.id == target.id);

      expect(updated.name, 'Cần làm gấp');
      expect(updated.createdAt, equals(originalCreatedAt));
      expect(updated.updatedAt!.isAfter(originalCreatedAt!), isTrue);
    });

    test('deleteList soft-deletes list and does NOT delete cards', () async {
      // Thêm card demo vào list_todo
      repository.addCardToList(
        boardId: boardId,
        listId: 'list_todo',
        card: const BoardCard(title: 'Card thử nghiệm'),
      );

      expect(
        repository.getCardsForList(boardId: boardId, listId: 'list_todo').length,
        3,
      );

      // Xóa list_todo
      await repository.deleteList(boardId: boardId, listId: 'list_todo');

      // Danh sách active không còn list_todo
      final activeLists = await repository.getListsByBoardId(boardId).first;
      expect(activeLists.any((l) => l.id == 'list_todo'), isFalse);

      // Card vẫn còn nguyên vẹn trong list_todo
      final cards = repository.getCardsForList(boardId: boardId, listId: 'list_todo');
      expect(cards.length, 3);
      expect(cards.any((c) => c.title == 'Card thử nghiệm'), isTrue);
    });

    test('reorderLists updates positions in given order', () async {
      await repository.reorderLists(
        boardId: boardId,
        orderedListIds: ['list_done', 'list_doing', 'list_todo'],
      );

      final lists = await repository.getListsByBoardId(boardId).first;
      expect(lists[0].id, 'list_done');
      expect(lists[0].position, 1000.0);

      expect(lists[1].id, 'list_doing');
      expect(lists[1].position, 2000.0);

      expect(lists[2].id, 'list_todo');
      expect(lists[2].position, 3000.0);
    });

    test('unarchiveList restores an archived list', () async {
      await repository.archiveList(boardId: boardId, listId: 'list_todo');

      var lists = await repository.getListsByBoardId(boardId).first;
      expect(lists.any((l) => l.id == 'list_todo'), isFalse);

      await repository.unarchiveList(boardId: boardId, listId: 'list_todo');

      lists = await repository.getListsByBoardId(boardId).first;
      expect(lists.any((l) => l.id == 'list_todo'), isTrue);
    });
  });
}
