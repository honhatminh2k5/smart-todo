import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/list_model.dart';
import '../providers/list_providers.dart';

/// Inline editor for a list title.
class ListTitleEditor extends ConsumerStatefulWidget {
  const ListTitleEditor({required this.boardId, required this.list, super.key});

  final String boardId;
  final TaskListModel list;

  @override
  ConsumerState<ListTitleEditor> createState() => _ListTitleEditorState();
}

class _ListTitleEditorState extends ConsumerState<ListTitleEditor> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _isEditing = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.list.name;
  }

  @override
  void didUpdateWidget(covariant ListTitleEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditing && oldWidget.list.name != widget.list.name) {
      _controller.text = widget.list.name;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startEditing() {
    if (_isSubmitting) return;
    _controller.text = widget.list.name;
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    setState(() => _isEditing = true);
    _focusNode.requestFocus();
  }

  void _cancel() {
    if (_isSubmitting) return;
    _controller.text = widget.list.name;
    setState(() => _isEditing = false);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSubmitting = true);
    final success = await ref
        .read(boardListsControllerProvider.notifier)
        .renameList(
          boardId: widget.boardId,
          listId: widget.list.id,
          newName: _controller.text.trim(),
        );

    if (!mounted) return;

    setState(() => _isSubmitting = false);
    if (success) {
      setState(() => _isEditing = false);
      return;
    }

    final message =
        ref.read(boardListsControllerProvider).errorMessage ??
        'Không thể đổi tên danh sách. Vui lòng thử lại.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (!_isEditing) {
      return InkWell(
        onTap: _startEditing,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(
            widget.list.name,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _cancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Form(
        key: _formKey,
        child: Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _controller,
                autofocus: true,
                enabled: !_isSubmitting,
                maxLength: 100,
                maxLines: 1,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  isDense: true,
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final name = value?.trim() ?? '';
                  if (name.isEmpty) return 'Tên không được để trống';
                  if (name.length > 100) {
                    return 'Tên tối đa 100 ký tự';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _save(),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Lưu',
              onPressed: _isSubmitting ? null : _save,
              icon: _isSubmitting
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.primary,
                      ),
                    )
                  : const Icon(Icons.check_rounded),
            ),
            IconButton(
              tooltip: 'Hủy',
              onPressed: _isSubmitting ? null : _cancel,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compatibility dialog retained for the older list-column prototype.
class ListTitleEditorDialog extends StatefulWidget {
  const ListTitleEditorDialog({required this.initialName, super.key});

  final String initialName;

  static Future<String?> show(
    BuildContext context, {
    required String initialName,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => ListTitleEditorDialog(initialName: initialName),
    );
  }

  @override
  State<ListTitleEditorDialog> createState() => _ListTitleEditorDialogState();
}

class _ListTitleEditorDialogState extends State<ListTitleEditorDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Đổi tên danh sách'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 100,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Lưu')),
      ],
    );
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty || name.length > 100) return;
    Navigator.of(context).pop(name);
  }
}
