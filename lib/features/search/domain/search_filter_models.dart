import '../../cards/data/card_model.dart';
import '../../cards/domain/card_rules.dart';

/// Tiện ích xử lý tiếng Việt: chuẩn hóa chuỗi và so khớp không phân biệt hoa/thường và dấu.
class VietnameseUtils {
  static const _vietnameseMap = {
    'a': 'àáảãạăằắẳẵặâầấẩẫậ',
    'A': 'ÀÁẢÃẠĂẰẮẲẴẶÂẦẤẨẪẬ',
    'd': 'đ',
    'D': 'Đ',
    'e': 'èéẻẽẹêềếểễệ',
    'E': 'ÈÉẺẼẸÊỀẾỂỄỆ',
    'i': 'ìíỉĩị',
    'I': 'ÌÍỈĨỊ',
    'o': 'òóỏõọôồốổỗộơờớởỡợ',
    'O': 'ÒÓỎÕỌÔỒỐỔỖỘƠỜỚỞỠỢ',
    'u': 'ùúủũụưừứửữự',
    'U': 'ÙÚỦŨỤƯỪỨỬỮỰ',
    'y': 'ỳýỷỹỵ',
    'Y': 'ỲÝỶỸỴ',
  };

  static final Map<int, String> _lookup = () {
    final map = <int, String>{};
    for (final entry in _vietnameseMap.entries) {
      final replacement = entry.key;
      for (final codeUnit in entry.value.runes) {
        map[codeUnit] = replacement;
      }
    }
    return map;
  }();

  /// Chuẩn hóa chuỗi: bỏ dấu tiếng Việt, chuyển chữ thường và cắt khoảng trắng đầu cuối.
  static String normalize(String input) {
    if (input.isEmpty) return '';
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final replaced = _lookup[rune];
      if (replaced != null) {
        buffer.write(replaced);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString().toLowerCase().trim();
  }

  /// So khớp tiêu đề với từ khóa, không phân biệt chữ hoa/thường và dấu tiếng Việt (UC08 bước 3–5).
  static bool matches(String text, String keyword) {
    final cleanKeyword = normalize(keyword);
    if (cleanKeyword.isEmpty) return true;
    final cleanText = normalize(text);
    return cleanText.contains(cleanKeyword);
  }
}

/// Tình trạng hạn chót dùng cho bộ lọc (UC08 3a).
enum CardDueFilter {
  overdue('Quá hạn'),
  dueSoon('Sắp đến hạn'),
  noDue('Không có hạn');

  const CardDueFilter(this.label);
  final String label;
}

/// Trạng thái hoàn thành dùng cho bộ lọc (UC08 3a).
enum CardCompletionFilter {
  incomplete('Chưa hoàn thành'),
  completed('Đã hoàn thành');

  const CardCompletionFilter(this.label);
  final String label;
}

/// Tiêu chí tìm kiếm và lọc card trong một board (UC08).
///
/// Quy tắc kết hợp (§ 7 firestore-access-patterns.md):
/// - Các loại điều kiện khác nhau kết hợp AND (từ khóa, nhãn, người được giao, hạn, hoàn thành).
/// - Trong cùng một loại điều kiện, chọn nhiều giá trị kết hợp OR.
/// - Từ khóa trống: chỉ áp dụng bộ lọc.
class SearchFilterCriteria {
  const SearchFilterCriteria({
    this.keyword = '',
    this.selectedLabelIds = const <String>{},
    this.selectedAssigneeIds = const <String>{},
    this.selectedDueFilters = const <CardDueFilter>{},
    this.selectedCompletionFilters = const <CardCompletionFilter>{},
  });

  /// Từ khóa tìm kiếm theo tiêu đề.
  final String keyword;

  /// Các ID nhãn được chọn (OR).
  final Set<String> selectedLabelIds;

  /// Các UID người được giao được chọn (OR).
  final Set<String> selectedAssigneeIds;

  /// Các điều kiện hạn chót được chọn (OR).
  final Set<CardDueFilter> selectedDueFilters;

  /// Các điều kiện hoàn thành được chọn (OR).
  final Set<CardCompletionFilter> selectedCompletionFilters;

