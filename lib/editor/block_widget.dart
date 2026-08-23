import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/entry.dart';

typedef BlockResizeUpdate = void Function(
  Offset globalPosition,
  Offset globalDelta,
);

class BlockWidget extends StatefulWidget {
  const BlockWidget({
    super.key,
    required this.block,
    required this.selected,
    required this.editing,
    required this.textEditing,
    required this.onTap,
    required this.onEditText,
    required this.onMoveStart,
    required this.onMoveUpdate,
    required this.onMoveEnd,
    required this.onResize,
    required this.onRotate,
    required this.onTextChanged,
    this.preserveAspectRatio = false,
    this.imageBytes,
    this.imageProvider,
    this.onOpenImage,
  });

  final ContentBlock block;
  final bool selected;
  final bool editing;
  final bool textEditing;
  final VoidCallback onTap;
  final VoidCallback onEditText;
  final ValueChanged<Offset> onMoveStart;
  final ValueChanged<Offset> onMoveUpdate;
  final VoidCallback onMoveEnd;
  final BlockResizeUpdate onResize;
  final ValueChanged<double> onRotate;
  final ValueChanged<String> onTextChanged;
  final bool preserveAspectRatio;
  final Uint8List? imageBytes;
  final ImageProvider<Object>? imageProvider;
  final VoidCallback? onOpenImage;

  @override
  State<BlockWidget> createState() => _BlockWidgetState();
}

