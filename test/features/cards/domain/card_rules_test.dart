import 'package:flutter_test/flutter_test.dart';
import 'package:smart_todo/features/cards/domain/card_rules.dart';

void main() {
  group('validateCardTitle (UC05 bước 6, 5a)', () {
    test('rejects empty or whitespace-only titles', () {
      expect(validateCardTitle(''), isNotNull);
      expect(validateCardTitle('   '), isNotNull);
      expect(validateCardTitle(null), isNotNull);
    });

    test('accepts 1 to 200 characters after trimming', () {
      expect(validateCardTitle('A'), isNull);
      expect(validateCardTitle('a' * 200), isNull);
      expect(validateCardTitle('  ${'a' * 200}  '), isNull);
    });

    test('rejects titles longer than 200 characters', () {
      expect(validateCardTitle('a' * 201), 'Tiêu đề thẻ tối đa 200 ký tự.');
    });

    test('normalizeCardTitle trims or throws ArgumentError', () {
      expect(normalizeCardTitle('  Viết báo cáo  '), 'Viết báo cáo');
      expect(() => normalizeCardTitle(' '), throwsArgumentError);
    });
  });

  group('positionBetween (access patterns § 5)', () {
    test('matches the documented examples', () {
      expect(positionBetween(null, null), 1024);
      expect(positionBetween(3072, null), 4096);
      expect(positionBetween(1024, 2048), 1536);
      expect(positionBetween(null, 1024), 512);
    });

    test('returns null when neighbours are too close', () {
      expect(positionBetween(1, 1 + kMinPositionGap / 2), isNull);
      expect(positionBetween(null, 0), isNull);
    });
  });

  group('dueStatusOf (access patterns § 6)', () {
    final now = DateTime(2026, 11, 3, 12);

    test('applies the rules in order', () {
      DateTime inHours(int hours) => now.add(Duration(hours: hours));
      CardDueStatus status(DateTime? dueAt, {bool done = false}) =>
          dueStatusOf(isCompleted: done, dueAt: dueAt, now: now);

      expect(status(inHours(-5), done: true), CardDueStatus.completed);
      expect(status(null), CardDueStatus.none);
      expect(status(inHours(-1)), CardDueStatus.overdue);
      expect(status(inHours(24)), CardDueStatus.dueSoon);
      expect(status(inHours(25)), CardDueStatus.normal);
    });
  });
}
