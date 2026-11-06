import 'dart:async';

import 'package:flutter/material.dart';

/// Báo mất kết nối Firestore khi dữ liệu board chỉ còn từ bộ nhớ đệm (UC05 8a).
///
/// Chỉ hiện khi tình trạng kéo dài quá [delay], tránh nháy lên trong lúc mở
/// board (lần đọc đầu tiên thường lấy từ bộ nhớ đệm trước).
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({
    required this.isOffline,
    this.delay = const Duration(seconds: 2),
    super.key,
  });

  final bool isOffline;
  final Duration delay;

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant OfflineBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isOffline != widget.isOffline) _sync();
  }

  void _sync() {
    _timer?.cancel();
    if (!widget.isOffline) {
      if (_visible) setState(() => _visible = false);
      return;
    }
    _timer = Timer(widget.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, color: colorScheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Mất kết nối tới Firestore. Đang hiển thị dữ liệu đã tải; thay '
              'đổi sẽ được đồng bộ khi có mạng trở lại.',
              style: TextStyle(
                color: colorScheme.onErrorContainer,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
