import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_todo/features/lists/data/fake_list_repository.dart';
import 'package:smart_todo/features/lists/data/list_model.dart';
import 'package:smart_todo/features/lists/presentation/providers/list_providers.dart';

void main() {
  group('List Providers & BoardListsController', () {
    late FakeListRepository fakeRepo;
    late ProviderContainer container;
    const boardId = 'thesis_board';

    setUp(() {
      fakeRepo = FakeListRepository();
      container = ProviderContainer(
        overrides: [
          listRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
    });

    tearDown(() {
      container.dispose();
      fakeRepo.dispose();
    });

    test('boardListsStreamProvider emits active lists for given boardId',
        () async {
      AsyncValue<List<TaskListModel>>? state;
      container.listen(
        boardListsStreamProvider(boardId),
        (_, next) => state = next,
        fireImmediately: true,
      );

      // Cho Stream phát giá trị đầu tiên
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(state, isNotNull);
      expect(state!.hasValue, isTrue);
      final lists = state!.value!;
      expect(lists.length, 3);
      expect(lists[0].name, 'Cần làm');
      expect(lists[1].name, 'Đang làm');
      expect(lists[2].name, 'Hoàn thành');
    });

    test('createList creates list and updates state', () async {
      final controller =
          container.read(boardListsControllerProvider.notifier);

      final success = await controller.createList(
        boardId: boardId,
        name: 'Danh sách mới',
      );

      expect(success, isTrue);
      expect(container.read(boardListsControllerProvider).isLoading, isFalse);
      expect(container.read(boardListsControllerProvider).hasError, isFalse);

      final lists = await fakeRepo.getListsByBoardId(boardId).first;
      expect(lists.any((l) => l.name == 'Danh sách mới'), isTrue);
    });

    test('createList with invalid name sets error state', () async {
      final controller =
          container.read(boardListsControllerProvider.notifier);

      final success = await controller.createList(
        boardId: boardId,
        name: '   ',
      );

      expect(success, isFalse);
      final state = container.read(boardListsControllerProvider);
      expect(state.isLoading, isFalse);
      expect(state.hasError, isTrue);
      expect(state.errorMessage, contains('từ 1 đến 100 ký tự'));

      controller.clearError();
      expect(container.read(boardListsControllerProvider).hasError, isFalse);
    });

    test('renameList updates list name', () async {
      final controller =
          container.read(boardListsControllerProvider.notifier);

      final success = await controller.renameList(
        boardId: boardId,
        listId: 'list_todo',
        newName: 'Việc cần làm ngay',
      );

      expect(success, isTrue);
      final lists = await fakeRepo.getListsByBoardId(boardId).first;
      expect(lists.firstWhere((l) => l.id == 'list_todo').name,
          'Việc cần làm ngay');
    });

    test('archiveList and unarchiveList toggle archive state', () async {
      final controller =
          container.read(boardListsControllerProvider.notifier);

      // Archive
      final archiveSuccess = await controller.archiveList(
        boardId: boardId,
        listId: 'list_todo',
      );
      expect(archiveSuccess, isTrue);

      var activeLists = await fakeRepo.getListsByBoardId(boardId).first;
      expect(activeLists.any((l) => l.id == 'list_todo'), isFalse);

      // Unarchive
      final unarchiveSuccess = await controller.unarchiveList(
        boardId: boardId,
        listId: 'list_todo',
      );
      expect(unarchiveSuccess, isTrue);

      activeLists = await fakeRepo.getListsByBoardId(boardId).first;
      expect(activeLists.any((l) => l.id == 'list_todo'), isTrue);
    });

    test('deleteList soft-deletes list', () async {
      final controller =
          container.read(boardListsControllerProvider.notifier);

      final success = await controller.deleteList(
        boardId: boardId,
        listId: 'list_doing',
      );

      expect(success, isTrue);
      final activeLists = await fakeRepo.getListsByBoardId(boardId).first;
      expect(activeLists.any((l) => l.id == 'list_doing'), isFalse);
    });

    test('reorderLists changes position order', () async {
      final controller =
          container.read(boardListsControllerProvider.notifier);

      final success = await controller.reorderLists(
        boardId: boardId,
        orderedListIds: ['list_done', 'list_doing', 'list_todo'],
      );

      expect(success, isTrue);
      final activeLists = await fakeRepo.getListsByBoardId(boardId).first;
      expect(activeLists[0].id, 'list_done');
      expect(activeLists[1].id, 'list_doing');
      expect(activeLists[2].id, 'list_todo');
    });
  });
}
