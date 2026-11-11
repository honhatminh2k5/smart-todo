import 'package:flutter_test/flutter_test.dart';
import 'package:smart_todo/features/cards/data/card_model.dart';
import 'package:smart_todo/features/search/domain/search_filter_models.dart';

void main() {
  group('VietnameseUtils', () {
    test('normalize removes diacritics and converts to lowercase', () {
      expect(VietnameseUtils.normalize('THIET KE'), 'thiet ke');
      expect(
        VietnameseUtils.normalize('Thiết kế màn hình đăng nhập'),
        'thiet ke man hinh dang nhap',
      );
      expect(VietnameseUtils.normalize('kiem thu'), 'kiem thu');
      expect(VietnameseUtils.normalize('Kiểm thử'), 'kiem thu');
      expect(VietnameseUtils.normalize('Đồ án Đa năng'), 'do an da nang');
    });

    test('matches correctly regardless of case and accents', () {
      expect(
        VietnameseUtils.matches('Thiết kế màn hình đăng nhập', 'THIET KE'),
        isTrue,
      );
      expect(
        VietnameseUtils.matches('Thiết kế màn hình đăng nhập', 'man hinh'),
        isTrue,
      );
      expect(
        VietnameseUtils.matches('Thiết kế màn hình đăng nhập', 'kiem thu'),
        isFalse,
      );
    });
  });

  group('SearchFilterCriteria', () {
    final now = DateTime(2026, 10, 20, 17, 58);

    final card1 = TaskCardModel(
      id: 'card_1',
      boardId: 'b1',
      listId: 'l1',
      title: 'Thiết kế màn hình đăng nhập',
      position: 1000,
      createdBy: 'u1',
      labelIds: const ['label_design', 'label_urgent'],
      assigneeIds: const ['u_an', 'u_minh'],
      dueAt: DateTime(2026, 10, 21, 10), // within 24h -> dueSoon
      isCompleted: false,
    );

    final card2 = TaskCardModel(
      id: 'card_2',
      boardId: 'b1',
      listId: 'l1',
      title: 'Viết đặc tả use case',
      position: 2000,
      createdBy: 'u1',
      labelIds: const ['label_docs'],
      assigneeIds: const ['u_lan'],
      dueAt: DateTime(2026, 10, 26, 10), // normal
      isCompleted: false,
    );

    test('Empty criteria matches all cards', () {
      const criteria = SearchFilterCriteria();
      expect(criteria.matchesCard(card1, now: now), isTrue);
      expect(criteria.matchesCard(card2, now: now), isTrue);
    });

    test('Keyword only filter', () {
      const criteria = SearchFilterCriteria(keyword: 'THIET KE');
      expect(criteria.matchesCard(card1, now: now), isTrue);
      expect(criteria.matchesCard(card2, now: now), isFalse);
    });

    test(
      'Combined filter: keyword AND OR-labels AND assignee AND due AND completion',
      () {
        // Figma D08d scenario:
        // 'màn hình' AND (Thiết kế OR Flutter) AND Hoàng Minh AND Sắp đến hạn AND Chưa hoàn thành
        final criteria = SearchFilterCriteria(
          keyword: 'màn hình',
          selectedLabelIds: {'label_design', 'label_flutter'},
          selectedAssigneeIds: {'u_minh'},
          selectedDueFilters: {CardDueFilter.dueSoon},
          selectedCompletionFilters: {CardCompletionFilter.incomplete},
        );

        expect(criteria.activeFilterTypeCount, 4);
        expect(criteria.matchesCard(card1, now: now), isTrue);
        expect(criteria.matchesCard(card2, now: now), isFalse);
      },
    );

    test(
      'No matching results when keyword does not match with active filters (D08e)',
      () {
        final criteria = SearchFilterCriteria(
          keyword: 'kiem thu',
          selectedLabelIds: {'label_design', 'label_flutter'},
          selectedAssigneeIds: {'u_minh'},
          selectedDueFilters: {CardDueFilter.dueSoon},
          selectedCompletionFilters: {CardCompletionFilter.incomplete},
        );

        expect(criteria.matchesCard(card1, now: now), isFalse);
        expect(criteria.matchesCard(card2, now: now), isFalse);
      },
    );
  });
}
