import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../cards/data/card_model.dart';
import '../../../cards/presentation/providers/card_providers.dart';
import '../../../cards/presentation/screens/card_detail_screen.dart';
import '../../../cards/presentation/widgets/card_tile.dart';
import '../../../lists/data/list_model.dart';
import '../../../lists/presentation/providers/list_providers.dart';
import '../../domain/search_filter_models.dart';
import 'board_filter_sheet.dart';

/// Màn hình tìm kiếm và lọc công việc trong board (UC08).
///
/// Thể hiện đầy đủ 6 trạng thái theo thiết kế:
/// - D08a: Từ khóa trống, chưa lọc -> hiển thị các cột list cuộn ngang.
/// - D08b: Nhập từ khóa không dấu -> khớp tiêu đề tiếng Việt.
/// - D08c: Hộp thoại/Sheet bộ lọc đa tiêu chí (mở qua nút "Bộ lọc").
/// - D08d: Kết hợp từ khóa + bộ lọc nhiều loại (AND/OR).
/// - D08e: Không tìm thấy kết quả phù hợp -> thông báo và nút xóa bộ lọc.
/// - D08f: Lỗi đồng bộ -> tiếp tục tìm kiếm trên dữ liệu đã tải trong bộ nhớ đệm.
class BoardSearchScreen extends ConsumerStatefulWidget {
  const BoardSearchScreen({
    required this.boardId,
    required this.boardTitle,
    this.initialKeyword = '',
    this.now,
    super.key,
  });

  final String boardId;
  final String boardTitle;
  final String initialKeyword;
  final DateTime? now;

  @override
  ConsumerState<BoardSearchScreen> createState() => _BoardSearchScreenState();
}

