import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_todo/features/cards/data/card_model.dart';
import 'package:smart_todo/features/cards/data/fake_card_repository.dart';
import 'package:smart_todo/features/cards/presentation/providers/card_providers.dart';
import 'package:smart_todo/features/cards/presentation/screens/card_detail_screen.dart';
import 'package:smart_todo/features/lists/data/fake_list_repository.dart';
import 'package:smart_todo/features/lists/presentation/providers/list_providers.dart';
import 'package:smart_todo/features/lists/presentation/widgets/board_lists_section.dart';

/// Kiểm thử giao diện UC05 trên board mẫu `thesis_board` của repository giả.
void main() {
  const boardId = 'thesis_board';
  late FakeListRepository listRepo;
  late FakeCardRepository cardRepo;

  setUp(() {
    listRepo = FakeListRepository();
    cardRepo = FakeCardRepository();
  });

  tearDown(() {
    listRepo.dispose();
    cardRepo.dispose();
  });

  Future<void> pumpBoard(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          listRepositoryProvider.overrideWithValue(listRepo),
          cardRepositoryProvider.overrideWithValue(cardRepo),
        ],
        child: const MaterialApp(
          home: Scaffold(body: BoardListsSection(boardId: boardId)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
  }

  Future<TaskCardModel?> storedCard(String cardId) =>
      cardRepo.watchCard(boardId: boardId, cardId: cardId).first;

  Finder cardTile(String title) =>
      find.ancestor(of: find.text(title), matching: find.byType(InkWell)).first;

  Future<void> openCardMenu(WidgetTester tester, String title) async {
    await tester.tap(
      find.descendant(
        of: cardTile(title),
        matching: find.byIcon(Icons.more_horiz_rounded),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows card summaries in each list (bước 2)', (tester) async {
    await pumpBoard(tester);

    expect(find.text('Đọc tài liệu tham khảo'), findsOneWidget);
    expect(find.text('Phác thảo chương 1'), findsOneWidget);
    expect(find.text('Thiết kế ERD'), findsOneWidget);
    expect(find.text('2 thẻ'), findsOneWidget);

    // Nhãn, hạn chót, checklist, bình luận và avatar người được giao.
    expect(find.text('Tài liệu'), findsOneWidget);
    expect(find.text('15/12'), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('A'), findsOneWidget); // Nguyễn An
  });

  testWidgets('adds a card at the end of the list (bước 3–8)', (tester) async {
    await pumpBoard(tester);

    await tester.tap(find.text('Thêm thẻ').first);
    await tester.pump();
    await tester.enterText(find.byType(TextFormField), '  Viết chương 2  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Viết chương 2'), findsOneWidget);
    expect(find.text('3 thẻ'), findsOneWidget);
    final todo = (await cardRepo.watchBoardCards(boardId).first).cardsInList(
      'list_todo',
    );
    expect(todo.last.title, 'Viết chương 2');

    // Ô nhập vẫn mở và đã được xóa để thêm thẻ tiếp theo.
    final field = tester.widget<TextFormField>(find.byType(TextFormField));
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('rejects an empty title (5a)', (tester) async {
    await pumpBoard(tester);

    await tester.tap(find.text('Thêm thẻ').first);
    await tester.pump();
    await tester.enterText(find.byType(TextFormField), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Tiêu đề thẻ không được để trống.'), findsOneWidget);
    expect(find.text('2 thẻ'), findsOneWidget);
  });

  testWidgets('marks a card completed and back (3c–3d)', (tester) async {
    await pumpBoard(tester);

    await tester.tap(find.byTooltip('Đánh dấu hoàn thành').first);
    await tester.pumpAndSettle();
    expect((await storedCard('card_read'))!.isCompleted, isTrue);

    final title = tester.widget<Text>(find.text('Đọc tài liệu tham khảo'));
    expect(title.style?.decoration, TextDecoration.lineThrough);

    await openCardMenu(tester, 'Đọc tài liệu tham khảo');
    await tester.tap(find.text('Bỏ đánh dấu hoàn thành'));
    await tester.pumpAndSettle();
    expect((await storedCard('card_read'))!.isCompleted, isFalse);
  });

  testWidgets('archives a card after confirmation (3e)', (tester) async {
    await pumpBoard(tester);

    await openCardMenu(tester, 'Thiết kế ERD');
    await tester.tap(find.text('Lưu trữ thẻ'));
    await tester.pumpAndSettle();
    expect(find.text('Lưu trữ thẻ?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Lưu trữ'));
    await tester.pumpAndSettle();

    expect(find.text('Thiết kế ERD'), findsNothing);
    expect((await storedCard('card_erd'))!.isArchived, isTrue);
    expect(find.text('Đã lưu trữ thẻ.'), findsOneWidget);
  });

  testWidgets('deletes a card only after two confirmations (3f)', (
    tester,
  ) async {
    await pumpBoard(tester);

    // Hủy ở bước thứ hai: thẻ vẫn còn.
    await openCardMenu(tester, 'Thiết kế ERD');
    await tester.tap(find.text('Xóa thẻ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();
    expect(find.text('Xóa vĩnh viễn?'), findsOneWidget);
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(await storedCard('card_erd'), isNotNull);

    await openCardMenu(tester, 'Thiết kế ERD');
    await tester.tap(find.text('Xóa thẻ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xóa vĩnh viễn'));
    await tester.pumpAndSettle();

    expect(await storedCard('card_erd'), isNull);
    expect(find.text('Thiết kế ERD'), findsNothing);
  });

  testWidgets('drags a card to another list', (tester) async {
    await pumpBoard(tester);

    final from = tester.getCenter(find.text('Phác thảo chương 1'));
    final target = tester.getCenter(find.text('Thiết kế ERD'));
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 600));
    const steps = 8;
    // Thả ngay dưới thẻ “Thiết kế ERD”.
    final delta = (target + const Offset(0, 60) - from) / steps.toDouble();
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(delta);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    final moved = await storedCard('card_outline');
    expect(moved!.listId, 'list_doing');
    final doing = (await cardRepo.watchBoardCards(boardId).first).cardsInList(
      'list_doing',
    );
    expect(doing.map((c) => c.id), ['card_erd', 'card_outline']);
  });

  testWidgets('edits the title in the detail screen with autosave (3a–3b)', (
    tester,
  ) async {
    await pumpBoard(tester);

    await tester.tap(find.text('Phác thảo chương 1'));
    await tester.pumpAndSettle();
    expect(find.byType(CardDetailScreen), findsOneWidget);
    expect(find.text('Trong danh sách “Cần làm”'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Phác thảo chương 1 và 2');
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();

    expect(
      (await storedCard('card_outline'))!.title,
      'Phác thảo chương 1 và 2',
    );
    expect(find.text('Đã lưu'), findsOneWidget);

    // Tiêu đề rỗng không được lưu.
    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Tiêu đề thẻ không được để trống.'), findsOneWidget);
    expect(
      (await storedCard('card_outline'))!.title,
      'Phác thảo chương 1 và 2',
    );
  });

  testWidgets('returns to the board when the open card is deleted (3g)', (
    tester,
  ) async {
    await pumpBoard(tester);

    await tester.tap(find.text('Thiết kế ERD'));
    await tester.pumpAndSettle();
    expect(find.byType(CardDetailScreen), findsOneWidget);

    // Một thành viên khác xóa thẻ.
    await cardRepo.deleteCard(boardId: boardId, cardId: 'card_erd');
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(CardDetailScreen), findsNothing);
    expect(find.textContaining('Thẻ không còn tồn tại'), findsOneWidget);
  });

  testWidgets('reports connection errors (8a)', (tester) async {
    await pumpBoard(tester);
    cardRepo.writeError = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'unavailable',
    );

    await tester.tap(find.byTooltip('Đánh dấu hoàn thành').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Không kết nối được Firestore'), findsOneWidget);
    expect((await storedCard('card_read'))!.isCompleted, isFalse);
  });

  testWidgets('shows an offline banner when data only comes from cache', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          listRepositoryProvider.overrideWithValue(listRepo),
          boardCardsProvider(boardId).overrideWith(
            (ref) => Stream.value(
              BoardCardsSnapshot(cards: const [], isFromCache: true),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: BoardListsSection(boardId: boardId)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('Mất kết nối tới Firestore'), findsNothing);

    await tester.pump(const Duration(seconds: 3));
    expect(find.textContaining('Mất kết nối tới Firestore'), findsOneWidget);
  });
}
