import 'package:flutter/material.dart';

import '../../../cards/data/card_model.dart';
import '../../domain/search_filter_models.dart';

/// Màn hình/Sheet bộ lọc công việc theo 4 loại điều kiện (UC08 - D08c).
///
/// Nhiều lựa chọn trong cùng loại kết hợp OR.
/// Giữa các loại khác nhau và từ khóa kết hợp AND.
/// Số lượng kết quả cập nhật tức thời khi người dùng thay đổi lựa chọn.
class BoardFilterSheet extends StatefulWidget {
  const BoardFilterSheet({
    required this.initialCriteria,
    required this.allCards,
    required this.labels,
    required this.members,
    required this.now,
    super.key,
  });

  final SearchFilterCriteria initialCriteria;
  final List<TaskCardModel> allCards;
  final List<CardLabel> labels;
  final List<BoardMember> members;
  final DateTime now;

  static Future<SearchFilterCriteria?> show(
    BuildContext context, {
    required SearchFilterCriteria initialCriteria,
    required List<TaskCardModel> allCards,
    required List<CardLabel> labels,
    required List<BoardMember> members,
    required DateTime now,
  }) {
    return Navigator.of(context).push<SearchFilterCriteria>(
      MaterialPageRoute(
        builder: (_) => BoardFilterSheet(
          initialCriteria: initialCriteria,
          allCards: allCards,
          labels: labels,
          members: members,
          now: now,
        ),
      ),
    );
  }

  @override
  State<BoardFilterSheet> createState() => _BoardFilterSheetState();
}

class _BoardFilterSheetState extends State<BoardFilterSheet> {
  late SearchFilterCriteria _criteria;

  @override
  void initState() {
    super.initState();
    _criteria = widget.initialCriteria;
  }

  int get _matchingCount {
    return widget.allCards
        .where((card) => _criteria.matchesCard(card, now: widget.now))
        .length;
  }

  void _toggleLabel(String labelId) {
    final updated = Set<String>.from(_criteria.selectedLabelIds);
    if (updated.contains(labelId)) {
      updated.remove(labelId);
    } else {
      updated.add(labelId);
    }
    setState(() {
      _criteria = _criteria.copyWith(selectedLabelIds: updated);
    });
  }

  void _toggleAssignee(String uid) {
    final updated = Set<String>.from(_criteria.selectedAssigneeIds);
    if (updated.contains(uid)) {
      updated.remove(uid);
    } else {
      updated.add(uid);
    }
    setState(() {
      _criteria = _criteria.copyWith(selectedAssigneeIds: updated);
    });
  }

  void _toggleDue(CardDueFilter filter) {
    final updated = Set<CardDueFilter>.from(_criteria.selectedDueFilters);
    if (updated.contains(filter)) {
      updated.remove(filter);
    } else {
      updated.add(filter);
    }
    setState(() {
      _criteria = _criteria.copyWith(selectedDueFilters: updated);
    });
  }

  void _toggleCompletion(CardCompletionFilter filter) {
    final updated = Set<CardCompletionFilter>.from(
      _criteria.selectedCompletionFilters,
    );
    if (updated.contains(filter)) {
      updated.remove(filter);
    } else {
      updated.add(filter);
    }
    setState(() {
      _criteria = _criteria.copyWith(selectedCompletionFilters: updated);
    });
  }

  void _clearFilters() {
    setState(() {
      _criteria = _criteria.clearFilters();
    });
  }

  @override
  Widget build(BuildContext context) {
    final count = _matchingCount;
    final keywordText = _criteria.hasKeyword
        ? 'Từ khóa: ${_criteria.keyword.trim()} · Cập nhật tức thời'
        : 'Cập nhật tức thời';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(_criteria),
        ),
        title: const Text(
          'Bộ lọc',
          style: TextStyle(
            color: Color(0xFF1E293B),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(left: 20, right: 20, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                keywordText,
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                children: [
                  // Nhãn
                  _FilterSection(
                    title: 'Nhãn',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final label in widget.labels)
                          _FilterChipItem(
                            label: label.name,
                            isSelected: _criteria.selectedLabelIds.contains(
                              label.id,
                            ),
                            dotColor: Color(label.color),
                            onTap: () => _toggleLabel(label.id),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Người được giao
                  _FilterSection(
                    title: 'Người được giao',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final member in widget.members)
                          _FilterChipItem(
                            label: member.displayName.isNotEmpty
                                ? member.displayName
                                : member.email,
                            isSelected: _criteria.selectedAssigneeIds.contains(
                              member.uid,
                            ),
                            onTap: () => _toggleAssignee(member.uid),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Hạn chót
                  _FilterSection(
                    title: 'Hạn chót',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final due in CardDueFilter.values)
                          _FilterChipItem(
                            label: due.label,
                            isSelected: _criteria.selectedDueFilters.contains(
                              due,
                            ),
                            onTap: () => _toggleDue(due),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Hoàn thành
                  _FilterSection(
                    title: 'Hoàn thành',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final completion in CardCompletionFilter.values)
                          _FilterChipItem(
                            label: completion.label,
                            isSelected: _criteria.selectedCompletionFilters
                                .contains(completion),
                            onTap: () => _toggleCompletion(completion),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Ghi chú quy tắc
                  const Center(
                    child: Text(
                      'Cùng loại: OR · Khác loại và từ khóa: AND',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),

            // Nút bấm ở dưới đáy (D08c)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF4338CA),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(_criteria),
                      child: Text(
                        'Đóng bộ lọc - $count kết quả',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _criteria.hasAnyFilter ? _clearFilters : null,
                    child: const Text(
                      'Xóa bộ lọc',
                      style: TextStyle(
                        color: Color(0xFF4338CA),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterSection extends StatelessWidget {
  const _FilterSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _FilterChipItem extends StatelessWidget {
  const _FilterChipItem({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.dotColor,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    final bg = isSelected ? const Color(0xFFEEF2FF) : const Color(0xFFF1F5F9);
    final border = isSelected
        ? const Color(0xFF6366F1)
        : const Color(0xFFE2E8F0);
    final textColor = isSelected
        ? const Color(0xFF4338CA)
        : const Color(0xFF334155);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border, width: isSelected ? 1.5 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              const Icon(Icons.check, size: 16, color: Color(0xFF4338CA)),
              const SizedBox(width: 4),
            ] else if (dotColor != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
