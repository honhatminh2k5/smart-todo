import 'package:flutter/material.dart';

import '../domain/card_rules.dart';

String _twoDigits(int value) => value.toString().padLeft(2, '0');

/// `dd/MM`, kèm năm nếu khác năm hiện tại.
String formatShortDate(DateTime date, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final day = '${_twoDigits(date.day)}/${_twoDigits(date.month)}';
  return date.year == current.year ? day : '$day/${date.year}';
}

/// `dd/MM/yyyy HH:mm`.
String formatDateTime(DateTime date) =>
    '${_twoDigits(date.day)}/${_twoDigits(date.month)}/${date.year} '
    '${_twoDigits(date.hour)}:${_twoDigits(date.minute)}';

String dueStatusLabel(CardDueStatus status) => switch (status) {
  CardDueStatus.completed => 'Đã hoàn thành',
  CardDueStatus.none => 'Không có hạn',
  CardDueStatus.overdue => 'Quá hạn',
  CardDueStatus.dueSoon => 'Sắp đến hạn',
  CardDueStatus.normal => 'Còn hạn',
};

/// Màu nền và màu chữ của chip hạn chót.
(Color, Color) dueStatusColors(CardDueStatus status, ColorScheme colorScheme) {
  return switch (status) {
    CardDueStatus.completed => (Colors.green.shade100, Colors.green.shade900),
    CardDueStatus.overdue => (
      colorScheme.errorContainer,
      colorScheme.onErrorContainer,
    ),
    CardDueStatus.dueSoon => (Colors.amber.shade100, Colors.brown.shade800),
    CardDueStatus.none || CardDueStatus.normal => (
      colorScheme.surfaceContainerHighest,
      colorScheme.onSurfaceVariant,
    ),
  };
}
