import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../boards/data/boards_repository.dart';
import '../../../cards/data/card_model.dart';
import '../../../cards/presentation/card_format.dart';
import '../../data/collaboration_models.dart';
import '../../domain/collaboration_rules.dart';
import '../providers/collaboration_providers.dart';
import '../widgets/member_avatar.dart';

/// Màn hình Thành viên của board (UC06).
///
/// - Mọi thành viên: xem danh sách thành viên kèm vai trò (bước 2).
/// - Owner: mời thành viên qua email (bước 3–5, 4a), xem và hủy lời mời
///   đang chờ (2a), xóa Member khỏi board (2b–2c).
/// - Member: rời board (2d); Owner không có nút này.
class BoardMembersScreen extends ConsumerStatefulWidget {
  const BoardMembersScreen({required this.boardId, super.key});

  final String boardId;

  @override
  ConsumerState<BoardMembersScreen> createState() => _BoardMembersScreenState();
}

class _BoardMembersScreenState extends ConsumerState<BoardMembersScreen> {
  /// uid thành viên hoặc email lời mời đang được xử lý.
  final Set<String> _busy = {};
  bool _leaving = false;

  String get _boardId => widget.boardId;

  CollaborationController get _controller =>
      ref.read(collaborationControllerProvider);

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _runBusy(
    String key,
    Future<String?> Function() action, {
    required String successMessage,
  }) async {
    if (_busy.contains(key)) return;
    setState(() => _busy.add(key));
    final error = await action();
    if (!mounted) return;
    setState(() => _busy.remove(key));
    _showMessage(error ?? successMessage);
  }

  Future<void> _invite() async {
    final email = await showDialog<String>(
      context: context,
      builder: (_) => _InviteMemberDialog(boardId: _boardId),
    );
    if (email != null && mounted) {
      _showMessage('Đã gửi lời mời tới $email.');
    }
  }

  Future<void> _cancelInvitation(BoardInvitation invitation) async {
    final confirmed = await _confirm(
      title: 'Hủy lời mời?',
      message:
          'Lời mời gửi tới ${invitation.email} sẽ bị hủy. Người nhận sẽ không '
          'còn thấy lời mời này.',
      confirmLabel: 'Hủy lời mời',
      cancelLabel: 'Giữ lại',
    );
    if (!confirmed || !mounted) return;
    await _runBusy(
      invitation.normalizedEmail,
      () => _controller.cancelInvitation(
        boardId: _boardId,
        normalizedEmail: invitation.normalizedEmail,
      ),
      successMessage: 'Đã hủy lời mời gửi tới ${invitation.email}.',
    );
  }

