import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/card_rules.dart';
import '../providers/card_providers.dart';
import 'card_actions.dart';

/// Nút “Thêm thẻ” ở cuối list, mở ô nhập tiêu đề để thêm nhanh (UC05 bước 3–6).
class AddCardComposer extends ConsumerStatefulWidget {
  const AddCardComposer({
    required this.boardId,
    required this.listId,
    super.key,
  });

  final String boardId;
  final String listId;

  @override
  ConsumerState<AddCardComposer> createState() => _AddCardComposerState();
}

class _AddCardComposerState extends ConsumerState<AddCardComposer> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _isExpanded = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _expand() {
    setState(() => _isExpanded = true);
    _focusNode.requestFocus();
  }

  void _collapse() {
    _controller.clear();
    setState(() => _isExpanded = false);
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final title = _controller.text.trim();
    final cardsInList =
        ref
            .read(boardCardsProvider(widget.boardId))
            .asData
            ?.value
            .cardsInList(widget.listId) ??
        const [];

    // Xóa ô nhập ngay để thêm tiếp thẻ khác; thẻ mới hiện ra qua luồng dữ liệu.
    _controller.clear();
    _focusNode.requestFocus();
    showCardActionResult(
      ScaffoldMessenger.of(context),
      ref
          .read(cardsControllerProvider)
          .createCard(
            boardId: widget.boardId,
            listId: widget.listId,
            title: title,
            cardsInList: cardsInList,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (!_isExpanded) {
      return SizedBox(
        width: double.infinity,
        child: TextButton.icon(
          onPressed: _expand,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Thêm thẻ'),
          style: TextButton.styleFrom(
            alignment: Alignment.centerLeft,
            foregroundColor: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _controller,
            focusNode: _focusNode,
            maxLength: kCardTitleMaxLength,
            minLines: 1,
            maxLines: 3,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.deny(RegExp(r'[\r\n]')),
            ],
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Nhập tiêu đề thẻ…',
              filled: true,
              fillColor: colorScheme.surface,
              border: const OutlineInputBorder(),
            ),
            validator: validateCardTitle,
            // Giữ bàn phím mở sau khi thêm để nhập thẻ tiếp theo.
            onEditingComplete: () {},
            onFieldSubmitted: (_) => _submit(),
          ),
          Row(
            children: [
              FilledButton(onPressed: _submit, child: const Text('Thêm thẻ')),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Đóng',
                onPressed: _collapse,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
