import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_todo/features/collaboration/presentation/widgets/assignee_picker_sheet.dart';
import 'package:smart_todo/features/collaboration/presentation/widgets/card_comments_section.dart';
import 'package:smart_todo/features/collaboration/presentation/widgets/member_avatar.dart';
import 'package:smart_todo/features/lists/presentation/providers/list_providers.dart';

import '../../data/card_model.dart';
import '../../domain/card_rules.dart';
import '../card_format.dart';
import '../providers/card_providers.dart';
import '../widgets/card_actions.dart';

/// Màn hình xem và sửa nhanh một thẻ (UC05 3a–3g, UC06 1a–1d).
///
/// Tiêu đề tự lưu khi ngừng gõ. Chọn người được giao và bình luận ngay tại
/// đây (UC06). Mô tả, hạn chót, nhãn, checklist chỉ hiển thị; phần chỉnh sửa
/// thuộc chức năng Chi tiết card.
class CardDetailScreen extends ConsumerStatefulWidget {
  const CardDetailScreen({
    required this.boardId,
    required this.cardId,
    super.key,
  });

  final String boardId;
  final String cardId;

  @override
  ConsumerState<CardDetailScreen> createState() => _CardDetailScreenState();
}

enum _SaveStatus { idle, saving, saved, failed }

class _CardDetailScreenState extends ConsumerState<CardDetailScreen> {
  static const _autosaveDelay = Duration(milliseconds: 800);

  final _titleController = TextEditingController();
  final _titleFocus = FocusNode();
  late final CardsController _cards;
  late ScaffoldMessengerState _messenger;
  Timer? _autosave;
  String? _savedTitle;
  String? _savingTitle;
  String? _titleError;
  _SaveStatus _saveStatus = _SaveStatus.idle;

  /// Đã rời màn hình (tự lưu trữ/xóa hoặc thẻ bị người khác xóa).
  bool _leaving = false;

  ({String boardId, String cardId}) get _key =>
      (boardId: widget.boardId, cardId: widget.cardId);

  @override
  void initState() {
    super.initState();
    _cards = ref.read(cardsControllerProvider);
    _titleFocus.addListener(() {
      if (!_titleFocus.hasFocus) _saveTitle();
    });
    ref.listenManual(
      cardDetailProvider(_key),
      (_, next) => next.whenData(_onCardChanged),
      fireImmediately: true,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Lưu lại để vẫn báo lỗi được khi lần tự lưu cuối chạy lúc đóng màn hình.
    _messenger = ScaffoldMessenger.of(context);
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _titleController.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  void _onCardChanged(TaskCardModel? card) {
    if (_leaving) return;
    if (card == null || card.isArchived) {
      // UC05 3g: thành viên khác đã xóa (hoặc lưu trữ) thẻ đang mở.
      _leave(
        card == null
            ? 'Thẻ không còn tồn tại. Có thể thành viên khác đã xóa thẻ.'
            : 'Thẻ đã được lưu trữ bởi thành viên khác.',
      );
      return;
    }
    // Cập nhật tiêu đề từ thiết bị khác khi người dùng không đang sửa dở.
    final isDirty = _titleController.text.trim() != (_savedTitle ?? '');
    if (_savedTitle == null || !isDirty) {
      _titleController.text = card.title;
    }
    _savedTitle = card.title;
  }

  void _leave(String message) {
    _leaving = true;
    _autosave?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
      Navigator.of(context).maybePop();
    });
  }

  void _onTitleChanged(String value) {
    setState(() {
      _titleError = validateCardTitle(value);
      _saveStatus = _SaveStatus.idle;
    });
    _autosave?.cancel();
    _autosave = Timer(_autosaveDelay, _saveTitle);
  }

  /// Lưu tiêu đề nếu hợp lệ và khác bản đã lưu (UC05 3b).
  Future<void> _saveTitle() async {
    _autosave?.cancel();
    if (_leaving) return;
    final title = _titleController.text.trim();
    if (validateCardTitle(title) != null ||
        title == _savedTitle ||
        title == _savingTitle) {
      return;
    }

    _savingTitle = title;
    if (mounted) setState(() => _saveStatus = _SaveStatus.saving);
    final error = await _cards.renameCard(
      boardId: widget.boardId,
      cardId: widget.cardId,
      title: title,
    );
    if (_savingTitle == title) _savingTitle = null;
    if (error != null) {
      _messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
    }
    if (!mounted) return;
    setState(
      () =>
          _saveStatus = error == null ? _SaveStatus.saved : _SaveStatus.failed,
    );
  }

  void _toggleCompleted(TaskCardModel card) {
    showCardActionResult(
      ScaffoldMessenger.of(context),
      _cards.setCompleted(
        boardId: widget.boardId,
        cardId: widget.cardId,
        isCompleted: !card.isCompleted,
      ),
    );
  }

  Future<void> _archive(TaskCardModel card) async {
    if (!await confirmArchiveCard(context, card) || !mounted) return;
    _leaving = true;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    await showCardActionResult(
      messenger,
      _cards.archiveCard(boardId: widget.boardId, cardId: widget.cardId),
      successMessage: 'Đã lưu trữ thẻ.',
    );
  }

