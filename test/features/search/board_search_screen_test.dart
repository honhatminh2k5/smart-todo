import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_todo/features/search/presentation/screens/board_search_screen.dart';

void main() {
  Widget buildTestApp({String initialKeyword = ''}) {
    return ProviderScope(
      child: MaterialApp(
        home: BoardSearchScreen(
          boardId: 'uc08_board',
          boardTitle: 'Khóa luận tốt nghiệp',
          initialKeyword: initialKeyword,
          now: DateTime(2026, 10, 20, 17, 58),
        ),
      ),
    );
  }

  testWidgets(
    'D08a: Mở tìm kiếm với từ khóa trống -> hiển thị 7 công việc trong 2 list',
    (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Khóa luận tốt nghiệp'), findsOneWidget);
      expect(find.text('Tìm theo tiêu đề'), findsOneWidget);
      expect(find.text('7 công việc'), findsOneWidget);
      expect(find.text('Bộ lọc'), findsOneWidget);

      // Hiển thị 2 list cuộn ngang: "Cần làm - 3" và "Đang làm - 4"
      expect(find.text('Cần làm - 3'), findsOneWidget);
      expect(find.text('Đang làm - 4'), findsOneWidget);
    },
  );

  testWidgets(
    'D08b: Nhập từ khóa không dấu "THIET KE" khớp "Thiết kế màn hình đăng nhập"',
    (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      final input = find.byType(TextField);
      await tester.enterText(input, 'THIET KE');
      await tester.pumpAndSettle();

      expect(find.text('1 kết quả'), findsOneWidget);
      expect(find.text('Khớp tiêu đề - không phân biệt dấu'), findsOneWidget);
      expect(find.text('Thiết kế màn hình đăng nhập'), findsOneWidget);
      expect(find.text('Các card không khớp đã được ẩn.'), findsOneWidget);
    },
  );

  testWidgets(
    'D08c & D08d: Mở bộ lọc, chọn nhãn/người/hạn/hoàn thành, kết hợp từ khóa "màn hình"',
    (tester) async {
      await tester.pumpWidget(buildTestApp(initialKeyword: 'màn hình'));
      await tester.pumpAndSettle();

      // Nhấn nút Bộ lọc
      final filterButton = find.widgetWithText(OutlinedButton, 'Bộ lọc');
      expect(filterButton, findsOneWidget);
      await tester.tap(filterButton);
      await tester.pumpAndSettle();

      // Kiểm tra các phần trong BoardFilterSheet (D08c)
      // Chọn nhãn 'Thiết kế' (ở ngay trên đầu)
      await tester.tap(find.text('Thiết kế'));
      await tester.pumpAndSettle();

      // Chọn người được giao 'Hoàng Minh'
      await tester.tap(find.text('Hoàng Minh'));
      await tester.pumpAndSettle();

      // Cuộn xuống để chọn hạn chót và hoàn thành
      await tester.drag(find.byType(ListView), const Offset(0, -250));
      await tester.pumpAndSettle();

      expect(find.text('Hạn chót'), findsOneWidget);
      expect(find.text('Hoàn thành'), findsOneWidget);
      expect(
        find.text('Cùng loại: OR · Khác loại và từ khóa: AND'),
        findsOneWidget,
      );

      // Chọn hạn chót 'Sắp đến hạn'
      await tester.tap(find.text('Sắp đến hạn'));
      await tester.pumpAndSettle();

      // Chọn 'Chưa hoàn thành'
      await tester.tap(find.text('Chưa hoàn thành'));
      await tester.pumpAndSettle();

      // Nút đóng bộ lọc hiện "Đóng bộ lọc - 1 kết quả"
      final closeFilterButton = find.widgetWithText(
        FilledButton,
        'Đóng bộ lọc - 1 kết quả',
      );
      expect(closeFilterButton, findsOneWidget);
      await tester.tap(closeFilterButton);
      await tester.pumpAndSettle();

      // Trở về màn hình D08d: nút hiển thị "Bộ lọc - 4"
      expect(find.text('Bộ lọc - 4'), findsOneWidget);
      expect(find.text('1 kết quả'), findsOneWidget);
      expect(find.text('Thiết kế màn hình đăng nhập'), findsOneWidget);
      expect(find.text('Kết quả đã cập nhật'), findsOneWidget);
    },
  );

  testWidgets('D08e: Không tìm thấy kết quả phù hợp và nút Xóa bộ lọc', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    final input = find.byType(TextField);
    await tester.enterText(input, 'tu khoa khong ton tai');
    await tester.pumpAndSettle();

    expect(find.text('0 kết quả'), findsOneWidget);
    expect(find.text('Không tìm thấy công việc phù hợp'), findsOneWidget);
    expect(
      find.text(
        'Thử xóa bộ lọc và từ khóa để xem lại tất cả công việc trong board.',
      ),
      findsOneWidget,
    );

    // Nhấn nút Xóa bộ lọc -> quay về 7 công việc
    final clearButton = find.widgetWithText(FilledButton, 'Xóa bộ lọc');
    expect(clearButton, findsOneWidget);
    await tester.tap(clearButton);
    await tester.pumpAndSettle();

    expect(find.text('7 công việc'), findsOneWidget);
  });
}
