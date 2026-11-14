import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_todo/features/cards/data/fake_card_repository.dart';
import 'package:smart_todo/features/cards/presentation/providers/card_providers.dart';
import 'package:smart_todo/features/cards/presentation/screens/card_detail_screen.dart';
import 'package:smart_todo/features/collaboration/data/fake_collaboration_repository.dart';
import 'package:smart_todo/features/collaboration/presentation/providers/collaboration_providers.dart';
import 'package:smart_todo/features/collaboration/presentation/widgets/assignee_picker_sheet.dart';
import 'package:smart_todo/features/lists/data/fake_list_repository.dart';
import 'package:smart_todo/features/lists/presentation/providers/list_providers.dart';

/// Kiểm thử giao việc và bình luận trong chi tiết thẻ (UC06 1a–1d) trên thẻ
/// mẫu `card_read`: được giao cho `preview_user`, có 2 bình luận
/// (`comment_1` của Nguyễn An, `comment_2` của Owner `preview_user`).
void main() {
  const boardId = 'thesis_board';
  const cardId = 'card_read';
  late FakeListRepository listRepo;
  late FakeCardRepository cardRepo;
  late FakeCollaborationRepository collabRepo;

  setUp(() {
    listRepo = FakeListRepository();
    cardRepo = FakeCardRepository();
    collabRepo = FakeCollaborationRepository();
  });

  tearDown(() {
    listRepo.dispose();
    cardRepo.dispose();
    collabRepo.dispose();
  });

  Future<void> pumpCard(WidgetTester tester) async {
    // Màn hình cao để toàn bộ ListView (kể cả bình luận) được dựng.
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          listRepositoryProvider.overrideWithValue(listRepo),
          cardRepositoryProvider.overrideWithValue(cardRepo),
          collaborationRepositoryProvider.overrideWithValue(collabRepo),
        ],
        child: const MaterialApp(
          home: CardDetailScreen(boardId: boardId, cardId: cardId),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder commentMenu(String commentId) => find.descendant(
    of: find.byKey(ValueKey('comment-$commentId')),
    matching: find.byIcon(Icons.more_vert_rounded),
  );

  Finder composer() => find.byType(TextField).last;

  group('Giao việc (1a–1b)', () {
    testWidgets('chọn và bỏ chọn thành viên của board', (tester) async {
      await pumpCard(tester);
      expect(find.widgetWithText(Chip, 'Người dùng xem trước'), findsOneWidget);

      await tester.tap(find.text('Người được giao'));
      await tester.pumpAndSettle();

      // Chỉ liệt kê thành viên của board, người đang được giao đã được chọn.
      final me = find.widgetWithText(
        CheckboxListTile,
        'Người dùng xem trước (Bạn)',
      );
      final an = find.widgetWithText(CheckboxListTile, 'Nguyễn An');
      expect(tester.widget<CheckboxListTile>(me).value, isTrue);
      expect(tester.widget<CheckboxListTile>(an).value, isFalse);
      expect(
        find.descendant(
          of: find.byType(AssigneePickerSheet),
          matching: find.byType(CheckboxListTile),
        ),
        findsNWidgets(2),
      );

      await tester.tap(an);
      await tester.pumpAndSettle();
      await tester.tap(me);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(an).value, isTrue);
      expect(tester.widget<CheckboxListTile>(me).value, isFalse);

      final card = await cardRepo
          .watchCard(boardId: boardId, cardId: cardId)
          .first;
      expect(card!.assigneeIds, ['member_an']);

      // Đóng bảng chọn: thẻ hiển thị người được giao mới.
      await tester.tapAt(const Offset(450, 20));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(Chip, 'Nguyễn An'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'Người dùng xem trước'), findsNothing);
    });
  });

  group('Bình luận (1c–1d)', () {
    testWidgets('hiển thị bình luận kèm tên và thời gian', (tester) async {
      await pumpCard(tester);

      expect(find.text('Bình luận (2)'), findsOneWidget);
      expect(
        find.text('Mình đã tìm được 3 bài báo liên quan.'),
        findsOneWidget,
      );
      expect(find.text('Nguyễn An'), findsOneWidget);
      expect(find.text('02/10/2026 09:30'), findsOneWidget);

      // Mới nhất ở trên.
      final newer = tester.getTopLeft(
        find.text('Cảm ơn, mình sẽ đọc trong tuần này.'),
      );
      final older = tester.getTopLeft(
        find.text('Mình đã tìm được 3 bài báo liên quan.'),
      );
      expect(newer.dy, lessThan(older.dy));
    });

    testWidgets('gửi bình luận mới; nội dung trống bị từ chối', (tester) async {
      await pumpCard(tester);

      await tester.enterText(composer(), '   ');
      await tester.tap(find.byTooltip('Gửi'));
      await tester.pumpAndSettle();
      expect(
        find.text('Nội dung bình luận không được để trống.'),
        findsOneWidget,
      );

      await tester.enterText(composer(), '  Đã đọc xong bài đầu tiên  ');
      await tester.tap(find.byTooltip('Gửi'));
      await tester.pumpAndSettle();

      expect(find.text('Đã đọc xong bài đầu tiên'), findsOneWidget);
      expect(find.text('Bình luận (3)'), findsOneWidget);
      expect(tester.widget<TextField>(composer()).controller!.text, isEmpty);
      expect(collabRepo.commentCountOf(boardId, cardId), 3);
    });

    testWidgets('tác giả sửa bình luận của mình', (tester) async {
      await pumpCard(tester);

      await tester.tap(commentMenu('comment_2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sửa bình luận'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Mình đọc xong rồi nhé.',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
      await tester.pumpAndSettle();

      expect(find.text('Mình đọc xong rồi nhé.'), findsOneWidget);
      expect(find.textContaining('đã chỉnh sửa'), findsOneWidget);
    });

    testWidgets(
      'Owner xóa được bình luận của người khác nhưng không sửa được',
      (tester) async {
        await pumpCard(tester);

        await tester.tap(commentMenu('comment_1'));
        await tester.pumpAndSettle();
        expect(find.text('Sửa bình luận'), findsNothing);
        await tester.tap(find.text('Xóa bình luận'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Xóa'));
        await tester.pumpAndSettle();

        expect(
          find.text('Mình đã tìm được 3 bài báo liên quan.'),
          findsNothing,
        );
        expect(find.text('Bình luận (1)'), findsOneWidget);
      },
    );

    testWidgets('Member không sửa/xóa được bình luận của người khác', (
      tester,
    ) async {
      collabRepo.dispose();
      collabRepo = FakeCollaborationRepository(
        currentUserId: 'member_an',
        currentUserEmail: 'an@example.com',
        currentUserName: 'Nguyễn An',
      );
      await pumpCard(tester);

      expect(commentMenu('comment_2'), findsNothing);
      await tester.tap(commentMenu('comment_1'));
      await tester.pumpAndSettle();
      expect(find.text('Sửa bình luận'), findsOneWidget);
      expect(find.text('Xóa bình luận'), findsOneWidget);
    });
  });
}
