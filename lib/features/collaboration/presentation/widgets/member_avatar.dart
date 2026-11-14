import 'package:flutter/material.dart';

/// Màu cố định theo uid để mỗi người luôn có cùng một màu (cùng công thức với
/// avatar người được giao trên thẻ).
Color memberAvatarColor(String uid) {
  final hash = uid.codeUnits.fold<int>(0, (sum, unit) => sum + unit);
  return Colors.primaries[hash % Colors.primaries.length].shade400;
}

/// Chữ cái đầu của tên gọi (từ cuối trong họ tên tiếng Việt).
String memberInitial(String name, {String fallback = ''}) {
  final words = name.trim().split(RegExp(r'\s+'));
  final word = words.isEmpty || words.last.isEmpty
      ? fallback.trim()
      : words.last;
  return word.isEmpty
      ? '?'
      : String.fromCharCode(word.runes.first).toUpperCase();
}

/// Avatar tròn hiển thị chữ cái đầu của một thành viên.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    required this.uid,
    required this.name,
    this.email = '',
    this.radius = 18,
    super.key,
  });

  final String uid;
  final String name;
  final String email;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: memberAvatarColor(uid),
      child: Text(
        memberInitial(name, fallback: email),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.85,
        ),
      ),
    );
  }
}
