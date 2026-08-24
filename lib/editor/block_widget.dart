import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/entry.dart';

class BlockWidget extends StatefulWidget {
  const BlockWidget({
    super.key,
    required this.block,
    required this.selected,
    required this.editing,
    this.locked = false,
    required this.textEditing,
    required this.onTap,
    required this.onEditText,
    required this.onMoveStart,
    required this.onMoveUpdate,
    required this.onMoveEnd,
    required this.onRotate,
    this.onTransformStart,
    this.onTransformEnd,
    required this.onTextChanged,
    this.preserveAspectRatio = false,
    this.imageBytes,
    this.imageProvider,
    this.onOpenImage,
  });

  final ContentBlock block;
  final bool selected;
  final bool editing;
  final bool locked;
  final bool textEditing;
  final VoidCallback onTap;
  final VoidCallback onEditText;
  final ValueChanged<Offset> onMoveStart;
  final ValueChanged<Offset> onMoveUpdate;
  final VoidCallback onMoveEnd;
  final ValueChanged<double> onRotate;
  final VoidCallback? onTransformStart;
  final VoidCallback? onTransformEnd;
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
  late final FocusNode _textFocusNode;
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
    _textFocusNode = FocusNode();
    if (widget.textEditing) _scheduleTextFocus();
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
    if (!oldWidget.textEditing && widget.textEditing) {
      _scheduleTextFocus();
    } else if (oldWidget.textEditing && !widget.textEditing) {
      _textFocusNode.unfocus();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.block.type == BlockType.shape
        ? CustomPaint(
            painter: _ShapePainter(widget.block),
            child: const SizedBox.expand(),
          )
        : widget.block.type == BlockType.ink
        ? CustomPaint(
            painter: _InkPainter(widget.block),
            child: const SizedBox.expand(),
          )
        : _isVisualBlock
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
        : widget.editing &&
              !widget.locked &&
              widget.selected &&
              widget.textEditing
        ? TextField(
            key: ValueKey('block-text-${widget.block.id}'),
            controller: _controller,
            focusNode: _textFocusNode,
            maxLines: null,
            expands: true,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
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
      onPointerDown: widget.editing && !widget.locked
          ? _handlePointerDown
          : null,
      onPointerMove: widget.editing && !widget.locked
          ? _handlePointerMove
          : null,
      onPointerUp: widget.editing && !widget.locked ? _handlePointerUp : null,
      onPointerCancel: widget.editing && !widget.locked
          ? _handlePointerUp
          : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.editing
            ? () {
                widget.onTap();
                if (widget.block.type == BlockType.text && !widget.locked) {
                  widget.onEditText();
                }
              }
            : widget.onOpenImage,
        onPanDown: widget.editing && !widget.locked
            ? (details) => _panDownGlobalPosition = details.globalPosition
            : null,
        onPanStart: widget.editing && !widget.locked
            ? (details) {
                final size = context.size ?? Size.zero;
                _movingEdge =
                    details.localPosition.dx <= 20 ||
                    details.localPosition.dy <= 20 ||
                    details.localPosition.dx >= size.width - 20 ||
                    details.localPosition.dy >= size.height - 20;
                widget.onTap();
                _movingBody =
                    _moveEdgePointer == null && !_movingEdge && !_rotating;
                if (_movingBody) {
                  widget.onMoveStart(
                    _panDownGlobalPosition ?? details.globalPosition,
                  );
                  widget.onMoveUpdate(details.globalPosition);
                }
              }
            : null,
        onPanUpdate: widget.editing && !widget.locked
            ? (details) {
                if (_rotating) return;
                if (_movingBody) {
                  widget.onMoveUpdate(details.globalPosition);
                }
              }
            : null,
        onPanEnd: widget.editing && !widget.locked
            ? (_) => _finishBodyGesture()
            : null,
        onPanCancel: widget.editing && !widget.locked
            ? _finishBodyGesture
            : null,
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
              if (widget.editing && !widget.locked && widget.selected)
                Positioned(
                  left: 0,
                  top: 0,
                  right: 0,
                  height: 20,
                  child: _buildMoveEdge(
                    key: ValueKey('move-${widget.block.id}'),
                  ),
                ),
              if (widget.editing && !widget.locked && widget.selected)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 20,
                  child: _buildMoveEdge(),
                ),
              if (widget.editing && !widget.locked && widget.selected)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 20,
                  child: _buildMoveEdge(),
                ),
              if (widget.editing && !widget.locked && widget.selected)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 20,
                  child: _buildMoveEdge(),
                ),
              if (widget.editing &&
                  !widget.locked &&
                  widget.selected &&
                  _isTransformable)
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
                        onPanStart: (_) => widget.onTransformStart?.call(),
                        onPanUpdate: (details) =>
                            widget.onRotate(details.delta.dx / 100),
                        onPanEnd: (_) => widget.onTransformEnd?.call(),
                        onPanCancel: () => widget.onTransformEnd?.call(),
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
        color: widget.block.textColorValue == null
            ? null
            : Color(widget.block.textColorValue!),
        fontWeight: widget.block.bold ? FontWeight.bold : FontWeight.normal,
        fontStyle: widget.block.italic ? FontStyle.italic : FontStyle.normal,
      );

  void _scheduleTextFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.editing || !widget.textEditing) return;
      _textFocusNode.requestFocus();
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    });
  }

  void _handlePointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 2 && widget.selected && _isTransformable) {
      if (_movingBody || _moveEdgePointer != null) {
        widget.onMoveEnd();
      }
      _rotating = true;
      widget.onTransformStart?.call();
      _lastPointerAngle = _pointerAngle;
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
      if (_rotating) widget.onTransformEnd?.call();
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

  bool get _isTransformable => widget.block.type != BlockType.group;
}

