import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_todo/features/cards/data/card_model.dart';
import 'package:smart_todo/features/cards/presentation/providers/card_providers.dart';
import 'package:smart_todo/features/cards/presentation/widgets/card_drag_controller.dart';
import 'package:smart_todo/features/cards/presentation/widgets/list_cards_panel.dart';
import 'package:smart_todo/features/cards/presentation/widgets/offline_banner.dart';
import 'package:smart_todo/features/lists/data/list_model.dart';
import 'package:smart_todo/features/lists/presentation/providers/list_providers.dart';

import 'add_list_button.dart';
import 'list_title_editor.dart';

/// Widget hiển thị phần danh sách (Kanban columns) của một Board.
///
/// Lắng nghe luồng dữ liệu thời gian thực từ [boardListsStreamProvider] và
/// [boardCardsProvider]. Nhấn giữ tiêu đề cột để đổi thứ tự list; nhấn giữ
/// một thẻ để kéo sang vị trí hoặc list khác.
class BoardListsSection extends ConsumerStatefulWidget {
  const BoardListsSection({required this.boardId, super.key});

  final String boardId;

  @override
  ConsumerState<BoardListsSection> createState() => _BoardListsSectionState();
}

class _BoardListsSectionState extends ConsumerState<BoardListsSection> {
  List<TaskListModel> _reorderingLists = const [];
  bool _isReordering = false;
  final _cardDrag = CardDragController();
  final _boardScroll = ScrollController();
  final _boardViewportKey = GlobalKey();

  String get boardId => widget.boardId;

  @override
  void initState() {
    super.initState();
    _cardDrag.attachBoard(_boardScroll, _boardViewportKey);
  }

  @override
  void dispose() {
    _cardDrag.dispose();
    _boardScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listsAsync = ref.watch(boardListsStreamProvider(boardId));
    final cardsAsync = ref.watch(boardCardsProvider(boardId));
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OfflineBanner(isOffline: cardsAsync.asData?.value.isFromCache ?? false),
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
            return _buildListsView(context, ref, lists, cardsAsync);
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
    AsyncValue<BoardCardsSnapshot> cardsAsync,
  ) {
    final displayedLists = _isReordering ? _reorderingLists : lists;
    final columnHeight = (MediaQuery.sizeOf(context).height * 0.62).clamp(
      380.0,
      640.0,
    );

    return SizedBox(
      key: _boardViewportKey,
      height: columnHeight,
      child: Stack(
        children: [
          AbsorbPointer(
            absorbing: _isReordering,
            child: ReorderableListView.builder(
              scrollController: _boardScroll,
              scrollDirection: Axis.horizontal,
              // Chỉ tiêu đề cột kéo được list; phần thân dành cho kéo thẻ.
              buildDefaultDragHandles: false,
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
                  child: _buildListCard(context, ref, list, index, cardsAsync),
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
    int index,
    AsyncValue<BoardCardsSnapshot> cardsAsync,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cards = cardsAsync.asData?.value.cardsInList(list.id) ?? const [];

    return Container(
      width: 260,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
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
      child: ListCardsPanel(
        boardId: boardId,
        listId: list.id,
        cards: cards,
        dragController: _cardDrag,
        isLoading: cardsAsync.isLoading,
        error: cardsAsync.error,
        // Header: nhấn giữ để kéo đổi thứ tự list.
        header: ReorderableDelayedDragStartListener(
          index: index,
          enabled: !_isReordering,
          child: Row(
            children: [
              Expanded(
                child: ListTitleEditor(boardId: boardId, list: list),
              ),
              const SizedBox(width: 8),
              Text(
                '${cards.length} thẻ',
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
        ),
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
                'Danh sách “${list.name}” và các thẻ trong đó sẽ được lưu trữ và ẩn khỏi board hiện tại.',
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
