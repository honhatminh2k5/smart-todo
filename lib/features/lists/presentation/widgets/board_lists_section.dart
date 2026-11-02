import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_todo/features/lists/data/list_model.dart';
import 'package:smart_todo/features/lists/presentation/providers/list_providers.dart';

import 'add_list_button.dart';
import 'list_title_editor.dart';

/// Widget hiển thị phần danh sách (Kanban columns) của một Board.
///
/// Lắng nghe luồng dữ liệu thời gian thực từ [boardListsStreamProvider].
class BoardListsSection extends ConsumerStatefulWidget {
  const BoardListsSection({required this.boardId, super.key});

  final String boardId;

  @override
  ConsumerState<BoardListsSection> createState() => _BoardListsSectionState();
}

class _BoardListsSectionState extends ConsumerState<BoardListsSection> {
  List<TaskListModel> _reorderingLists = const [];
  bool _isReordering = false;

  String get boardId => widget.boardId;

  @override
  Widget build(BuildContext context) {
    final listsAsync = ref.watch(boardListsStreamProvider(boardId));
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.view_column_rounded,
              size: 20,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              'Danh sách công việc',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        listsAsync.when(
          loading: () => _buildLoadingState(context),
          error: (error, _) => _buildErrorState(context, ref, error),
          data: (lists) {
            if (lists.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildEmptyState(context),
                  const SizedBox(height: 14),
                  AddListCard(boardId: boardId),
                ],
              );
            }
            return _buildListsView(context, ref, lists);
          },
        ),
      ],
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      height: 160,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 12),
            Text(
              'Đang tải danh sách...',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, WidgetRef ref, Object error) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, color: colorScheme.error, size: 32),
          const SizedBox(height: 8),
          Text(
            'Không tải được danh sách công việc',
            style: theme.textTheme.titleSmall?.copyWith(
              color: colorScheme.error,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            error.toString().replaceFirst('Exception: ', ''),
            textAlign: TextAlign.center,
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: () => ref.invalidate(boardListsStreamProvider(boardId)),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Thử lại'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.view_column_outlined,
            size: 44,
            color: colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'Chưa có danh sách nào',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Board này chưa có danh sách công việc. Bạn có thể tạo danh sách mới ở bước tiếp theo.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildListsView(
    BuildContext context,
    WidgetRef ref,
    List<TaskListModel> lists,
  ) {
    final displayedLists = _isReordering ? _reorderingLists : lists;

    return SizedBox(
      height: 320,
      child: Stack(
        children: [
          AbsorbPointer(
            absorbing: _isReordering,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: true,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(right: 4),
              footer: Padding(
                padding: const EdgeInsets.only(left: 14),
                child: AddListCard(boardId: boardId),
              ),
              itemCount: displayedLists.length,
              onReorderItem: (oldIndex, newIndex) =>
                  _reorderLists(displayedLists, oldIndex, newIndex),
              itemBuilder: (context, index) {
                final list = displayedLists[index];
                return Padding(
                  key: ValueKey(list.id),
                  padding: const EdgeInsets.only(right: 14),
                  child: _buildListCard(context, ref, list),
                );
              },
            ),
          ),
          if (_isReordering)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black26,
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Đang lưu thứ tự...',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _reorderLists(
    List<TaskListModel> lists,
    int oldIndex,
    int newIndex,
  ) async {
    if (_isReordering) return;
    final reordered = List<TaskListModel>.of(lists);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    setState(() {
      _isReordering = true;
      _reorderingLists = reordered;
    });

    final success = await ref
        .read(boardListsControllerProvider.notifier)
        .reorderLists(
          boardId: boardId,
          orderedListIds: reordered.map((list) => list.id).toList(),
        );

    if (!mounted) return;

    setState(() => _isReordering = false);
    if (success) return;

    ref.invalidate(boardListsStreamProvider(boardId));
    final message =
        ref.read(boardListsControllerProvider).errorMessage ??
        'Không thể lưu thứ tự danh sách. Vui lòng thử lại.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildListCard(
    BuildContext context,
    WidgetRef ref,
    TaskListModel list,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: 260,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: ListTitleEditor(boardId: boardId, list: list),
              ),
              const SizedBox(width: 8),
              Text(
                '0 thẻ',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              IconButton(
                tooltip: 'Thao tác danh sách',
                onPressed: () => _showListActions(context, ref, list),
                icon: const Icon(Icons.more_vert),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Placeholder khu vực thẻ công việc (UC05)
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.dashboard_customize_outlined,
                      size: 28,
                      color: colorScheme.outline,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Chưa có thẻ công việc',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Sẽ sẵn sàng ở UC05',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmArchive(
    BuildContext context,
    WidgetRef ref,
    TaskListModel list,
  ) async {
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        var isSubmitting = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final colorScheme = Theme.of(context).colorScheme;
            return AlertDialog(
              title: const Text('Lưu trữ danh sách?'),
              content: Text(
                'Danh sách “${list.name}” sẽ được lưu trữ và ẩn khỏi board hiện tại.',
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Hủy'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.error,
                    foregroundColor: colorScheme.onError,
                  ),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setDialogState(() => isSubmitting = true);
                          final success = await ref
                              .read(boardListsControllerProvider.notifier)
                              .archiveList(boardId: boardId, listId: list.id);

                          if (!dialogContext.mounted) return;
                          if (success) {
                            Navigator.of(dialogContext).pop(true);
                            return;
                          }

                          setDialogState(() => isSubmitting = false);
                          final message =
                              ref
                                  .read(boardListsControllerProvider)
                                  .errorMessage ??
                              'Không thể lưu trữ danh sách. Vui lòng thử lại.';
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(SnackBar(content: Text(message)));
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Lưu trữ'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showListActions(
    BuildContext context,
    WidgetRef ref,
    TaskListModel list,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: const Text('Lưu trữ danh sách'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              _confirmArchive(context, ref, list);
            },
          ),
        );
      },
    );
  }
}
