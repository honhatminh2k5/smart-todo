import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_todo/features/lists/data/fake_list_repository.dart';
import 'package:smart_todo/features/lists/presentation/providers/list_providers.dart';
import 'package:smart_todo/features/lists/presentation/widgets/board_lists_section.dart';

void main() {
  group('BoardListsSection Widget', () {
    const boardId = 'thesis_board';

    testWidgets('renders active list columns from provider', (tester) async {
      final fakeRepo = FakeListRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [listRepositoryProvider.overrideWithValue(fakeRepo)],
          child: const MaterialApp(
            home: Scaffold(body: BoardListsSection(boardId: boardId)),
          ),
        ),
      );

      // Cho stream phát dữ liệu và render
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(find.text('Danh sách công việc'), findsOneWidget);
      expect(find.text('Cần làm'), findsOneWidget);
      expect(find.text('Đang làm'), findsOneWidget);

      // Mỗi cột có vùng cuộn thẻ riêng; vùng cuộn đầu tiên là board (ngang).
      await tester.scrollUntilVisible(
        find.text('Hoàn thành'),
        400,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Hoàn thành'), findsOneWidget);
      expect(find.text('Đặt tên đề tài'), findsOneWidget);
      expect(find.text('1 thẻ'), findsWidgets);

      fakeRepo.dispose();
    });

    testWidgets('renders empty state when board has no lists', (tester) async {
      final fakeRepo = FakeListRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [listRepositoryProvider.overrideWithValue(fakeRepo)],
          child: const MaterialApp(
            home: Scaffold(body: BoardListsSection(boardId: 'empty_board')),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(find.text('Chưa có danh sách nào'), findsOneWidget);
      expect(
        find.textContaining('Board này chưa có danh sách công việc'),
        findsOneWidget,
      );

      fakeRepo.dispose();
    });

    testWidgets('creates a list through the controller', (tester) async {
      final fakeRepo = FakeListRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [listRepositoryProvider.overrideWithValue(fakeRepo)],
          child: const MaterialApp(
            home: Scaffold(body: BoardListsSection(boardId: 'empty_board')),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(OutlinedButton));
      await tester.pump();

      await tester.enterText(find.byType(TextFormField), 'Việc cần làm');
      await tester.tap(find.text('Thêm'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(find.text('Việc cần làm'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsOneWidget);

      fakeRepo.dispose();
    });

    testWidgets('submits exactly once when Enter is pressed', (tester) async {
      final fakeRepo = FakeListRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [listRepositoryProvider.overrideWithValue(fakeRepo)],
          child: const MaterialApp(
            home: Scaffold(body: BoardListsSection(boardId: 'empty_board')),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(OutlinedButton));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField), 'Enter only');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      final lists = await fakeRepo.getListsByBoardId('empty_board').first;
      expect(lists.where((list) => list.name == 'Enter only'), hasLength(1));

      fakeRepo.dispose();
    });

    testWidgets('submits exactly once when Add is pressed', (tester) async {
      final fakeRepo = FakeListRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [listRepositoryProvider.overrideWithValue(fakeRepo)],
          child: const MaterialApp(
            home: Scaffold(body: BoardListsSection(boardId: 'empty_board')),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(OutlinedButton));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField), 'Add only');
      await tester.tap(find.byType(FilledButton));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      final lists = await fakeRepo.getListsByBoardId('empty_board').first;
      expect(lists.where((list) => list.name == 'Add only'), hasLength(1));

      fakeRepo.dispose();
    });

    testWidgets('renames a list through the controller', (tester) async {
      final fakeRepo = FakeListRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [listRepositoryProvider.overrideWithValue(fakeRepo)],
          child: const MaterialApp(
            home: Scaffold(body: BoardListsSection(boardId: boardId)),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Cần làm'));
      await tester.pump();

      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.text('Cần làm'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '  Đang làm ngay  ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(find.text('Đang làm ngay'), findsOneWidget);
      expect(find.text('Cần làm'), findsNothing);

      await tester.tap(find.text('Đang làm ngay'));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField), 'Tên tạm thời');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(find.text('Đang làm ngay'), findsOneWidget);
      expect(find.text('Tên tạm thời'), findsNothing);

      fakeRepo.dispose();
    });

    testWidgets('archives a list after confirmation', (tester) async {
      final fakeRepo = FakeListRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [listRepositoryProvider.overrideWithValue(fakeRepo)],
          child: const MaterialApp(
            home: Scaffold(body: BoardListsSection(boardId: boardId)),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();

      expect(find.text('Lưu trữ danh sách'), findsOneWidget);
      await tester.tap(find.text('Lưu trữ danh sách'));
      await tester.pumpAndSettle();

      expect(find.text('Lưu trữ danh sách?'), findsOneWidget);
      expect(find.textContaining('Cần làm'), findsNWidgets(2));

      await tester.tap(find.text('Lưu trữ'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(find.text('Cần làm'), findsNothing);
      expect(find.text('Đang làm'), findsOneWidget);
      expect(find.text('Hoàn thành'), findsOneWidget);

      fakeRepo.dispose();
    });

    testWidgets('reorders lists after drag and drop', (tester) async {
      final fakeRepo = FakeListRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [listRepositoryProvider.overrideWithValue(fakeRepo)],
          child: const MaterialApp(
            home: Scaffold(body: BoardListsSection(boardId: boardId)),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 50));
      // Nhấn giữ tiêu đề cột để kéo list (thân cột dành cho kéo thẻ).
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Cần làm')),
      );
      await tester.pump(const Duration(milliseconds: 600));
      for (var step = 0; step < 5; step++) {
        await gesture.moveBy(const Offset(100, 0));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Cần làm'), findsOneWidget);
      final lists = await fakeRepo.getListsByBoardId(boardId).first;
      expect(lists.first.name, isNot('Cần làm'));
      expect(
        lists.map((list) => list.name),
        containsAll(['Cần làm', 'Đang làm', 'Hoàn thành']),
      );

      fakeRepo.dispose();
    });
  });
}
