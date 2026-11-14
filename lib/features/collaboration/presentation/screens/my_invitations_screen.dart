import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../cards/presentation/card_format.dart';
import '../../data/collaboration_models.dart';
import '../providers/collaboration_providers.dart';

/// Mở board sau khi chấp nhận lời mời (bước 10).
typedef OpenBoardCallback = void Function(BuildContext context, String boardId);

/// Màn hình Lời mời của người được mời (UC06 bước 6–10, 8a, 9a).
///
/// Danh sách đồng bộ thời gian thực: lời mời bị Owner hủy sẽ tự biến mất (2a).
class MyInvitationsScreen extends ConsumerStatefulWidget {
  const MyInvitationsScreen({this.onOpenBoard, super.key});

  final OpenBoardCallback? onOpenBoard;

  @override
  ConsumerState<MyInvitationsScreen> createState() =>
      _MyInvitationsScreenState();
}

class _MyInvitationsScreenState extends ConsumerState<MyInvitationsScreen> {
  /// ID board của các lời mời đang được xử lý.
  final Set<String> _busy = {};

  Future<void> _accept(BoardInvitation invitation) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await _respond(
      invitation,
      (controller) => controller.acceptInvitation(invitation),
    );
    if (!mounted) return;
    final openBoard = widget.onOpenBoard;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            error ?? 'Bạn đã tham gia board “${invitation.boardName}”.',
          ),
          action: error == null && openBoard != null
              ? SnackBarAction(
                  label: 'Mở board',
                  onPressed: () {
                    if (mounted) openBoard(context, invitation.boardId);
                  },
                )
              : null,
        ),
      );
  }

  Future<void> _decline(BoardInvitation invitation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Từ chối lời mời?'),
        content: Text(
          'Bạn sẽ không tham gia board “${invitation.boardName}”. Muốn tham '
          'gia sau này, bạn cần Owner mời lại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Từ chối'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final error = await _respond(
      invitation,
      (controller) => controller.declineInvitation(invitation),
    );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            error ?? 'Đã từ chối lời mời vào board “${invitation.boardName}”.',
          ),
        ),
      );
  }

  Future<String?> _respond(
    BoardInvitation invitation,
    Future<String?> Function(CollaborationController controller) action,
  ) async {
    if (_busy.contains(invitation.boardId)) return null;
    setState(() => _busy.add(invitation.boardId));
    final error = await action(ref.read(collaborationControllerProvider));
    if (mounted) setState(() => _busy.remove(invitation.boardId));
    return error;
  }

  @override
  Widget build(BuildContext context) {
    final invitationsAsync = ref.watch(myInvitationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Lời mời tham gia board')),
      body: SafeArea(
        child: invitationsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _MessageState(
            icon: Icons.cloud_off_outlined,
            message:
                'Không tải được lời mời. ${describeCollaborationError(error)}',
            actionLabel: 'Thử lại',
            onAction: () => ref.invalidate(myInvitationsProvider),
          ),
          data: (invitations) {
            if (invitations.isEmpty) {
              return const _MessageState(
                icon: Icons.mark_email_read_outlined,
                message:
                    'Bạn chưa có lời mời nào. Khi Owner của một board mời '
                    'email của bạn, lời mời sẽ hiện ở đây.',
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: invitations.length,
              itemBuilder: (context, index) {
                final invitation = invitations[index];
                return _InvitationCard(
                  invitation: invitation,
                  busy: _busy.contains(invitation.boardId),
                  onAccept: () => _accept(invitation),
                  onDecline: () => _decline(invitation),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _InvitationCard extends StatelessWidget {
  const _InvitationCard({
    required this.invitation,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  final BoardInvitation invitation;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final createdAt = invitation.createdAt;
    final inviter = invitation.inviterName.isEmpty
        ? 'Owner của board'
        : invitation.inviterName;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: colorScheme.primaryContainer,
                  foregroundColor: colorScheme.onPrimaryContainer,
                  child: const Icon(Icons.dashboard_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    invitation.boardName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: inviter,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const TextSpan(text: ' mời bạn tham gia board này.'),
                ],
              ),
            ),
            if (createdAt != null) ...[
              const SizedBox(height: 4),
              Text(
                'Gửi lúc ${formatDateTime(createdAt)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(right: 16),
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                OutlinedButton(
                  onPressed: busy ? null : onDecline,
                  child: const Text('Từ chối'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: busy ? null : onAccept,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Chấp nhận'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final label = actionLabel;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            if (label != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(label),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Nút "Lời mời" trên thanh tiêu đề danh sách board, kèm số lời mời đang chờ.
class InvitationsButton extends ConsumerWidget {
  const InvitationsButton({this.onOpenBoard, super.key});

  final OpenBoardCallback? onOpenBoard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(myInvitationsProvider).asData?.value.length ?? 0;
    return IconButton(
      tooltip: count == 0 ? 'Lời mời' : 'Lời mời ($count)',
      onPressed: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => MyInvitationsScreen(onOpenBoard: onOpenBoard),
        ),
      ),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: const Icon(Icons.mail_outline_rounded),
      ),
    );
  }
}
