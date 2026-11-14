import 'package:flutter_test/flutter_test.dart';
import 'package:smart_todo/features/collaboration/domain/collaboration_rules.dart';

void main() {
  group('validateInviteEmail (UC06 bước 4, 4a)', () {
    test('chấp nhận email hợp lệ, bỏ qua khoảng trắng hai đầu', () {
      expect(validateInviteEmail('ban@example.com'), isNull);
      expect(validateInviteEmail('  Ban.Hoc@Sv.HAUI.edu.vn  '), isNull);
    });

    test('báo lỗi khi trống hoặc sai định dạng', () {
      expect(validateInviteEmail(''), 'Hãy nhập email người được mời.');
      expect(validateInviteEmail('   '), 'Hãy nhập email người được mời.');
      for (final email in [
        'ban',
        'ban@',
        '@example.com',
        'ban@example',
        'ban an@example.com',
        'ban@@example.com',
      ]) {
        expect(
          validateInviteEmail(email),
          'Email không đúng định dạng.',
          reason: email,
        );
      }
    });

    test('báo lỗi khi dài hơn 254 ký tự', () {
      final local = 'a' * 242; // 242 + '@example.com' = 254 ký tự
      expect(validateInviteEmail('$local@example.com'), isNull);
      expect(
        validateInviteEmail('a$local@example.com'),
        'Email không đúng định dạng.',
      );
    });
  });

  test('normalizeEmail bỏ khoảng trắng và viết thường (Q9)', () {
    expect(normalizeEmail('  Ban@Example.COM '), 'ban@example.com');
  });

  group('validateCommentBody (UC06 1d)', () {
    test('nhận 1 đến 2000 ký tự sau khi bỏ khoảng trắng', () {
      expect(validateCommentBody('a'), isNull);
      expect(validateCommentBody('a' * 2000), isNull);
      expect(validateCommentBody('  ${'a' * 2000}  '), isNull);
    });

    test('báo lỗi khi trống hoặc quá 2000 ký tự', () {
      expect(
        validateCommentBody('  \n '),
        'Nội dung bình luận không được để trống.',
      );
      expect(validateCommentBody('a' * 2001), 'Bình luận tối đa 2000 ký tự.');
    });

    test('normalizeCommentBody làm sạch hoặc ném ArgumentError', () {
      expect(normalizeCommentBody('  Xin chào  '), 'Xin chào');
      expect(() => normalizeCommentBody(''), throwsArgumentError);
    });
  });

  test('displayNameFor dùng tên, rồi email, và cắt còn 100 ký tự', () {
    expect(displayNameFor(displayName: ' An ', email: 'an@x.com'), 'An');
    expect(displayNameFor(displayName: '', email: 'an@x.com'), 'an@x.com');
    expect(displayNameFor(displayName: null, email: null), 'Thành viên');
    expect(displayNameFor(displayName: 'a' * 150).length, 100);
  });
}