class _BoardSearchScreenState extends ConsumerState<BoardSearchScreen> {
  late final TextEditingController _searchController;
  late SearchFilterCriteria _criteria;
  late DateTime _now;
  late DateTime _lastSyncedTime;
  bool _forceSyncError = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialKeyword);
    _criteria = SearchFilterCriteria(keyword: widget.initialKeyword);
    _now = widget.now ?? DateTime.now();
    _lastSyncedTime = widget.now ?? DateTime.now();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {
      _criteria = _criteria.copyWith(keyword: value);
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _criteria = _criteria.copyWith(keyword: '');
    });
  }

  void _clearAllFiltersAndKeyword() {
    _searchController.clear();
    setState(() {
      _criteria = _criteria.clearAll();
    });
  }

  Future<void> _openFilterSheet({
    required List<TaskCardModel> allCards,
    required List<CardLabel> labels,
    required List<BoardMember> members,
  }) async {
    final updated = await BoardFilterSheet.show(
      context,
      initialCriteria: _criteria,
      allCards: allCards,
      labels: labels,
      members: members,
      now: _now,
    );

    if (updated != null && mounted) {
      setState(() {
        _criteria = updated;
      });
    }
  }

  String _formatSyncTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    final month = time.month.toString().padLeft(2, '0');
    return '$hour:$minute, $day/$month';
  }

  @override
  Widget build(BuildContext context) {
    final cardsAsync = ref.watch(boardCardsProvider(widget.boardId));
    final listsAsync = ref.watch(boardListsStreamProvider(widget.boardId));
    final labelsMap =
        ref.watch(boardLabelsProvider(widget.boardId)).asData?.value ??
        const {};
    final membersMap =
        ref.watch(boardMembersProvider(widget.boardId)).asData?.value ??
        const {};

    final allCards = cardsAsync.asData?.value.cards ?? const <TaskCardModel>[];
    final isFromCache =
        cardsAsync.asData?.value.isFromCache ?? false || _forceSyncError;
    final activeLists = listsAsync.asData?.value ?? const <TaskListModel>[];

    final listNames = {for (final l in activeLists) l.id: l.name};
    final labelsList = labelsMap.values.toList();
    final membersList = membersMap.values.toList();

    // Lọc danh sách card theo tiêu chí
    final filteredCards = allCards
        .where((card) => _criteria.matchesCard(card, now: _now))
        .toList();

    final isInitialState = _criteria.isEmpty;
    final activeFilterCount = _criteria.activeFilterTypeCount;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.boardTitle,
          style: const TextStyle(
            color: Color(0xFF1E293B),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ô tìm kiếm tiêu đề
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tìm theo tiêu đề',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Tìm công việc...',
                      hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF4338CA),
                          width: 1.8,
                        ),
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, size: 20),
                              onPressed: _clearSearch,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Hàng số lượng và nút Bộ lọc
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isInitialState
                            ? '${allCards.length} công việc'
                            : '${filteredCards.length} kết quả',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF334155),
                        ),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF4338CA),
                          side: BorderSide(
                            color: activeFilterCount > 0
                                ? const Color(0xFF4338CA)
                                : const Color(0xFFCBD5E1),
                            width: activeFilterCount > 0 ? 1.5 : 1,
                          ),
                          backgroundColor: activeFilterCount > 0
                              ? const Color(0xFFEEF2FF)
                              : Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                        ),
                        onPressed: () => _openFilterSheet(
                          allCards: allCards,
                          labels: labelsList,
                          members: membersList,
                        ),
                        icon: const Icon(Icons.tune, size: 16),
                        label: Text(
                          activeFilterCount > 0
                              ? 'Bộ lọc - $activeFilterCount'
                              : 'Bộ lọc',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // D08b: Dòng phụ chú khi tìm không dấu
                  if (_criteria.hasKeyword && !_criteria.hasAnyFilter) ...[
                    const SizedBox(height: 4),
                    const Text(
                      'Khớp tiêu đề - không phân biệt dấu',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],

                  // D08d / D08e: Các chip bộ lọc đang chọn
                  if (_criteria.hasAnyFilter) ...[
                    const SizedBox(height: 8),
                    _buildActiveFilterChips(labelsMap, membersMap),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: _clearAllFiltersAndKeyword,
                        child: const Text(
                          'Xóa bộ lọc',
                          style: TextStyle(
                            color: Color(0xFF4338CA),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // D08f: Banner lỗi đồng bộ / offline
            if (isFromCache) _buildOfflineBanner(context),

            // D08d: Thông báo "Kết quả đã cập nhật" khi lọc kết hợp
            if (_criteria.hasKeyword &&
                _criteria.hasAnyFilter &&
                filteredCards.isNotEmpty &&
                !isFromCache)
              _buildUpdatedNotice(),

            // Phần thân nội dung: D08a vs D08e vs Kết quả D08b/D08d/D08f
            Expanded(
              child: cardsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => _buildErrorState(err),
                data: (_) {
                  if (isInitialState) {
                    // D08a: Từ khóa trống, chưa lọc -> hiển thị các cột list cuộn ngang
                    return _buildHorizontalListsView(
                      activeLists: activeLists,
                      allCards: allCards,
                    );
                  }

                  if (filteredCards.isEmpty) {
                    // D08e: Không tìm thấy kết quả phù hợp
                    return _buildEmptyResultsView();
                  }

                  // D08b, D08d, D08f: Danh sách kết quả phù hợp
                  return _buildResultsListView(
                    filteredCards: filteredCards,
                    listNames: listNames,
                    isFromCache: isFromCache,
                    totalListsCount: activeLists.length,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Chip hiển thị các điều kiện lọc đang kích hoạt
  Widget _buildActiveFilterChips(
    Map<String, CardLabel> labelsMap,
    Map<String, BoardMember> membersMap,
  ) {
    final chips = <Widget>[];

    for (final labelId in _criteria.selectedLabelIds) {
      final label = labelsMap[labelId];
      if (label != null) {
        chips.add(_activeChip(label.name));
      }
    }

    for (final uid in _criteria.selectedAssigneeIds) {
      final member = membersMap[uid];
      if (member != null) {
        chips.add(_activeChip(member.displayName));
      }
    }

    for (final due in _criteria.selectedDueFilters) {
      chips.add(_activeChip(due.label));
    }

    for (final completion in _criteria.selectedCompletionFilters) {
      chips.add(_activeChip(completion.label));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final chip in chips) ...[chip, const SizedBox(width: 6)],
        ],
      ),
    );
  }

  Widget _activeChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC7D2FE)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check, size: 14, color: Color(0xFF4338CA)),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF4338CA),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// D08f: Banner cảnh báo không thể đồng bộ board
  Widget _buildOfflineBanner(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECDD3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            color: Color(0xFFE11D48),
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Không thể đồng bộ board',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF9F1239),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Mất kết nối hoặc máy chủ không phản hồi. Đang tìm trên dữ liệu đã tải lúc: ${_formatSyncTime(_lastSyncedTime)}.',
                  style: const TextStyle(
                    color: Color(0xFFBE123C),
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () {
                    setState(() {
                      _now = DateTime.now();
                      _lastSyncedTime = DateTime.now();
                      _forceSyncError = false;
                    });
                    ref.invalidate(boardCardsProvider(widget.boardId));
                  },
                  child: const Text(
                    'Thử đồng bộ lại',
                    style: TextStyle(
                      color: Color(0xFF9F1239),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// D08d: Banner thông báo kết quả cập nhật
  Widget _buildUpdatedNotice() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFC7D2FE)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: Color(0xFF4338CA), size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kết quả đã cập nhật',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3730A3),
                  ),
                ),
                Text(
                  'Chỉ hiển thị công việc khớp tất cả các loại điều kiện đang chọn.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF4338CA)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// D08a: Màn hình khi từ khóa trống và chưa lọc: cuộn ngang các list và card
  Widget _buildHorizontalListsView({
    required List<TaskListModel> activeLists,
    required List<TaskCardModel> allCards,
  }) {
    if (activeLists.isEmpty) {
      return const Center(
        child: Text(
          'Board chưa có danh sách nào.',
          style: TextStyle(color: Color(0xFF64748B)),
        ),
      );
    }

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      itemCount: activeLists.length,
      itemBuilder: (context, index) {
        final list = activeLists[index];
        final cardsInList = allCards.where((c) => c.listId == list.id).toList()
          ..sort(TaskCardModel.compare);

        return Container(
          width: 290,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tiêu đề list: "Cần làm - 3"
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Text(
                  '${list.name} - ${cardsInList.length}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),

              // Danh sách card trong cột
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  itemCount: cardsInList.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, cardIndex) {
                    final card = cardsInList[cardIndex];
                    return CardTile(
                      boardId: widget.boardId,
                      card: card,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CardDetailScreen(
                            boardId: widget.boardId,
                            cardId: card.id,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// D08e: Không tìm thấy kết quả phù hợp
  Widget _buildEmptyResultsView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: Color(0xFFEEF2FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.search_off_rounded,
                size: 42,
                color: Color(0xFF4338CA),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Không tìm thấy công việc phù hợp',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Thử xóa bộ lọc và từ khóa để xem lại tất cả công việc trong board.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 180,
              height: 44,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4338CA),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _clearAllFiltersAndKeyword,
                child: const Text(
                  'Xóa bộ lọc',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// D08b, D08d, D08f: Danh sách kết quả phù hợp kèm tiêu đề breadcrumb
  Widget _buildResultsListView({
    required List<TaskCardModel> filteredCards,
    required Map<String, String> listNames,
    required bool isFromCache,
    required int totalListsCount,
  }) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: filteredCards.length + 1,
      itemBuilder: (context, index) {
        if (index == filteredCards.length) {
          // Footer note
          return Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Center(
              child: Text(
                isFromCache
                    ? '${filteredCards.length} kết quả trong $totalListsCount/$totalListsCount list đã tải · Chưa kiểm tra được thay đổi mới nhất trên board.'
                    : 'Các card không khớp đã được ẩn.',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final card = filteredCards[index];
        final listName = listNames[card.listId] ?? 'Danh sách';

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Breadcrumb: "Khóa luận tốt nghiệp · Cần làm"
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 6),
                child: Text(
                  '${widget.boardTitle} · $listName',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
              CardTile(
                boardId: widget.boardId,
                card: card,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CardDetailScreen(
                      boardId: widget.boardId,
                      cardId: card.id,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildErrorState(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Color(0xFFEF4444)),
            const SizedBox(height: 12),
            Text(
              'Lỗi tải dữ liệu: $error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }
}
