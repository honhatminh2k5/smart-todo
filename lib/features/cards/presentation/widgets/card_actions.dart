import 'package:flutter/material.dart';

import '../../data/card_model.dart';
import '../providers/card_providers.dart';

/// Chờ thao tác xong rồi hiện lỗi, hoặc [successMessage] nếu thành công.
///
/// Nhận sẵn [messenger] để vẫn báo được khi màn hình gọi đã đóng.
Future<void> showCardActionResult(
  ScaffoldMessengerState messenger,
  Future<String?> action, {
  String? successMessage,
}) async {
  final message = await action ?? successMessage;
  if (message == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Hỏi xác nhận trước khi lưu trữ thẻ (UC05 3e).
Future<bool> confirmArchiveCard(
  BuildContext context,
  TaskCardModel card,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Lưu trữ thẻ?'),
      content: Text(
        'Thẻ “${card.title}” sẽ được lưu trữ và ẩn khỏi danh sách.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Lưu trữ'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Xác nhận hai bước trước khi xóa vĩnh viễn thẻ (UC05 3f).
Future<bool> confirmDeleteCard(BuildContext context, TaskCardModel card) async {
  final proceed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Xóa thẻ?'),
      content: Text('Bạn muốn xóa thẻ “${card.title}”?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Hủy'),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Tiếp tục'),
        ),
      ],
    ),
  );
  if (proceed != true || !context.mounted) return false;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final colorScheme = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: colorScheme.error),
        title: const Text('Xóa vĩnh viễn?'),
        content: Text(
          'Thẻ “${card.title}” cùng checklist và bình luận sẽ bị xóa vĩnh viễn, '
          'không thể khôi phục.',
        ),
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
            child: const Text('Xóa vĩnh viễn'),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

enum _CardAction { open, toggleCompleted, archive, delete }

/// Menu thao tác của một thẻ trên board.
Future<void> showCardActionsSheet(
  BuildContext context, {
  required CardsController cards,
  required String boardId,
  required TaskCardModel card,
  VoidCallback? onOpen,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final action = await showModalBottomSheet<_CardAction>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final colorScheme = Theme.of(sheetContext).colorScheme;
      void choose(_CardAction action) => Navigator.of(sheetContext).pop(action);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                card.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            if (onOpen != null)
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded),
                title: const Text('Mở chi tiết'),
                onTap: () => choose(_CardAction.open),
              ),
            ListTile(
              leading: Icon(
                card.isCompleted
                    ? Icons.radio_button_unchecked_rounded
                    : Icons.check_circle_outline_rounded,
              ),
              title: Text(
                card.isCompleted
                    ? 'Bỏ đánh dấu hoàn thành'
                    : 'Đánh dấu hoàn thành',
              ),
              onTap: () => choose(_CardAction.toggleCompleted),
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('Lưu trữ thẻ'),
              onTap: () => choose(_CardAction.archive),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: colorScheme.error),
              title: Text(
                'Xóa thẻ',
                style: TextStyle(color: colorScheme.error),
              ),
              onTap: () => choose(_CardAction.delete),
            ),
          ],
        ),
      );
    },
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case _CardAction.open:
      onOpen?.call();
    case _CardAction.toggleCompleted:
      await showCardActionResult(
        messenger,
        cards.setCompleted(
          boardId: boardId,
          cardId: card.id,
          isCompleted: !card.isCompleted,
        ),
      );
    case _CardAction.archive:
      if (!await confirmArchiveCard(context, card)) return;
      await showCardActionResult(
        messenger,
        cards.archiveCard(boardId: boardId, cardId: card.id),
        successMessage: 'Đã lưu trữ thẻ.',
      );
    case _CardAction.delete:
      if (!await confirmDeleteCard(context, card)) return;
      await showCardActionResult(
        messenger,
        cards.deleteCard(boardId: boardId, cardId: card.id),
        successMessage: 'Đã xóa thẻ.',
      );
  }
}
