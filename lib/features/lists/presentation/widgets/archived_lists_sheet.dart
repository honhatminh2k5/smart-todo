import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/list_providers.dart';

/// Bottom sheet hiển thị các List đã lưu trữ của một Board.
class ArchivedListsSheet extends ConsumerStatefulWidget {
  const ArchivedListsSheet({required this.boardId, super.key});

  final String boardId;

  static Future<void> show(BuildContext context, {required String boardId}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ArchivedListsSheet(boardId: boardId),
    );
  }

  @override
  ConsumerState<ArchivedListsSheet> createState() => _ArchivedListsSheetState();
}

class _ArchivedListsSheetState extends ConsumerState<ArchivedListsSheet> {
  final Set<String> _restoringIds = <String>{};

  Future<void> _restore(String listId) async {
    if (!_restoringIds.add(listId)) return;

    setState(() {});
    final success = await ref
        .read(boardListsControllerProvider.notifier)
        .unarchiveList(boardId: widget.boardId, listId: listId);

    if (!mounted) return;
    setState(() => _restoringIds.remove(listId));

    if (!success) {
      final message =
          ref.read(boardListsControllerProvider).errorMessage ??
          'Không thể khôi phục danh sách. Vui lòng thử lại.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final archivedLists = ref.watch(
      archivedBoardListsStreamProvider(widget.boardId),
    );

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Danh sách đã lưu trữ',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Khôi phục danh sách để hiển thị lại trên Board.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: archivedLists.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => _buildErrorState(context, error),
                  data: (lists) {
                    if (lists.isEmpty) return _buildEmptyState(context);
                    return ListView.separated(
                      itemCount: lists.length,
                      separatorBuilder: (_, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final list = lists[index];
                        final isRestoring = _restoringIds.contains(list.id);
                        return Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            leading: const Icon(Icons.archive_outlined),
                            title: Text(
                              list.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: FilledButton.tonal(
                              onPressed: isRestoring
                                  ? null
                                  : () => _restore(list.id),
                              child: isRestoring
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Khôi phục'),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.archive_outlined, size: 44, color: colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            'Chưa có danh sách đã lưu trữ',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, Object error) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, color: colorScheme.error, size: 40),
          const SizedBox(height: 8),
          Text(
            'Không tải được danh sách đã lưu trữ',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              color: colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            error.toString().replaceFirst('Exception: ', ''),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: () => ref.invalidate(
              archivedBoardListsStreamProvider(widget.boardId),
            ),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Thử lại'),
          ),
        ],
      ),
    );
  }
}
