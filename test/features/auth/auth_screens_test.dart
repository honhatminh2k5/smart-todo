import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_todo/features/auth/data/auth_repository.dart';
import 'package:smart_todo/features/auth/presentation/auth_screens.dart';

void main() {
  Widget buildSignInScreen() {
    // AuthRepository chỉ được gọi khi biểu mẫu hợp lệ. Các test này cố ý
    // nhập dữ liệu không hợp lệ nên không cần cấu hình Firebase.
    return MaterialApp(
      home: SignInScreen(
        auth: AuthRepository(),
        firebaseSetupMessage: null,
      ),
    );
  }

  Future<void> tapWhenVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> enterField(
    WidgetTester tester,
    Finder fields,
    int index,
    String value,
  ) async {
    final field = fields.at(index);
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, value);
  }

  Future<void> openRegistration(WidgetTester tester) async {
    // Liên kết đăng ký nằm gần cuối trang đăng nhập, có thể ở ngoài viewport.
    await tapWhenVisible(tester, find.text('Đăng ký tài khoản'));
  }

  Future<void> submitRegistration(WidgetTester tester) async {
    await tapWhenVisible(
      tester,
      find.widgetWithText(FilledButton, 'Đăng ký'),
    );
  }

  group('UC02 - Đăng nhập', () {
    testWidgets('không cho gửi biểu mẫu khi email và mật khẩu để trống', (
      tester,
    ) async {
      await tester.pumpWidget(buildSignInScreen());

      await tapWhenVisible(
        tester,
        find.widgetWithText(FilledButton, 'Đăng nhập'),
      );

      expect(find.text('Vui lòng nhập email.'), findsOneWidget);
      expect(find.text('Vui lòng nhập mật khẩu.'), findsOneWidget);
    });

    testWidgets('báo lỗi khi email sai định dạng', (tester) async {
      await tester.pumpWidget(buildSignInScreen());

      final fields = find.byType(TextFormField);
      await enterField(tester, fields, 0, 'email-khong-hop-le');
      await enterField(tester, fields, 1, 'MatKhau123');
      await tapWhenVisible(
        tester,
        find.widgetWithText(FilledButton, 'Đăng nhập'),
      );

      expect(find.text('Email không đúng định dạng.'), findsOneWidget);
    });
  });

  group('UC01 - Đăng ký', () {
    testWidgets('không cho đăng ký khi bỏ trống các trường bắt buộc', (
      tester,
    ) async {
      await tester.pumpWidget(buildSignInScreen());
      await openRegistration(tester);
      await submitRegistration(tester);

      expect(find.text('Vui lòng nhập họ tên.'), findsOneWidget);
      expect(find.text('Vui lòng nhập email.'), findsOneWidget);
      expect(find.text('Mật khẩu phải có tối thiểu 8 ký tự.'), findsOneWidget);
    });

    testWidgets('từ chối email sai định dạng', (tester) async {
      await tester.pumpWidget(buildSignInScreen());
      await openRegistration(tester);

      final fields = find.byType(TextFormField);
      await enterField(tester, fields, 0, 'Nguyen Van A');
      await enterField(tester, fields, 1, 'email-sai');
      await enterField(tester, fields, 2, 'MatKhau123');
      await enterField(tester, fields, 3, 'MatKhau123');
      await submitRegistration(tester);

      expect(find.text('Email không đúng định dạng.'), findsOneWidget);
    });

    testWidgets('từ chối mật khẩu ngắn hơn 8 ký tự', (tester) async {
      await tester.pumpWidget(buildSignInScreen());
      await openRegistration(tester);

      final fields = find.byType(TextFormField);
      await enterField(tester, fields, 0, 'Nguyen Van A');
      await enterField(tester, fields, 1, 'a@example.com');
      await enterField(tester, fields, 2, '1234567');
      await enterField(tester, fields, 3, '1234567');
      await submitRegistration(tester);

      expect(find.text('Mật khẩu phải có tối thiểu 8 ký tự.'), findsOneWidget);
    });

    testWidgets('từ chối khi mật khẩu xác nhận không trùng khớp', (
      tester,
    ) async {
      await tester.pumpWidget(buildSignInScreen());
      await openRegistration(tester);

      final fields = find.byType(TextFormField);
      await enterField(tester, fields, 0, 'Nguyen Van A');
      await enterField(tester, fields, 1, 'a@example.com');
      await enterField(tester, fields, 2, 'MatKhau123');
      await enterField(tester, fields, 3, 'MatKhau456');
      await submitRegistration(tester);

      expect(find.text('Mật khẩu xác nhận không khớp.'), findsOneWidget);
    });
  });
}
