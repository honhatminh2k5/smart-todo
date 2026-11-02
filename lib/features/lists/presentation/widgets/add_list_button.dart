import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/list_providers.dart';

/// Inline card used to create a list in the current board.
class AddListCard extends ConsumerStatefulWidget {
  const AddListCard({required this.boardId, super.key});

  final String boardId;

  @override
  ConsumerState<AddListCard> createState() => _AddListCardState();
}

class _AddListCardState extends ConsumerState<AddListCard> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  bool _isExpanded = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSubmitting = true);
    final success = await ref
        .read(boardListsControllerProvider.notifier)
        .createList(boardId: widget.boardId, name: _controller.text.trim());

    if (!mounted) return;

    setState(() => _isSubmitting = false);
    if (success) {
      _controller.clear();
      setState(() => _isExpanded = false);
      return;
    }

    final message =
        ref.read(boardListsControllerProvider).errorMessage ??
        'Không thể tạo danh sách. Vui lòng thử lại.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _collapse() {
    if (_isSubmitting) return;
    _controller.clear();
    setState(() => _isExpanded = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (!_isExpanded) {
      return SizedBox(
        width: 260,
        height: 320,
        child: OutlinedButton.icon(
          onPressed: () => setState(() => _isExpanded = true),
          icon: const Icon(Icons.add_rounded),
          label: const Text(' Thêm danh sách'),
          style: OutlinedButton.styleFrom(
            foregroundColor: colorScheme.primary,
            backgroundColor: colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.3,
            ),
            side: BorderSide(color: colorScheme.outlineVariant),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: 260,
      height: 320,
      child: Card(
        margin: EdgeInsets.zero,
        color: colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Thêm danh sách',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _controller,
                  autofocus: true,
                  enabled: !_isSubmitting,
                  maxLength: 100,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Tên danh sách',
                    hintText: 'Ví dụ: Cần làm',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final name = value?.trim() ?? '';
                    if (name.isEmpty) return 'Vui lòng nhập tên danh sách';
                    if (name.length > 100) {
                      return 'Tên danh sách tối đa 100 ký tự';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tối đa 100 ký tự',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSubmitting ? null : _collapse,
                      child: const Text('Hủy'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Thêm'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