  Future<void> _removeMember(BoardSummary board, BoardMember member) async {
    final name = _nameOf(member);
    final confirmed = await _confirm(
      title: 'Xóa thành viên?',
      message:
          '$name sẽ bị xóa khỏi board “${board.name}”, mất quyền truy cập '
          'board và được gỡ khỏi mọi thẻ đang được giao.',
      confirmLabel: 'Xóa khỏi board',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _runBusy(
      member.uid,
      () => _controller.removeMember(boardId: _boardId, memberUid: member.uid),
      successMessage: 'Đã xóa $name khỏi board.',
    );
  }

  Future<void> _leave(BoardSummary board) async {
    final confirmed = await _confirm(
      title: 'Rời board?',
      message:
          'Bạn sẽ không còn thấy board “${board.name}” và được gỡ khỏi mọi thẻ '
          'đang được giao. Muốn tham gia lại, bạn cần Owner mời lại.',
      confirmLabel: 'Rời board',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _leaving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final error = await _controller.leaveBoard(_boardId);
    if (error != null) {
      if (mounted) setState(() => _leaving = false);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    // Đã mất quyền truy cập board: quay về danh sách board.
    navigator.popUntil((route) => route.isFirst);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Đã rời board “${board.name}”.')));
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    String cancelLabel = 'Hủy',
    bool destructive = false,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(cancelLabel),
            ),
            FilledButton(
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: colorScheme.error,
                      foregroundColor: colorScheme.onError,
                    )
                  : null,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final boardAsync = ref.watch(collaborationBoardProvider(_boardId));
    final uid = ref.watch(collaboratorIdProvider);

    return boardAsync.when(
      loading: () =>
          _scaffold(body: const Center(child: CircularProgressIndicator())),
      error: (error, _) => _scaffold(
        body: _isPermissionDenied(error)
            ? const _AccessLost()
            : _CenteredMessage(
                icon: Icons.cloud_off_outlined,
                message:
                    'Không tải được thành viên. '
                    '${describeCollaborationError(error)}',
              ),
      ),
      data: (board) {
        if (board == null) {
          return _scaffold(
            body: const _CenteredMessage(
              icon: Icons.dashboard_outlined,
              message: 'Board không còn tồn tại.',
            ),
          );
        }
        if (uid == null || !board.memberIds.contains(uid)) {
          return _scaffold(
            body: _leaving
                ? const Center(child: CircularProgressIndicator())
                : const _AccessLost(),
          );
        }
        return _buildContent(context, board, uid);
      },
    );
  }

  Scaffold _scaffold({required Widget body}) {
    return Scaffold(
      appBar: AppBar(title: const Text('Thành viên')),
      body: body,
    );
  }

  Widget _buildContent(BuildContext context, BoardSummary board, String uid) {
    final theme = Theme.of(context);
    final isOwner = board.ownerId == uid;
    final membersAsync = ref.watch(boardCollaboratorsProvider(_boardId));
    final invitationsAsync = isOwner
        ? ref.watch(pendingInvitationsProvider(_boardId))
        : null;
    final members = membersAsync.asData?.value ?? const <BoardMember>[];
    final invitations =
        invitationsAsync?.asData?.value ?? const <BoardInvitation>[];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Thành viên'),
            Text(
              board.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: isOwner
          ? FloatingActionButton.extended(
              onPressed: _invite,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Mời thành viên'),
            )
          : null,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            _SectionHeader(
              title: 'Thành viên',
              count: membersAsync.hasValue ? members.length : null,
            ),
            if (membersAsync.isLoading && !membersAsync.hasValue)
              const _LoadingRow()
            else if (membersAsync.hasError && !membersAsync.hasValue)
              _InlineError(
                message: describeCollaborationError(membersAsync.error!),
              )
            else
              for (final member in members)
                _MemberTile(
                  member: member,
                  isOwner: member.uid == board.ownerId,
                  isMe: member.uid == uid,
                  busy: _busy.contains(member.uid),
                  onRemove: isOwner && member.uid != board.ownerId
                      ? () => _removeMember(board, member)
                      : null,
                ),
            if (isOwner) ...[
              const SizedBox(height: 20),
              _SectionHeader(
                title: 'Lời mời đang chờ',
                count: invitationsAsync!.hasValue ? invitations.length : null,
              ),
              if (invitationsAsync.isLoading && !invitationsAsync.hasValue)
                const _LoadingRow()
              else if (invitationsAsync.hasError && !invitationsAsync.hasValue)
                _InlineError(
                  message: describeCollaborationError(invitationsAsync.error!),
                )
              else if (invitations.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Chưa có lời mời nào đang chờ. Nhấn “Mời thành viên” để '
                    'mời bạn bè cùng làm việc.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                for (final invitation in invitations)
                  _InvitationTile(
                    invitation: invitation,
                    busy: _busy.contains(invitation.normalizedEmail),
                    onCancel: () => _cancelInvitation(invitation),
                  ),
            ] else ...[
              const SizedBox(height: 28),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error),
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _leaving ? null : () => _leave(board),
                icon: _leaving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.logout_rounded),
                label: Text(_leaving ? 'Đang rời board…' : 'Rời board'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _nameOf(BoardMember member) => member.displayName.isNotEmpty
    ? member.displayName
    : (member.email.isNotEmpty ? member.email : 'Thành viên');

bool _isPermissionDenied(Object error) =>
    error is FirebaseException && error.code == 'permission-denied';

// =============================================================================
// Hộp thoại mời thành viên (bước 3–5, 4a)
// =============================================================================

class _InviteMemberDialog extends ConsumerStatefulWidget {
  const _InviteMemberDialog({required this.boardId});

  final String boardId;

  @override
  ConsumerState<_InviteMemberDialog> createState() =>
      _InviteMemberDialogState();
}

class _InviteMemberDialogState extends ConsumerState<_InviteMemberDialog> {
  final _emailController = TextEditingController();
  String? _error;
  bool _sending = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending) return;
    final email = _emailController.text.trim();
    final formatError = validateInviteEmail(email);
    if (formatError != null) {
      setState(() => _error = formatError);
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final error = await ref
        .read(collaborationControllerProvider)
        .inviteMember(boardId: widget.boardId, email: email);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(email);
      return;
    }
    setState(() {
      _sending = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Mời thành viên'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Người được mời cần đăng nhập bằng đúng email này để thấy và '
              'chấp nhận lời mời.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              autofocus: true,
              enabled: !_sending,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.send,
              autocorrect: false,
              enableSuggestions: false,
              maxLength: kEmailMaxLength,
              buildCounter:
                  (
                    context, {
                    required currentLength,
                    required isFocused,
                    required maxLength,
                  }) => null,
              decoration: InputDecoration(
                labelText: 'Email người được mời',
                hintText: 'ten@example.com',
                prefixIcon: const Icon(Icons.alternate_email_rounded),
                border: const OutlineInputBorder(),
                errorText: _error,
                errorMaxLines: 3,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton.icon(
          onPressed: _sending ? null : _submit,
          icon: _sending
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_rounded, size: 18),
          label: Text(_sending ? 'Đang gửi…' : 'Gửi lời mời'),
        ),
      ],
    );
  }
}

// =============================================================================
// Các thành phần giao diện
// =============================================================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.count});

  final String title;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Text(
        count == null ? title : '$title ($count)',
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.isOwner,
    required this.isMe,
    required this.busy,
    this.onRemove,
  });

  final BoardMember member;

  /// Vai trò thật lấy từ `board.ownerId` (quyết định D2).
  final bool isOwner;
  final bool isMe;
  final bool busy;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final name = _nameOf(member);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: ListTile(
        leading: MemberAvatar(
          uid: member.uid,
          name: member.displayName,
          email: member.email,
        ),
        title: Text(
          isMe ? '$name (Bạn)' : name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: member.email.isEmpty
            ? null
            : Text(member.email, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RoleChip(isOwner: isOwner),
            if (busy)
              const Padding(
                padding: EdgeInsets.only(left: 12),
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (onRemove != null)
              IconButton(
                tooltip: 'Xóa $name khỏi board',
                onPressed: onRemove,
                icon: Icon(
                  Icons.person_remove_outlined,
                  color: colorScheme.error,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.isOwner});

  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = isOwner
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHighest;
    final foreground = isOwner
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isOwner ? 'Owner' : 'Member',
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _InvitationTile extends StatelessWidget {
  const _InvitationTile({
    required this.invitation,
    required this.busy,
    required this.onCancel,
  });

  final BoardInvitation invitation;
  final bool busy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final createdAt = invitation.createdAt;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colorScheme.secondaryContainer,
          foregroundColor: colorScheme.onSecondaryContainer,
          child: const Icon(Icons.mail_outline_rounded),
        ),
        title: Text(
          invitation.email,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          createdAt == null
              ? 'Đang gửi lời mời…'
              : 'Chờ phản hồi · mời lúc ${formatDateTime(createdAt)}',
        ),
        trailing: busy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                tooltip: 'Hủy lời mời',
                onPressed: onCancel,
                icon: const Icon(Icons.close_rounded),
              ),
      ),
    );
  }
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(color: colorScheme.error)),
          ),
        ],
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// Người dùng đã bị xóa khỏi board hoặc đã rời board (UC06 2c).
class _AccessLost extends StatelessWidget {
  const _AccessLost();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 52,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 14),
            const Text(
              'Bạn không còn là thành viên của board này.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
              child: const Text('Về danh sách board'),
            ),
          ],
        ),
      ),
    );
  }
}
