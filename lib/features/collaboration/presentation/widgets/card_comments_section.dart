import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../cards/presentation/card_format.dart';
import '../../data/collaboration_models.dart';
import '../../domain/collaboration_rules.dart';
import '../providers/collaboration_providers.dart';
import 'member_avatar.dart';

/// Bình luận trong chi tiết thẻ (UC06 1c–1d).
///
/// Nội dung 1–2000 ký tự, hiển thị theo thời gian thực kèm tên và thời gian.
/// Tác giả sửa được bình luận của mình; tác giả hoặc Owner xóa được.
class CardCommentsSection extends ConsumerStatefulWidget {
  const CardCommentsSection({
    required this.boardId,
    required this.cardId,
    super.key,
  });

  final String boardId;
  final String cardId;

  @override
  ConsumerState<CardCommentsSection> createState() =>
      _CardCommentsSectionState();
}

class _CardCommentsSectionState extends ConsumerState<CardCommentsSection> {
  /// Chỉ hiện bộ đếm ký tự khi gần chạm giới hạn.
  static const _counterThreshold = kCommentMaxLength - 200;

  final _composer = TextEditingController();
  final Set<String> _busyComments = {};
  bool _sending = false;
  String? _composerError;

  ({String boardId, String cardId}) get _key =>
      (boardId: widget.boardId, cardId: widget.cardId);

  CollaborationController get _controller =>
      ref.read(collaborationControllerProvider);

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _send() async {
    if (_sending) return;
    final body = _composer.text;
    final validation = validateCommentBody(body);
    if (validation != null) {
      setState(() => _composerError = validation);
      return;
    }
    setState(() {
      _sending = true;
      _composerError = null;
    });
    final error = await _controller.addComment(
      boardId: widget.boardId,
      cardId: widget.cardId,
      body: body,
    );
    if (!mounted) return;
    final queued = error == CollaborationController.queuedOfflineMessage;
    setState(() {
      _sending = false;
      if (error == null || queued) {
        _composer.clear();
      } else {
        _composerError = error;
      }
    });
    if (queued) _showMessage(error!);
  }

  Future<void> _edit(CardComment comment) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EditCommentDialog(
        boardId: widget.boardId,
        cardId: widget.cardId,
        comment: comment,
      ),
    );
    if (saved == true && mounted) _showMessage('Đã cập nhật bình luận.');
  }

  Future<void> _delete(CardComment comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: const Text('Xóa bình luận?'),
          content: const Text('Bình luận sẽ bị xóa vĩnh viễn.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Xóa'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyComments.add(comment.id));
    final error = await _controller.deleteComment(
      boardId: widget.boardId,
      cardId: widget.cardId,
      commentId: comment.id,
    );
    if (!mounted) return;
    setState(() => _busyComments.remove(comment.id));
    _showMessage(error ?? 'Đã xóa bình luận.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final commentsAsync = ref.watch(cardCommentsProvider(_key));
    final myUid = ref.watch(collaboratorIdProvider);
    final board = ref
        .watch(collaborationBoardProvider(widget.boardId))
        .asData
        ?.value;
    final isOwner = myUid != null && board?.ownerId == myUid;
    final comments = commentsAsync.asData?.value ?? const <CardComment>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 20,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Text(
              commentsAsync.hasValue
                  ? 'Bình luận (${comments.length})'
                  : 'Bình luận',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _composer,
          enabled: !_sending,
          minLines: 1,
          maxLines: 5,
          maxLength: kCommentMaxLength,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          buildCounter:
              (
                context, {
                required currentLength,
                required isFocused,
                required maxLength,
              }) => currentLength > _counterThreshold
              ? Text('$currentLength/$maxLength')
              : null,
          decoration: InputDecoration(
            hintText: 'Viết bình luận…',
            border: const OutlineInputBorder(),
            errorText: _composerError,
            errorMaxLines: 3,
            suffixIcon: _sending
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    tooltip: 'Gửi',
                    onPressed: _send,
                    icon: Icon(Icons.send_rounded, color: colorScheme.primary),
                  ),
          ),
          onChanged: (_) {
            if (_composerError != null) setState(() => _composerError = null);
          },
        ),
        const SizedBox(height: 8),
        commentsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Không tải được bình luận. ${describeCollaborationError(error)}',
              style: TextStyle(color: colorScheme.error),
            ),
          ),
          data: (comments) => comments.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Chưa có bình luận nào.',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Mới nhất ở trên, ngay dưới ô nhập.
                    for (final comment in comments.reversed)
                      _CommentTile(
                        key: ValueKey('comment-${comment.id}'),
                        comment: comment,
                        isMine: comment.authorId == myUid,
                        busy: _busyComments.contains(comment.id),
                        onEdit: comment.authorId == myUid && !comment.isPending
                            ? () => _edit(comment)
                            : null,
                        onDelete:
                            (comment.authorId == myUid || isOwner) &&
                                !comment.isPending
                            ? () => _delete(comment)
                            : null,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    super.key,
    required this.isMine,
    required this.busy,
    this.onEdit,
    this.onDelete,
  });

  final CardComment comment;
  final bool isMine;
  final bool busy;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final createdAt = comment.createdAt;
    final author = comment.authorName.isEmpty
        ? 'Một thành viên'
        : comment.authorName;
    final meta = [
      createdAt == null ? 'Đang gửi…' : formatDateTime(createdAt),
      if (comment.isEdited) 'đã chỉnh sửa',
    ].join(' · ');
    final onEdit = this.onEdit;
    final onDelete = this.onDelete;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MemberAvatar(uid: comment.authorId, name: author, radius: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
              decoration: BoxDecoration(
                color: isMine
                    ? colorScheme.primaryContainer.withValues(alpha: 0.45)
                    : colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.6,
                      ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              author,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              meta,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (busy)
                        const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else if (onEdit != null || onDelete != null)
                        PopupMenuButton<String>(
                          tooltip: 'Thao tác bình luận',
                          icon: const Icon(Icons.more_vert_rounded, size: 18),
                          onSelected: (value) => value == 'edit'
                              ? onEdit?.call()
                              : onDelete?.call(),
                          itemBuilder: (context) => [
                            if (onEdit != null)
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Sửa bình luận'),
                              ),
                            if (onDelete != null)
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Xóa bình luận'),
                              ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(comment.body),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditCommentDialog extends ConsumerStatefulWidget {
  const _EditCommentDialog({
    required this.boardId,
    required this.cardId,
    required this.comment,
  });

  final String boardId;
  final String cardId;
  final CardComment comment;

  @override
  ConsumerState<_EditCommentDialog> createState() => _EditCommentDialogState();
}

class _EditCommentDialogState extends ConsumerState<_EditCommentDialog> {
  late final _controller = TextEditingController(text: widget.comment.body);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final body = _controller.text;
    final validation = validateCommentBody(body);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    if (body.trim() == widget.comment.body) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await ref
        .read(collaborationControllerProvider)
        .editComment(
          boardId: widget.boardId,
          cardId: widget.cardId,
          commentId: widget.comment.id,
          body: body,
        );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _saving = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sửa bình luận'),
      content: SizedBox(
        width: 480,
        child: TextField(
          controller: _controller,
          autofocus: true,
          enabled: !_saving,
          minLines: 3,
          maxLines: 8,
          maxLength: kCommentMaxLength,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            errorText: _error,
            errorMaxLines: 3,
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Đang lưu…' : 'Lưu'),
        ),
      ],
    );
  }
}
