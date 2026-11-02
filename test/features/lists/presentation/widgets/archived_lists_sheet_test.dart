import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_todo/features/lists/data/fake_list_repository.dart';
import 'package:smart_todo/features/lists/data/list_model.dart';
import 'package:smart_todo/features/lists/presentation/providers/list_providers.dart';
import 'package:smart_todo/features/lists/presentation/widgets/archived_lists_sheet.dart';

class _FailingRestoreRepository extends FakeListRepository {
  @override
  Future<void> unarchiveList({
    required String boardId,
    required String listId,
  }) async {
    throw StateError('restore failed');
  }
}

class _CountingRestoreRepository extends FakeListRepository {
  var unarchiveCalls = 0;

  @override
  Future<void> unarchiveList({
    required String boardId,
    required String listId,
  }) async {
    unarchiveCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await super.unarchiveList(boardId: boardId, listId: listId);
  }
}

void main() {
  const boardId = 'thesis_board';

  Widget buildTestWidget(FakeListRepository repository) {
    return ProviderScope(
      overrides: [listRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(
        home: Scaffold(body: ArchivedListsSheet(boardId: boardId)),
      ),
    );
  }

  group('ArchivedListsSheet', () {
    testWidgets('shows archived lists for the current board', (tester) async {
      final repository = FakeListRepository();
      await repository.archiveList(boardId: boardId, listId: 'list_todo');

      await tester.pumpWidget(buildTestWidget(repository));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Danh sách đã lưu trữ'), findsOneWidget);
      expect(find.text('Cần làm'), findsOneWidget);
      expect(find.text('Khôi phục'), findsOneWidget);
      expect(find.text('Đang làm'), findsNothing);

      repository.dispose();
    });

    testWidgets('shows empty state when there are no archived lists', (
      tester,
    ) async {
      final repository = FakeListRepository();

      await tester.pumpWidget(buildTestWidget(repository));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Chưa có danh sách đã lưu trữ'), findsOneWidget);
      expect(find.text('Khôi phục'), findsNothing);

      repository.dispose();
    });

    testWidgets('restores a list and removes it from the archived stream', (
      tester,
    ) async {
      final repository = FakeListRepository();
      await repository.archiveList(boardId: boardId, listId: 'list_todo');

      await tester.pumpWidget(buildTestWidget(repository));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Khôi phục'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(find.text('Cần làm'), findsNothing);
      final active = await repository.getListsByBoardId(boardId).first;
      expect(active.any((list) => list.id == 'list_todo'), isTrue);

      repository.dispose();
    });

    testWidgets('shows error state with retry action', (tester) async {
      final repository = FakeListRepository();
      final archivedProvider = archivedBoardListsStreamProvider(boardId)
          .overrideWithValue(
            AsyncError<List<TaskListModel>>(
              Exception('archive unavailable'),
              StackTrace.current,
            ),
          );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            listRepositoryProvider.overrideWithValue(repository),
            archivedProvider,
          ],
          child: const MaterialApp(
            home: Scaffold(body: ArchivedListsSheet(boardId: boardId)),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Không tải được danh sách đã lưu trữ'), findsOneWidget);
      expect(find.text('Thử lại'), findsOneWidget);

      repository.dispose();
    });

    testWidgets('shows a snackbar when restore fails', (tester) async {
      final repository = _FailingRestoreRepository();
      await repository.archiveList(boardId: boardId, listId: 'list_todo');

      await tester.pumpWidget(buildTestWidget(repository));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Khôi phục'));
      await tester.pumpAndSettle();

      expect(find.textContaining('restore failed'), findsOneWidget);

      repository.dispose();
    });

    testWidgets('does not submit duplicate restore requests', (tester) async {
      final repository = _CountingRestoreRepository();
      await repository.archiveList(boardId: boardId, listId: 'list_todo');

      await tester.pumpWidget(buildTestWidget(repository));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Khôi phục'));
      await tester.tap(find.text('Khôi phục'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(repository.unarchiveCalls, 1);
      expect(find.text('Cáº§n lÃ m'), findsNothing);

      repository.dispose();
    });
  });
}