  Future<void> _delete(TaskCardModel card) async {
    if (!await confirmDeleteCard(context, card) || !mounted) return;
    _leaving = true;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    await showCardActionResult(
      messenger,
      _cards.deleteCard(boardId: widget.boardId, cardId: widget.cardId),
      successMessage: 'Đã xóa thẻ.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardAsync = ref.watch(cardDetailProvider(_key));
    final card = cardAsync.asData?.value;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _saveTitle();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Chi tiết thẻ'),
          actions: [
            if (card != null)
              PopupMenuButton<String>(
                tooltip: 'Thao tác thẻ',
                onSelected: (value) => switch (value) {
                  'archive' => _archive(card),
                  'delete' => _delete(card),
                  _ => null,
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'archive', child: Text('Lưu trữ thẻ')),
                  PopupMenuItem(value: 'delete', child: Text('Xóa thẻ')),
                ],
              ),
          ],
        ),
        body: cardAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Không tải được thẻ. ${describeCardError(error)}',
                textAlign: TextAlign.center,
              ),
            ),
          ),
          data: (card) => card == null || card.isArchived
              ? const Center(child: Text('Thẻ không còn tồn tại.'))
              : _buildContent(context, card),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, TaskCardModel card) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final lists =
        ref.watch(boardListsStreamProvider(widget.boardId)).asData?.value ??
        const [];
    final labels =
        ref.watch(boardLabelsProvider(widget.boardId)).asData?.value ??
        const {};
    final members =
        ref.watch(boardMembersProvider(widget.boardId)).asData?.value ??
        const {};

    final listName = lists
        .where((list) => list.id == card.listId)
        .map((list) => list.name)
        .firstOrNull;
    final cardLabels = [for (final id in card.labelIds) ?labels[id]];
    String nameOf(String uid) {
      final name = members[uid]?.displayName ?? '';
      return name.isEmpty ? 'Một thành viên' : name;
    }

    final dueAt = card.dueAt;
    final dueStatus = dueStatusOf(
      isCompleted: card.isCompleted,
      dueAt: dueAt,
      now: DateTime.now(),
    );
    final createdAt = card.createdAt;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        if (listName != null)
          Text(
            'Trong danh sách “$listName”',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _titleController,
          focusNode: _titleFocus,
          maxLength: kCardTitleMaxLength,
          minLines: 1,
          maxLines: 4,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.deny(RegExp(r'[\r\n]')),
          ],
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            labelText: 'Tiêu đề thẻ',
            border: const OutlineInputBorder(),
            errorText: _titleError,
            helperText: switch (_saveStatus) {
              _SaveStatus.saving => 'Đang lưu…',
              _SaveStatus.saved => 'Đã lưu',
              _SaveStatus.failed => 'Chưa lưu được thay đổi',
              _SaveStatus.idle => null,
            },
          ),
          onChanged: _onTitleChanged,
          onSubmitted: (_) => _saveTitle(),
        ),
        const SizedBox(height: 4),
        Material(
          color: card.isCompleted
              ? Colors.green.shade50
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          child: CheckboxListTile(
            value: card.isCompleted,
            onChanged: (_) => _toggleCompleted(card),
            controlAffinity: ListTileControlAffinity.leading,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: Text(
              card.isCompleted ? 'Đã hoàn thành' : 'Chưa hoàn thành',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              card.isCompleted
                  ? 'Bỏ chọn để đánh dấu chưa hoàn thành'
                  : 'Chọn để đánh dấu đã hoàn thành',
            ),
          ),
        ),
        const SizedBox(height: 16),
        _InfoRow(
          icon: Icons.label_outline_rounded,
          title: 'Nhãn',
          child: cardLabels.isEmpty
              ? const Text('Chưa có nhãn')
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final label in cardLabels)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: CircleAvatar(
                          backgroundColor: Color(label.color),
                          radius: 6,
                        ),
                        label: Text(label.name),
                      ),
                  ],
                ),
        ),
        _InfoRow(
          icon: Icons.schedule_rounded,
          title: 'Hạn chót',
          child: Text(
            dueAt == null
                ? 'Chưa đặt hạn'
                : '${formatDateTime(dueAt)} · ${dueStatusLabel(dueStatus)}',
          ),
        ),
        _InfoRow(
          icon: Icons.people_outline_rounded,
          title: 'Người được giao',
          trailing: Icon(
            Icons.edit_outlined,
            size: 18,
            color: colorScheme.onSurfaceVariant,
          ),
          onTap: () => showAssigneePicker(
            context,
            boardId: widget.boardId,
            cardId: widget.cardId,
          ),
          child: card.assigneeIds.isEmpty
              ? const Text('Chưa giao cho ai · Nhấn để chọn thành viên')
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final uid in card.assigneeIds)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: MemberAvatar(
                          uid: uid,
                          name: members[uid]?.displayName ?? '',
                          email: members[uid]?.email ?? '',
                          radius: 12,
                        ),
                        label: Text(nameOf(uid)),
                      ),
                  ],
                ),
        ),
        _InfoRow(
          icon: Icons.checklist_rounded,
          title: 'Checklist',
          child: Text(
            card.checklistTotal == 0
                ? 'Chưa có checklist'
                : '${card.checklistDone}/${card.checklistTotal} mục đã xong',
          ),
        ),
        _InfoRow(
          icon: Icons.notes_rounded,
          title: 'Mô tả',
          child: Text(
            card.description.isEmpty ? 'Chưa có mô tả' : card.description,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          createdAt == null
              ? 'Tạo bởi ${nameOf(card.createdBy)}'
              : 'Tạo bởi ${nameOf(card.createdBy)} lúc ${formatDateTime(createdAt)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const Divider(height: 32),
        CardCommentsSection(boardId: widget.boardId, cardId: widget.cardId),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

  /// Nhấn cả hàng để sửa mục này.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trailing = this.trailing;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                DefaultTextStyle.merge(
                  style: theme.textTheme.bodyMedium,
                  child: child,
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: row,
    );
  }
}