  bool get isEmpty => keyword.trim().isEmpty && !hasAnyFilter;
  bool get hasKeyword => keyword.trim().isNotEmpty;
  bool get hasAnyFilter =>
      selectedLabelIds.isNotEmpty ||
      selectedAssigneeIds.isNotEmpty ||
      selectedDueFilters.isNotEmpty ||
      selectedCompletionFilters.isNotEmpty;

  /// Số nhóm điều kiện lọc đang kích hoạt (0..4).
  int get activeFilterTypeCount {
    var count = 0;
    if (selectedLabelIds.isNotEmpty) count++;
    if (selectedAssigneeIds.isNotEmpty) count++;
    if (selectedDueFilters.isNotEmpty) count++;
    if (selectedCompletionFilters.isNotEmpty) count++;
    return count;
  }

  /// Tổng số chip lọc đang chọn.
  int get totalFilterCount =>
      selectedLabelIds.length +
      selectedAssigneeIds.length +
      selectedDueFilters.length +
      selectedCompletionFilters.length;

  SearchFilterCriteria copyWith({
    String? keyword,
    Set<String>? selectedLabelIds,
    Set<String>? selectedAssigneeIds,
    Set<CardDueFilter>? selectedDueFilters,
    Set<CardCompletionFilter>? selectedCompletionFilters,
  }) {
    return SearchFilterCriteria(
      keyword: keyword ?? this.keyword,
      selectedLabelIds: selectedLabelIds ?? this.selectedLabelIds,
      selectedAssigneeIds: selectedAssigneeIds ?? this.selectedAssigneeIds,
      selectedDueFilters: selectedDueFilters ?? this.selectedDueFilters,
      selectedCompletionFilters:
          selectedCompletionFilters ?? this.selectedCompletionFilters,
    );
  }

  /// Xóa tất cả bộ lọc, giữ nguyên từ khóa nếu có.
  SearchFilterCriteria clearFilters() {
    return SearchFilterCriteria(
      keyword: keyword,
      selectedLabelIds: const {},
      selectedAssigneeIds: const {},
      selectedDueFilters: const {},
      selectedCompletionFilters: const {},
    );
  }

  /// Xóa cả từ khóa và mọi điều kiện lọc (UC08 3d).
  SearchFilterCriteria clearAll() => const SearchFilterCriteria();

  /// Kiểm tra một card có thỏa mãn toàn bộ tiêu chí hay không.
  bool matchesCard(TaskCardModel card, {required DateTime now}) {
    // 1. Tiêu đề khớp từ khóa (không phân biệt dấu/hoa thường)
    if (hasKeyword && !VietnameseUtils.matches(card.title, keyword)) {
      return false;
    }

    // 2. Nhãn (OR trong cùng loại)
    if (selectedLabelIds.isNotEmpty) {
      final hasMatchingLabel = card.labelIds.any(selectedLabelIds.contains);
      if (!hasMatchingLabel) return false;
    }

    // 3. Người được giao (OR trong cùng loại)
    if (selectedAssigneeIds.isNotEmpty) {
      final hasMatchingAssignee = card.assigneeIds.any(
        selectedAssigneeIds.contains,
      );
      if (!hasMatchingAssignee) return false;
    }

    // 4. Hạn chót (OR trong cùng loại)
    if (selectedDueFilters.isNotEmpty) {
      final status = dueStatusOf(
        isCompleted: card.isCompleted,
        dueAt: card.dueAt,
        now: now,
      );
      final hasMatchingDue = selectedDueFilters.any((filter) {
        return switch (filter) {
          CardDueFilter.overdue => status == CardDueStatus.overdue,
          CardDueFilter.dueSoon => status == CardDueStatus.dueSoon,
          CardDueFilter.noDue => status == CardDueStatus.none,
        };
      });
      if (!hasMatchingDue) return false;
    }

    // 5. Hoàn thành (OR trong cùng loại)
    if (selectedCompletionFilters.isNotEmpty) {
      final hasMatchingCompletion = selectedCompletionFilters.any((filter) {
        return switch (filter) {
          CardCompletionFilter.incomplete => !card.isCompleted,
          CardCompletionFilter.completed => card.isCompleted,
        };
      });
      if (!hasMatchingCompletion) return false;
    }

    return true;
  }
}
