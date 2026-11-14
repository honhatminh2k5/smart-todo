import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_todo/features/collaboration/data/collaboration_models.dart';
import 'package:smart_todo/features/collaboration/data/fake_collaboration_repository.dart';
import 'package:smart_todo/features/collaboration/domain/collaboration_rules.dart';
import 'package:smart_todo/features/collaboration/presentation/providers/collaboration_providers.dart';
import 'package:smart_todo/features/collaboration/presentation/screens/my_invitations_screen.dart';

/// Kiểm thử phía người được mời (UC06 bước 6–10, 2a, 8a, 9a).
void main() {
  const boardId = 'thesis_board';
  late FakeCollaborationRepository repo;

  final invitation = BoardInvitation(
    boardId: boardId,
    email: 'Binh@example.com',
    normalizedEmail: 'binh@example.com',
    invitedBy: 'preview_user',
    inviterName: 'Người dùng xem trước',
    boardName: 'Khóa luận tốt nghiệp',
    createdAt: DateTime(2026, 11, 2, 9, 5),
  );

  setUp(() {
    repo = FakeCollaborationRepository(
      currentUserId: 'binh',
      currentUserEmail: 'binh@example.com',
      currentUserName: 'Trần Bình',
    );
    repo.putInvitation(invitation);
  });

  tearDown(() => repo.dispose());

  Future<List<String>> pumpBoardsBar(WidgetTester tester) async {
    final opened = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [collaborationRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: const Text('Board của tôi'),
              actions: [
                InvitationsButton(onOpenBoard: (context, id) => opened.add(id)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return opened;
  }

  Future<List<String>> openInvitations(WidgetTester tester) async {
    final opened = await pumpBoardsBar(tester);
    await tester.tap(find.byTooltip('Lời mời (1)'));
    await tester.pumpAndSettle();
    return opened;
  }

  testWidgets('nút Lời mời hiện số lời mời đang chờ', (tester) async {
    await pumpBoardsBar(tester);
    expect(find.byTooltip('Lời mời (1)'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    repo.deleteInvitation(boardId, 'binh@example.com');
    await tester.pumpAndSettle();
    expect(find.byTooltip('Lời mời'), findsOneWidget);
    expect(find.text('1'), findsNothing);
  });

  testWidgets('hiển thị tên board và người mời (bước 6–7)', (tester) async {
    await openInvitations(tester);

    expect(find.text('Khóa luận tốt nghiệp'), findsOneWidget);
    expect(
      find.text('Người dùng xem trước mời bạn tham gia board này.'),
      findsOneWidget,
    );
    expect(find.text('Gửi lúc 02/11/2026 09:05'), findsOneWidget);
  });

  testWidgets('chấp nhận thì trở thành Member và mở được board (bước 8–10)', (
    tester,
  ) async {
    final opened = await openInvitations(tester);

    await tester.tap(find.text('Chấp nhận'));
    await tester.pumpAndSettle();

    expect(
      find.text('Bạn đã tham gia board “Khóa luận tốt nghiệp”.'),
      findsOneWidget,
    );
    expect(find.textContaining('Bạn chưa có lời mời nào'), findsOneWidget);
    expect(repo.boardOf(boardId)!.memberIds, contains('binh'));
    expect(
      repo.invitationOf(boardId, 'binh@example.com')!.status,
      InvitationStatus.accepted,
    );

    final members = await repo.watchMembers(boardId).first;
    final binh = members.singleWhere((member) => member.uid == 'binh');
    expect(binh.role, 'member');
    expect(binh.displayName, 'Trần Bình');

    await tester.tap(find.text('Mở board'));
    await tester.pumpAndSettle();
    expect(opened, [boardId]);
  });

  testWidgets('từ chối thì không được thêm vào board (8a)', (tester) async {
    await openInvitations(tester);

    await tester.tap(find.text('Từ chối'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Từ chối'));
    await tester.pumpAndSettle();

    expect(
      find.text('Đã từ chối lời mời vào board “Khóa luận tốt nghiệp”.'),
      findsOneWidget,
    );
    expect(find.text('Khóa luận tốt nghiệp'), findsNothing);
    expect(repo.boardOf(boardId)!.memberIds, isNot(contains('binh')));
    expect(
      repo.invitationOf(boardId, 'binh@example.com')!.status,
      InvitationStatus.declined,
    );
  });

  testWidgets('lời mời bị Owner hủy thì biến mất ngay (2a)', (tester) async {
    await openInvitations(tester);
    expect(find.text('Khóa luận tốt nghiệp'), findsOneWidget);

    repo.deleteInvitation(boardId, 'binh@example.com');
    await tester.pumpAndSettle();

    expect(find.text('Khóa luận tốt nghiệp'), findsNothing);
    expect(find.textContaining('Bạn chưa có lời mời nào'), findsOneWidget);
  });

  test('chấp nhận lời mời đã bị hủy báo không còn hiệu lực (9a)', () async {
    final controller = CollaborationController(repo);
    repo.deleteInvitation(boardId, 'binh@example.com');

    expect(
      await controller.acceptInvitation(invitation),
      kInvitationNoLongerValid,
    );
    expect(repo.boardOf(boardId)!.memberIds, isNot(contains('binh')));
  });

  test('không chấp nhận được lời mời gửi cho email khác', () async {
    final other = FakeCollaborationRepository(
      currentUserId: 'khac',
      currentUserEmail: 'khac@example.com',
    )..putInvitation(invitation);
    addTearDown(other.dispose);

    expect(
      await CollaborationController(other).acceptInvitation(invitation),
      'Lời mời này không gửi tới email của bạn.',
    );
  });
}