class _BlockWidgetState extends State<BlockWidget> {
  late final TextEditingController _controller;
  bool _resizing = false;
  bool _movingEdge = false;
  bool _movingBody = false;
  bool _rotating = false;
  Offset? _panDownGlobalPosition;
  int? _moveEdgePointer;
  final Map<int, Offset> _pointers = {};
  double? _lastPointerAngle;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.block.text);
  }

  @override
  void didUpdateWidget(covariant BlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block.text != widget.block.text &&
        _controller.text != widget.block.text) {
      _controller.value = TextEditingValue(
        text: widget.block.text,
        selection: TextSelection.collapsed(offset: widget.block.text.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = _isVisualBlock
        ? (widget.imageProvider == null && widget.imageBytes == null
              ? const Center(child: Icon(Icons.broken_image_outlined))
              : Image(
                  image:
                      widget.imageProvider ?? MemoryImage(widget.imageBytes!),
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stackTrace) =>
                      const Center(child: Icon(Icons.broken_image_outlined)),
                ))
        : widget.editing && widget.selected && widget.textEditing
        ? TextField(
            key: ValueKey('block-text-${widget.block.id}'),
            controller: _controller,
            autofocus: true,
            maxLines: null,
            expands: true,
            onChanged: widget.onTextChanged,
            style: _textStyle(context),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(8),
            ),
          )
        : Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                widget.block.text.isEmpty ? 'Write here...' : widget.block.text,
                style: _textStyle(context),
              ),
            ),
          );

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: widget.editing ? _handlePointerDown : null,
      onPointerMove: widget.editing ? _handlePointerMove : null,
      onPointerUp: widget.editing ? _handlePointerUp : null,
      onPointerCancel: widget.editing ? _handlePointerUp : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.editing ? widget.onTap : widget.onOpenImage,
        onDoubleTap: widget.editing ? widget.onEditText : null,
        onPanDown: widget.editing
            ? (details) => _panDownGlobalPosition = details.globalPosition
            : null,
        onPanStart: widget.editing
            ? (details) {
                final size = context.size ?? Size.zero;
                final inResizeCorner =
                    details.localPosition.dx >= size.width - 56 &&
                    details.localPosition.dy >= size.height - 56;
                _resizing = inResizeCorner;
                _movingEdge =
                    !inResizeCorner &&
                    (details.localPosition.dx <= 20 ||
                        details.localPosition.dy <= 20 ||
                        details.localPosition.dx >= size.width - 20 ||
                        details.localPosition.dy >= size.height - 20);
                widget.onTap();
                _movingBody =
                    _moveEdgePointer == null &&
                    !_resizing &&
                    !_movingEdge &&
                    !_rotating;
                if (_movingBody) {
                  widget.onMoveStart(
                    _panDownGlobalPosition ?? details.globalPosition,
                  );
                  widget.onMoveUpdate(details.globalPosition);
                }
              }
            : null,
        onPanUpdate: widget.editing
            ? (details) {
                if (_rotating) return;
                if (_resizing) {
                  widget.onResize(details.globalPosition, details.delta);
                } else if (_movingBody) {
                  widget.onMoveUpdate(details.globalPosition);
                }
              }
            : null,
        onPanEnd: widget.editing ? (_) => _finishBodyGesture() : null,
        onPanCancel: widget.editing ? _finishBodyGesture : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: widget.selected
                ? Border.all(color: const Color(0xFFC97068), width: 2.5)
                : null,
            boxShadow: widget.selected
                ? [
                    BoxShadow(
                      color: const Color(0xFF3B3226).withValues(alpha: 0.14),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              content,
              if (widget.editing && widget.selected)
                Positioned(
                  left: 0,
                  top: 0,
                  right: 0,
                  height: 20,
                  child: _buildMoveEdge(
                    key: ValueKey('move-${widget.block.id}'),
                  ),
                ),
              if (widget.editing && widget.selected)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 20,
                  child: _buildMoveEdge(),
                ),
              if (widget.editing && widget.selected)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 20,
                  child: _buildMoveEdge(),
                ),
              if (widget.editing && widget.selected)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 20,
                  child: _buildMoveEdge(),
                ),
              if (widget.editing && widget.selected)
                Positioned(
                  right: -12,
                  bottom: -12,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerMove: (event) =>
                        widget.onResize(event.position, event.delta),
                    child: Container(
                      key: ValueKey('resize-${widget.block.id}'),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFC97068),
                          width: 3,
                        ),
                      ),
                      child: const Icon(
                        Icons.open_in_full,
                        size: 20,
                        color: Color(0xFFC97068),
                      ),
                    ),
                  ),
                ),
              if (widget.editing &&
                  widget.selected &&
                  (widget.block.type == BlockType.text || _isVisualBlock))
                Positioned(
                  top: -48,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      key: ValueKey('rotate-${widget.block.id}'),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B3226),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: (details) =>
                            widget.onRotate(details.delta.dx / 100),
                        child: const Icon(
                          Icons.rotate_right,
                          size: 23,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle _textStyle(BuildContext context) =>
      (Theme.of(context).textTheme.bodyLarge ?? const TextStyle()).copyWith(
        fontSize: widget.block.fontSize,
        fontFamily: widget.block.fontFamily,
        fontWeight: widget.block.bold ? FontWeight.bold : FontWeight.normal,
        fontStyle: widget.block.italic ? FontStyle.italic : FontStyle.normal,
      );

  void _handlePointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 2 &&
        widget.selected &&
        (widget.block.type == BlockType.text || _isVisualBlock)) {
      if (_movingBody || _moveEdgePointer != null) {
        widget.onMoveEnd();
      }
      _rotating = true;
      _lastPointerAngle = _pointerAngle;
      _resizing = false;
      _movingEdge = false;
      _movingBody = false;
      _moveEdgePointer = null;
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;
    if (!_rotating || _pointers.length < 2) return;
    final angle = _pointerAngle;
    final previous = _lastPointerAngle;
    if (angle == null || previous == null) return;
    var delta = angle - previous;
    if (delta > math.pi) delta -= math.pi * 2;
    if (delta < -math.pi) delta += math.pi * 2;
    widget.onRotate(delta);
    _lastPointerAngle = angle;
  }

  void _handlePointerUp(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.length < 2) {
      _rotating = false;
      _lastPointerAngle = null;
    }
  }

  double? get _pointerAngle {
    if (_pointers.length < 2) return null;
    final points = _pointers.values.toList();
    final delta = points[1] - points[0];
    return math.atan2(delta.dy, delta.dx);
  }

  Widget _buildMoveEdge({Key? key}) {
    return Listener(
      key: key,
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (_moveEdgePointer != null) return;
        _moveEdgePointer = event.pointer;
        widget.onTap();
        widget.onMoveStart(event.position);
      },
      onPointerMove: (event) {
        if (_moveEdgePointer == event.pointer && !_rotating) {
          widget.onMoveUpdate(event.position);
        }
      },
      onPointerUp: _finishEdgeGesture,
      onPointerCancel: _finishEdgeGesture,
    );
  }

  void _finishBodyGesture() {
    if (_movingBody) widget.onMoveEnd();
    _resizing = false;
    _movingEdge = false;
    _movingBody = false;
    _panDownGlobalPosition = null;
  }

  void _finishEdgeGesture(PointerEvent event) {
    if (_moveEdgePointer != event.pointer) return;
    _moveEdgePointer = null;
    widget.onMoveEnd();
  }

  bool get _isVisualBlock =>
      widget.block.type == BlockType.image ||
      widget.block.type == BlockType.sticker;
}