class _ShapePainter extends CustomPainter {
  const _ShapePainter(this.block);

  final ContentBlock block;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = block.strokeWidth.clamp(0.5, 20).toDouble()
      ..color = Color(block.strokeColorValue ?? 0xFF3B3226);
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = Color(block.fillColorValue ?? 0x00000000);
    final rect = Offset.zero & size;
    switch (block.shape) {
      case 'ellipse':
        canvas.drawOval(rect, fill);
        canvas.drawOval(rect.deflate(stroke.strokeWidth / 2), stroke);
      case 'line':
        canvas.drawLine(Offset.zero, Offset(size.width, size.height), stroke);
      case 'arrow':
        final end = Offset(size.width, size.height);
        canvas.drawLine(Offset.zero, end, stroke);
        final angle = math.atan2(size.height, size.width);
        const head = 12.0;
        canvas.drawLine(
          end,
          end -
              Offset(
                math.cos(angle - 0.55) * head,
                math.sin(angle - 0.55) * head,
              ),
          stroke,
        );
        canvas.drawLine(
          end,
          end -
              Offset(
                math.cos(angle + 0.55) * head,
                math.sin(angle + 0.55) * head,
              ),
          stroke,
        );
      default:
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(8)),
          fill,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            rect.deflate(stroke.strokeWidth / 2),
            const Radius.circular(8),
          ),
          stroke,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _ShapePainter oldDelegate) =>
      oldDelegate.block.toJson().toString() != block.toJson().toString();
}

class _InkPainter extends CustomPainter {
  const _InkPainter(this.block);

  final ContentBlock block;

  @override
  void paint(Canvas canvas, Size size) {
    final points = block.inkPoints ?? const <Map<String, dynamic>>[];
    if (points.length < 2 || block.w <= 0 || block.h <= 0) return;
    final path = Path();
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      final offset = Offset(
        ((point['x'] as num?)?.toDouble() ?? 0) * size.width / block.w,
        ((point['y'] as num?)?.toDouble() ?? 0) * size.height / block.h,
      );
      if (index == 0) {
        path.moveTo(offset.dx, offset.dy);
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = block.strokeWidth.clamp(0.5, 20).toDouble()
        ..color = Color(block.strokeColorValue ?? 0xFF3B3226),
    );
  }

  @override
  bool shouldRepaint(covariant _InkPainter oldDelegate) =>
      oldDelegate.block.toJson().toString() != block.toJson().toString();
}
