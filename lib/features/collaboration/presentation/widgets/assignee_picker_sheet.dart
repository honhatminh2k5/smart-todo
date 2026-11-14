import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../cards/data/card_model.dart';
import '../../../cards/presentation/providers/card_providers.dart';
import '../providers/collaboration_providers.dart';
import 'member_avatar.dart';

/// Mở bảng chọn người được giao cho một thẻ (UC06 1a–1b).
Future<void> showAssigneePicker(
  BuildContext context, {
  required String boardId,
  required String cardId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => AssigneePickerSheet(boardId: boardId, cardId: cardId),
  );
}

/// Danh sách thành viên của board, đánh dấu người đang được giao.
///
/// Chỉ hiện thành viên của board nên không thể giao cho người ngoài (luật
/// I3). Mỗi lần chọn/bỏ chọn được lưu ngay; trạng thái thẻ cập nhật thời gian
/// thực nên lựa chọn của thành viên khác cũng hiện ra.
class AssigneePickerSheet extends ConsumerStatefulWidget {
  const AssigneePickerSheet({
    required this.boardId,
    required this.cardId,
    super.key,
  });

  final String boardId;
  final String cardId;

  @override
  ConsumerState<AssigneePickerSheet> createState() =>
      _AssigneePickerSheetState();
}

class _AssigneePickerSheetState extends ConsumerState<AssigneePickerSheet> {
  /// Lựa chọn đang chờ lưu, theo uid (hiện ngay để phản hồi nhanh).
  final Map<String, bool> _pending = {};
  String? _error;

  Future<void> _toggle(String memberUid, bool assigned) async {
    setState(() {
      _pending[memberUid] = assigned;
      _error = null;
    });
    final error = await ref
        .read(cardsControllerProvider)
        .setAssignee(
          boardId: widget.boardId,
          cardId: widget.cardId,
          memberUid: memberUid,
          assigned: assigned,
        );
    if (!mounted) return;
    setState(() {
      if (_pending[memberUid] == assigned) _pending.remove(memberUid);
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = ref
        .watch(
          cardDetailProvider((boardId: widget.boardId, cardId: widget.cardId)),
        )
        .asData
        ?.value;
    final membersAsync = ref.watch(boardCollaboratorsProvider(widget.boardId));
    final myUid = ref.watch(collaboratorIdProvider);
    final error = _error;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
              child: Text('Người được giao', style: theme.textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'Chỉ chọn được thành viên của board.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  error,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            Flexible(
              child: membersAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Không tải được thành viên. '
                    '${describeCollaborationError(error)}',
                  ),
                ),
                data: (members) => card == null
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Thẻ không còn tồn tại.'),
                      )
                    : ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.only(bottom: 16),
                        children: [
                          for (final member in members)
                            _buildMemberTile(card, member, myUid),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberTile(
    TaskCardModel card,
    BoardMember member,
    String? myUid,
  ) {
    final assigned =
        _pending[member.uid] ?? card.assigneeIds.contains(member.uid);
    final name = member.displayName.isNotEmpty
        ? member.displayName
        : member.email;
    return CheckboxListTile(
      value: assigned,
      onChanged: (value) => _toggle(member.uid, value ?? false),
      secondary: MemberAvatar(
        uid: member.uid,
        name: member.displayName,
        email: member.email,
      ),
      title: Text(member.uid == myUid ? '$name (Bạn)' : name),
      subtitle: member.email.isEmpty ? null : Text(member.email),
    );
  }
}
