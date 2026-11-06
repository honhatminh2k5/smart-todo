// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:smart_todo/main.dart';

void main() {
  testWidgets('shows the Smart Todo sign-in screen in preview mode', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const SmartTodoApp(
        firebaseSetupMessage: 'Chế độ xem trước, chưa cấu hình Firebase.',
      ),
    );

    expect(find.text('Smart Todo'), findsOneWidget);
    expect(find.text('Đăng nhập'), findsOneWidget);
    expect(find.text('Quên mật khẩu?'), findsOneWidget);
    expect(find.text('Đăng ký tài khoản'), findsOneWidget);
  });
}
