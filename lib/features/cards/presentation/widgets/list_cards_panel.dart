import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/card_model.dart';
import '../providers/card_providers.dart';
import '../screens/card_detail_screen.dart';
import 'add_card_composer.dart';
import 'card_actions.dart';
import 'card_drag_controller.dart';
import 'card_tile.dart';

/// Nội dung một cột list: tiêu đề cột, các thẻ và nút “Thêm thẻ”.
///
/// Cả cột là vùng thả: nhấn giữ một thẻ để kéo, thả vào cột bất kỳ để chuyển
/// list hoặc đổi thứ tự.
class ListCardsPanel extends ConsumerStatefulWidget {
  const ListCardsPanel({
    required this.boardId,
    required this.listId,
    required this.cards,
    required this.dragController,
    required this.header,
    this.isLoading = false,
    this.error,
    super.key,
  });

  final String boardId;
  final String listId;

  /// Card của list theo thứ tự hiển thị.
  final List<TaskCardModel> cards;
  final CardDragController dragController;
  final Widget header;
  final bool isLoading;
  final Object? error;

  @override
  ConsumerState<ListCardsPanel> createState() => _ListCardsPanelState();
}

class _ListCardsPanelState extends ConsumerState<ListCardsPanel> {
  final _scrollController = ScrollController();
  final _viewportKey = GlobalKey();
  final Map<String, GlobalKey> _tileKeys = {};

  static const _tileSpacing = 8.0;

  CardDragController get _drag => widget.dragController;

  @override
  void initState() {
    super.initState();
    _drag.registerColumn(widget.listId, _scrollController, _viewportKey);
  }

