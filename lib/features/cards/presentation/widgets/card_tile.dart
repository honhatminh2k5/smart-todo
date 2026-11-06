import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/card_model.dart';
import '../../domain/card_rules.dart';
import '../card_format.dart';
import '../providers/card_providers.dart';

/// Thẻ tóm tắt trong list (UC05 bước 2): tiêu đề, nhãn, hạn chót, tiến độ
/// checklist, số bình luận và avatar người được giao.
class CardTile extends ConsumerWidget {
  const CardTile({
    required this.boardId,
    required this.card,
    this.onTap,
    this.onToggleCompleted,
    this.onMore,
    this.elevated = false,
    super.key,
  });

  final String boardId;
  final TaskCardModel card;
  final VoidCallback? onTap;
  final VoidCallback? onToggleCompleted;
  final VoidCallback? onMore;

  /// Vẽ nổi lên khi thẻ đang được kéo.
  final bool elevated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final labels =
        ref.watch(boardLabelsProvider(boardId)).asData?.value ?? const {};
    final members =
        ref.watch(boardMembersProvider(boardId)).asData?.value ?? const {};

    final cardLabels = [for (final id in card.labelIds) ?labels[id]];
    final assignees = [
      for (final uid in card.assigneeIds)
        members[uid] ??
            BoardMember(uid: uid, displayName: '', email: '', role: 'member'),
    ];
    final dueAt = card.dueAt;
    final badges = <Widget>[
      if (dueAt != null) _DueBadge(card: card, dueAt: dueAt),
      if (card.checklistTotal > 0)
        _CountBadge(
          icon: Icons.check_box_outlined,
          text: '${card.checklistDone}/${card.checklistTotal}',
          tooltip: 'Checklist',
          highlighted: card.checklistDone == card.checklistTotal,
        ),
      if (card.commentCount > 0)
        _CountBadge(
          icon: Icons.chat_bubble_outline_rounded,
          text: '${card.commentCount}',
          tooltip: 'Bình luận',
        ),
    ];

    return Material(
      color: colorScheme.surface,
      elevation: elevated ? 6 : 0,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 0, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (cardLabels.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final label in cardLabels) _LabelChip(label: label),
                    ],
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    tooltip: card.isCompleted
                        ? 'Bỏ đánh dấu hoàn thành'
                        : 'Đánh dấu hoàn thành',
                    visualDensity: VisualDensity.compact,
                    iconSize: 20,
                    onPressed: onToggleCompleted,
                    icon: card.isCompleted
                        ? Icon(
                            Icons.check_circle_rounded,
                            color: Colors.green.shade600,
                          )
                        : Icon(
                            Icons.radio_button_unchecked_rounded,
                            color: colorScheme.outline,
                          ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        card.title,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          decoration: card.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                          color: card.isCompleted
                              ? colorScheme.onSurfaceVariant
                              : colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                  if (onMore != null)
                    IconButton(
                      tooltip: 'Thao tác thẻ',
                      visualDensity: VisualDensity.compact,
                      iconSize: 18,
                      onPressed: onMore,
                      icon: const Icon(Icons.more_horiz_rounded),
                    ),
                ],
              ),
              if (badges.isNotEmpty || assignees.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 2, 10, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: badges,
                        ),
                      ),
                      if (assignees.isNotEmpty)
                        _AssigneeAvatars(assignees: assignees),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LabelChip extends StatelessWidget {
  const _LabelChip({required this.label});

  final CardLabel label;

  @override
  Widget build(BuildContext context) {
    final color = Color(label.color);
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label.name,
        style: TextStyle(
          color: onColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DueBadge extends StatelessWidget {
  const _DueBadge({required this.card, required this.dueAt});

  final TaskCardModel card;
  final DateTime dueAt;

  @override
  Widget build(BuildContext context) {
    final status = dueStatusOf(
      isCompleted: card.isCompleted,
      dueAt: dueAt,
      now: DateTime.now(),
    );
    final (background, foreground) = dueStatusColors(
      status,
      Theme.of(context).colorScheme,
    );
    return Tooltip(
      message: 'Hạn chót: ${formatDateTime(dueAt)} · ${dueStatusLabel(status)}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_rounded, size: 13, color: foreground),
            const SizedBox(width: 3),
            Text(
              formatShortDate(dueAt),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({
    required this.icon,
    required this.text,
    required this.tooltip,
    this.highlighted = false,
  });

  final IconData icon;
  final String text;
  final String tooltip;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final color = highlighted
        ? Colors.green.shade700
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Tooltip(
      message: tooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _AssigneeAvatars extends StatelessWidget {
  const _AssigneeAvatars({required this.assignees});

  final List<BoardMember> assignees;

  static const _maxShown = 3;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final shown = assignees.take(_maxShown).toList();
    final hidden = assignees.length - shown.length;

    Widget avatar(Widget child, Color color, String tooltip) {
      return Tooltip(
        message: tooltip,
        child: Container(
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            shape: BoxShape.circle,
          ),
          child: CircleAvatar(radius: 11, backgroundColor: color, child: child),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final member in shown)
          Align(
            widthFactor: 0.75,
            child: avatar(
              Text(
                member.initial,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              _avatarColor(member.uid),
              member.displayName.isEmpty ? 'Thành viên' : member.displayName,
            ),
          ),
        if (hidden > 0)
          Align(
            widthFactor: 0.75,
            child: avatar(
              Text(
                '+$hidden',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
              colorScheme.secondaryContainer,
              '$hidden người khác',
            ),
          ),
      ],
    );
  }

  /// Màu cố định theo uid để mỗi người luôn có cùng một màu.
  static Color _avatarColor(String uid) {
    final hash = uid.codeUnits.fold<int>(0, (sum, unit) => sum + unit);
    return Colors.primaries[hash % Colors.primaries.length].shade400;
  }
}
