import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_todo/features/cards/data/card_model.dart';
import 'package:smart_todo/features/collaboration/data/collaboration_models.dart';
import 'package:smart_todo/features/collaboration/data/fake_collaboration_repository.dart';
import 'package:smart_todo/features/collaboration/presentation/providers/collaboration_providers.dart';
import 'package:smart_todo/features/collaboration/presentation/screens/board_members_screen.dart';

/// Kiểm thử màn hình Thành viên (UC06 bước 2–5, 2a–2d, 4a, 10a) trên board
/// mẫu `thesis_board`: Owner `preview_user`, Member `member_an`.
void main() {
  const boardId = 'thesis_board';
  late FakeCollaborationRepository repo;

  tearDown(() => repo.dispose());

  /// Mở màn hình Thành viên từ một trang gốc, giống khi đi từ board.
  Future<void> pumpMembers(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [collaborationRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const BoardMembersScreen(boardId: boardId),
                    ),
                  ),
                  child: const Text('Mở thành viên'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mở thành viên'));
    await tester.pumpAndSettle();
  }

  Future<void> submitInvite(WidgetTester tester, String email) async {
    await tester.enterText(find.byType(TextField), email);
    await tester.tap(find.widgetWithText(FilledButton, 'Gửi lời mời'));
    await tester.pumpAndSettle();
  }

  group('Owner', () {
    setUp(() => repo = FakeCollaborationRepository());

    testWidgets('xem thành viên kèm vai trò và lời mời đang chờ (bước 2)', (
      tester,
    ) async {
      repo.putInvitation(
        BoardInvitation(
          boardId: boardId,
          email: 'binh@example.com',
          normalizedEmail: 'binh@example.com',
          invitedBy: 'preview_user',
          inviterName: 'Người dùng xem trước',
          boardName: 'Khóa luận tốt nghiệp',
          createdAt: DateTime(2026, 11, 2, 9, 5),
        ),
      );
      await pumpMembers(tester);

      expect(find.text('Thành viên (2)'), findsOneWidget);
      expect(find.text('Người dùng xem trước (Bạn)'), findsOneWidget);
      expect(find.text('Nguyễn An'), findsOneWidget);
      expect(find.text('Owner'), findsOneWidget);
      expect(find.text('Member'), findsOneWidget);
      expect(find.text('Lời mời đang chờ (1)'), findsOneWidget);
      expect(find.text('binh@example.com'), findsOneWidget);
      expect(
        find.text('Chờ phản hồi · mời lúc 02/11/2026 09:05'),
        findsOneWidget,
      );

      // Owner mời và xóa được Member, nhưng không xóa được chính mình và không
      // có nút rời board.
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byTooltip('Xóa Nguyễn An khỏi board'), findsOneWidget);
      expect(
        find.byTooltip('Xóa Người dùng xem trước khỏi board'),
        findsNothing,
      );
      expect(find.text('Rời board'), findsNothing);
    });

    testWidgets('mời thành viên qua email (bước 3–5)', (tester) async {
      await pumpMembers(tester);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await submitInvite(tester, '  Binh@Example.com ');

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Đã gửi lời mời tới Binh@Example.com.'), findsOneWidget);
      expect(find.text('Binh@Example.com'), findsOneWidget);
      expect(find.text('Lời mời đang chờ (1)'), findsOneWidget);

      final saved = repo.invitationOf(boardId, 'binh@example.com')!;
      expect(saved.status, InvitationStatus.pending);
      expect(saved.boardName, 'Khóa luận tốt nghiệp');
      expect(saved.inviterName, 'Người dùng xem trước');
    });

    testWidgets('báo lỗi và không tạo lời mời khi email không hợp lệ (4a)', (
      tester,
    ) async {
      repo.putInvitation(
        const BoardInvitation(
          boardId: boardId,
          email: 'binh@example.com',
          normalizedEmail: 'binh@example.com',
          invitedBy: 'preview_user',
          inviterName: 'Người dùng xem trước',
          boardName: 'Khóa luận tốt nghiệp',
        ),
      );
      await pumpMembers(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await submitInvite(tester, 'binh@');
      expect(find.text('Email không đúng định dạng.'), findsOneWidget);

      await submitInvite(tester, 'AN@example.com');
      expect(
        find.text('AN@example.com đã là thành viên của board.'),
        findsOneWidget,
      );

      await submitInvite(tester, 'binh@example.com');
      expect(
        find.text('Đã có lời mời đang chờ gửi tới binh@example.com.'),
        findsOneWidget,
      );

      // Hộp thoại vẫn mở; không có lời mời mới nào.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(repo.invitationOf(boardId, 'an@example.com'), isNull);
    });

    testWidgets('mời lại người đã từ chối (Q12)', (tester) async {
      repo.putInvitation(
        const BoardInvitation(
          boardId: boardId,
          email: 'binh@example.com',
          normalizedEmail: 'binh@example.com',
          invitedBy: 'preview_user',
          inviterName: 'Người dùng xem trước',
          boardName: 'Khóa luận tốt nghiệp',
          status: InvitationStatus.declined,
        ),
      );
      await pumpMembers(tester);
      expect(find.text('Lời mời đang chờ (0)'), findsOneWidget);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await submitInvite(tester, 'binh@example.com');

      expect(find.text('Lời mời đang chờ (1)'), findsOneWidget);
      expect(
        repo.invitationOf(boardId, 'binh@example.com')!.status,
        InvitationStatus.pending,
      );
    });

    testWidgets('hủy lời mời đang chờ (2a)', (tester) async {
      repo.putInvitation(
        const BoardInvitation(
          boardId: boardId,
          email: 'binh@example.com',
          normalizedEmail: 'binh@example.com',
          invitedBy: 'preview_user',
          inviterName: 'Người dùng xem trước',
          boardName: 'Khóa luận tốt nghiệp',
        ),
      );
      await pumpMembers(tester);

      await tester.tap(find.byTooltip('Hủy lời mời'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Hủy lời mời'));
      await tester.pumpAndSettle();

      expect(find.text('binh@example.com'), findsNothing);
      expect(find.text('Lời mời đang chờ (0)'), findsOneWidget);
      expect(repo.invitationOf(boardId, 'binh@example.com'), isNull);
    });

    testWidgets('xóa Member khỏi board (2b–2c)', (tester) async {
      await pumpMembers(tester);

      await tester.tap(find.byTooltip('Xóa Nguyễn An khỏi board'));
      await tester.pumpAndSettle();
      expect(find.textContaining('gỡ khỏi mọi thẻ'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Xóa khỏi board'));
      await tester.pumpAndSettle();

      expect(find.text('Đã xóa Nguyễn An khỏi board.'), findsOneWidget);
      expect(find.text('Thành viên (1)'), findsOneWidget);
      expect(repo.boardOf(boardId)!.memberIds, ['preview_user']);
      expect(repo.detachedMembers.single.uid, 'member_an');
    });

    testWidgets('báo lỗi khi mất kết nối Firestore (10a)', (tester) async {
      await pumpMembers(tester);
      repo.writeError = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await submitInvite(tester, 'binh@example.com');

      expect(find.text(kCollaborationOfflineMessage), findsOneWidget);
      expect(repo.invitationOf(boardId, 'binh@example.com'), isNull);
    });
  });

  group('Member', () {
    setUp(
      () => repo = FakeCollaborationRepository(
        currentUserId: 'member_an',
        currentUserEmail: 'an@example.com',
        currentUserName: 'Nguyễn An',
      ),
    );

    testWidgets('chỉ xem thành viên, không mời hoặc xóa được ai', (
      tester,
    ) async {
      await pumpMembers(tester);

      expect(find.text('Nguyễn An (Bạn)'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byIcon(Icons.person_remove_outlined), findsNothing);
      expect(find.textContaining('Lời mời đang chờ'), findsNothing);
      expect(find.text('Rời board'), findsOneWidget);
    });

    testWidgets('rời board sau khi xác nhận rồi quay về danh sách (2d)', (
      tester,
    ) async {
      await pumpMembers(tester);

      await tester.tap(find.text('Rời board'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Rời board'));
      await tester.pumpAndSettle();

      expect(find.byType(BoardMembersScreen), findsNothing);
      expect(find.text('Đã rời board “Khóa luận tốt nghiệp”.'), findsOneWidget);
      expect(repo.boardOf(boardId)!.memberIds, ['preview_user']);
    });

    testWidgets('báo mất quyền truy cập khi bị Owner xóa (2c)', (tester) async {
      await pumpMembers(tester);

      // Owner xóa Member từ một thiết bị khác.
      repo.putBoard(
        id: boardId,
        name: 'Khóa luận tốt nghiệp',
        ownerId: 'preview_user',
        members: const [
          BoardMember(
            uid: 'preview_user',
            displayName: 'Người dùng xem trước',
            email: 'preview@example.com',
            role: 'owner',
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Bạn không còn là thành viên của board này.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Về danh sách board'));
      await tester.pumpAndSettle();
      expect(find.byType(BoardMembersScreen), findsNothing);
    });
  });
}