  @override
  void didUpdateWidget(covariant ListCardsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listId != widget.listId ||
        oldWidget.dragController != widget.dragController) {
      oldWidget.dragController.unregisterColumn(
        oldWidget.listId,
        _scrollController,
      );
      _drag.registerColumn(widget.listId, _scrollController, _viewportKey);
    }
  }

  @override
  void dispose() {
    _drag.unregisterColumn(widget.listId, _scrollController);
    _scrollController.dispose();
    super.dispose();
  }

  /// Vị trí thả (tính trên danh sách đã bỏ thẻ đang kéo) theo tâm của thẻ
  /// đang kéo, với [feedbackOffset] là góc trên trái của thẻ đó.
  int _dropIndexAt(Offset feedbackOffset) {
    final probeY = feedbackOffset.dy + _drag.cardSize.height / 2;
    var index = 0;
    for (final card in widget.cards) {
      if (card.id == _drag.card?.id) continue;
      final box = _tileKeys[card.id]?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final centerY = box.localToGlobal(box.size.center(Offset.zero)).dy;
      if (centerY >= probeY) break;
      index++;
    }
    return index;
  }

  void _drop(TaskCardModel card, int index) {
    showCardActionResult(
      ScaffoldMessenger.of(context),
      ref
          .read(cardsControllerProvider)
          .moveCard(
            boardId: widget.boardId,
            card: card,
            toListId: widget.listId,
            targetCards: widget.cards,
            index: index,
          ),
    );
  }

  void _openCard(TaskCardModel card) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            CardDetailScreen(boardId: widget.boardId, cardId: card.id),
      ),
    );
  }

  void _toggleCompleted(TaskCardModel card) {
    showCardActionResult(
      ScaffoldMessenger.of(context),
      ref
          .read(cardsControllerProvider)
          .setCompleted(
            boardId: widget.boardId,
            cardId: card.id,
            isCompleted: !card.isCompleted,
          ),
    );
  }

  void _showActions(TaskCardModel card) {
    showCardActionsSheet(
      context,
      cards: ref.read(cardsControllerProvider),
      boardId: widget.boardId,
      card: card,
      onOpen: () => _openCard(card),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<TaskCardModel>(
      onMove: (details) =>
          _drag.hover(widget.listId, _dropIndexAt(details.offset)),
      onLeave: (_) => _drag.leave(widget.listId),
      onAcceptWithDetails: (details) =>
          _drop(details.data, _dropIndexAt(details.offset)),
      builder: (context, _, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          widget.header,
          const SizedBox(height: 4),
          Expanded(
            child: ListenableBuilder(
              listenable: _drag,
              builder: (context, _) => _buildCards(context),
            ),
          ),
          const SizedBox(height: 4),
          AddCardComposer(boardId: widget.boardId, listId: widget.listId),
        ],
      ),
    );
  }

  Widget _buildCards(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (widget.error case final error? when widget.cards.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: colorScheme.error),
            const SizedBox(height: 6),
            Text(
              'Không tải được thẻ. ${describeCardError(error)}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: colorScheme.error),
            ),
            TextButton(
              onPressed: () =>
                  ref.invalidate(boardCardsProvider(widget.boardId)),
              child: const Text('Thử lại'),
            ),
          ],
        ),
      );
    }
    if (widget.isLoading && widget.cards.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final dragging = _drag.card;
    final hoverIndex = _drag.hoverListId == widget.listId
        ? _drag.hoverIndex
        : null;
    final visibleIds = widget.cards.map((card) => card.id).toSet();
    _tileKeys.removeWhere((id, _) => !visibleIds.contains(id));

    final children = <Widget>[];
    var index = 0;
    for (final card in widget.cards) {
      if (card.id == dragging?.id) {
        // Giữ widget nguồn trong cây để thao tác kéo không bị hủy giữa chừng.
        children.add(_buildDraggableTile(card, isDragging: true));
        continue;
      }
      if (hoverIndex == index) children.add(_buildPlaceholder(colorScheme));
      children.add(_buildDraggableTile(card));
      index++;
    }
    if (hoverIndex != null && hoverIndex >= index) {
      children.add(_buildPlaceholder(colorScheme));
    }

    if (children.isEmpty) {
      return Center(
        child: Text(
          'Chưa có thẻ nào',
          style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    return SingleChildScrollView(
      key: _viewportKey,
      controller: _scrollController,
      padding: const EdgeInsets.only(top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _buildPlaceholder(ColorScheme colorScheme) {
    return Padding(
      key: const ValueKey('card-drop-placeholder'),
      padding: const EdgeInsets.only(bottom: _tileSpacing),
      child: Container(
        height: _drag.cardSize.height,
        decoration: BoxDecoration(
          color: colorScheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.5)),
        ),
      ),
    );
  }

  Widget _buildDraggableTile(TaskCardModel card, {bool isDragging = false}) {
    final tileKey = _tileKeys.putIfAbsent(card.id, GlobalKey.new);
    final tile = CardTile(
      boardId: widget.boardId,
      card: card,
      onTap: () => _openCard(card),
      onToggleCompleted: () => _toggleCompleted(card),
      onMore: () => _showActions(card),
    );

    return Padding(
      key: ValueKey(card.id),
      padding: EdgeInsets.only(bottom: isDragging ? 0 : _tileSpacing),
      child: LayoutBuilder(
        builder: (context, constraints) => LongPressDraggable<TaskCardModel>(
          key: tileKey,
          data: card,
          hapticFeedbackOnStart: true,
          dragAnchorStrategy: childDragAnchorStrategy,
          feedback: SizedBox(
            width: constraints.maxWidth,
            child: Transform.rotate(
              angle: 0.03,
              child: CardTile(
                boardId: widget.boardId,
                card: card,
                elevated: true,
              ),
            ),
          ),
          childWhenDragging: const SizedBox.shrink(),
          onDragStarted: () {
            final box = tileKey.currentContext?.findRenderObject();
            _drag.start(
              card,
              box is RenderBox && box.hasSize
                  ? box.size
                  : Size(constraints.maxWidth, 64),
            );
          },
          onDragUpdate: (details) =>
              _drag.updatePointer(details.globalPosition),
          onDragEnd: (_) => _drag.end(),
          onDraggableCanceled: (_, _) => _drag.end(),
          child: tile,
        ),
      ),
    );
  }
}
