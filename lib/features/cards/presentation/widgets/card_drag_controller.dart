import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../data/card_model.dart';

/// Trạng thái kéo thả card dùng chung cho mọi cột của một board.
///
/// Giữ card đang kéo và chỗ sẽ thả (list + vị trí) để các cột vẽ ô giữ chỗ,
/// đồng thời tự cuộn board/cột khi người dùng kéo card tới gần mép.
class CardDragController extends ChangeNotifier {
  TaskCardModel? _card;
  Size _cardSize = Size.zero;
  String? _hoverListId;
  int? _hoverIndex;

  TaskCardModel? get card => _card;

  /// Kích thước thẻ đang kéo, dùng cho ô giữ chỗ.
  Size get cardSize => _cardSize;
  String? get hoverListId => _hoverListId;
  int? get hoverIndex => _hoverIndex;
  bool get isDragging => _card != null;

  void start(TaskCardModel card, Size size) {
    _card = card;
    _cardSize = size;
    notifyListeners();
  }

  void hover(String listId, int index) {
    if (_hoverListId == listId && _hoverIndex == index) return;
    _hoverListId = listId;
    _hoverIndex = index;
    notifyListeners();
  }

  void leave(String listId) {
    if (_hoverListId != listId) return;
    _hoverListId = null;
    _hoverIndex = null;
    notifyListeners();
  }

  void end() {
    _stopAutoScroll();
    if (_card == null && _hoverListId == null) return;
    _card = null;
    _hoverListId = null;
    _hoverIndex = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Tự cuộn khi kéo tới mép
  // ---------------------------------------------------------------------------

  static const _edgeSize = 56.0;
  static const _maxStep = 14.0;

  ScrollController? _boardScroll;
  GlobalKey? _boardViewport;
  final Map<String, (ScrollController, GlobalKey)> _columns = {};
  Offset? _pointer;
  Timer? _ticker;

  /// Thanh cuộn ngang chứa các cột list.
  void attachBoard(ScrollController controller, GlobalKey viewport) {
    _boardScroll = controller;
    _boardViewport = viewport;
  }

  /// Vùng cuộn dọc chứa các card của một cột.
  void registerColumn(
    String listId,
    ScrollController controller,
    GlobalKey viewport,
  ) {
    _columns[listId] = (controller, viewport);
  }

  void unregisterColumn(String listId, ScrollController controller) {
    if (_columns[listId]?.$1 == controller) _columns.remove(listId);
  }

  /// Gọi mỗi khi ngón tay di chuyển trong lúc kéo (tọa độ toàn màn hình).
  void updatePointer(Offset globalPosition) {
    _pointer = globalPosition;
    _ticker ??= Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _autoScrollTick(),
    );
  }

  void _autoScrollTick() {
    final pointer = _pointer;
    if (pointer == null || !isDragging) {
      _stopAutoScroll();
      return;
    }
    var scrolled = _scrollNearEdge(
      _boardScroll,
      _boardViewport,
      pointer,
      Axis.horizontal,
    );
    for (final (controller, viewport) in _columns.values) {
      scrolled |= _scrollNearEdge(controller, viewport, pointer, Axis.vertical);
    }
    // Dừng khi không còn ở mép; lần di chuyển tiếp theo sẽ bật lại.
    if (!scrolled) _stopAutoScroll();
  }

  bool _scrollNearEdge(
    ScrollController? controller,
    GlobalKey? viewport,
    Offset pointer,
    Axis axis,
  ) {
    if (controller == null || !controller.hasClients) return false;
    final box = viewport?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return false;

    final rect = box.localToGlobal(Offset.zero) & box.size;
    final horizontal = axis == Axis.horizontal;
    // Chỉ cuộn vùng mà ngón tay đang nằm trong theo chiều còn lại.
    final crossInside = horizontal
        ? pointer.dy >= rect.top && pointer.dy <= rect.bottom
        : pointer.dx >= rect.left && pointer.dx <= rect.right;
    if (!crossInside) return false;

    final start = horizontal ? rect.left : rect.top;
    final end = horizontal ? rect.right : rect.bottom;
    final position = horizontal ? pointer.dx : pointer.dy;

    var delta = 0.0;
    if (position < start + _edgeSize) {
      delta =
          -_maxStep * (1 - (position - start).clamp(0, _edgeSize) / _edgeSize);
    } else if (position > end - _edgeSize) {
      delta = _maxStep * (1 - (end - position).clamp(0, _edgeSize) / _edgeSize);
    }
    if (delta == 0) return false;

    final metrics = controller.position;
    final target = (controller.offset + delta).clamp(
      metrics.minScrollExtent,
      metrics.maxScrollExtent,
    );
    if (target == controller.offset) return false;
    controller.jumpTo(target);
    return true;
  }

  void _stopAutoScroll() {
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  void dispose() {
    _stopAutoScroll();
    super.dispose();
  }
}
