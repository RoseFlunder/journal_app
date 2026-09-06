import 'dart:math' as math;

import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../models/document.dart';
import 'ink_stroke_renderer.dart';

class BlockWidget extends StatefulWidget {
  const BlockWidget({
    super.key,
    required this.block,
    required this.selected,
    required this.editing,
    this.locked = false,
    this.controlScale = 1,
    required this.textEditing,
    required this.onTap,
    this.onSelectionRequested,
    required this.onEditText,
    required this.onMoveStart,
    required this.onMoveUpdate,
    required this.onMoveEnd,
    required this.onRotate,
    this.onTransformStart,
    this.onTransformEnd,
    this.showRotateHandle = true,
    required this.onTextChanged,
    this.onRichTextChanged,
    this.preserveAspectRatio = false,
    this.imageBytes,
    this.imageProvider,
    this.onOpenImage,
    this.onEditImage,
  });

  final CanvasRenderable block;
  final bool selected;
  final bool editing;
  final bool locked;
  final double controlScale;
  final bool textEditing;
  final VoidCallback onTap;
  final void Function(PointerDeviceKind kind, {required bool pointerDown})?
  onSelectionRequested;
  final VoidCallback onEditText;
  final ValueChanged<Offset> onMoveStart;
  final ValueChanged<Offset> onMoveUpdate;
  final VoidCallback onMoveEnd;
  final ValueChanged<double> onRotate;
  final VoidCallback? onTransformStart;
  final VoidCallback? onTransformEnd;
  final bool showRotateHandle;
  final ValueChanged<String> onTextChanged;
  final void Function(String text, List<dynamic> delta)? onRichTextChanged;
  final bool preserveAspectRatio;
  final Uint8List? imageBytes;
  final ImageProvider<Object>? imageProvider;
  final VoidCallback? onOpenImage;
  final VoidCallback? onEditImage;

  @override
  State<BlockWidget> createState() => _BlockWidgetState();
}

class _BlockWidgetState extends State<BlockWidget> {
  late final TextEditingController _controller;
  late final FocusNode _textFocusNode;
  late final FocusNode _richFocusNode;
  QuillController? _quillController;
  String? _lastQuillDelta;
  bool _movingEdge = false;
  bool _movingBody = false;
  Offset? _panDownGlobalPosition;
  int? _moveEdgePointer;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.block.text);
    _textFocusNode = FocusNode();
    _richFocusNode = FocusNode();
    _createQuillController();
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
    if (_quillController == null &&
        widget.block.richTextDelta != null &&
        widget.textEditing &&
        !oldWidget.textEditing) {
      _createQuillController();
    }
    _quillController?.readOnly = !widget.textEditing;
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
    _quillController?.removeListener(_handleQuillChanged);
    _quillController?.dispose();
    _richFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controlSize = 48 / math.max(widget.controlScale, 0.01);
    final controlBorder = 2.5 / math.max(widget.controlScale, 0.01);
    final content = widget.block.isOpaque
        ? const Center(child: Icon(Icons.help_outline, semanticLabel: 'Unsupported content'))
        : widget.block.type == BlockType.shape
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
        ? _buildVisualContent()
        : widget.editing &&
              !widget.locked &&
              widget.selected &&
              widget.textEditing
        ? _buildTextEditor()
        : _quillController != null
        ? _buildTextEditor()
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

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: widget.editing
          ? (details) => _requestSelection(details.kind)
          : widget.onOpenImage == null
          ? null
          : (_) => widget.onOpenImage!(),
      onDoubleTap: widget.editing
          ? () {
              if (widget.locked) return;
              if (widget.block.type == BlockType.text) {
                widget.onEditText();
              } else if (_isVisualBlock) {
                widget.onEditImage?.call();
              }
            }
          : null,
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
              _requestSelection(details.kind);
              _movingBody = _moveEdgePointer == null && !_movingEdge;
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
              if (_movingBody) {
                widget.onMoveUpdate(details.globalPosition);
              }
            }
          : null,
      onPanEnd: widget.editing && !widget.locked
          ? (_) => _finishBodyGesture()
          : null,
      onPanCancel: widget.editing && !widget.locked ? _finishBodyGesture : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: widget.selected
              ? Border.all(color: const Color(0xFFC97068), width: controlBorder)
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
                child: _buildMoveEdge(key: ValueKey('move-${widget.block.id}')),
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
                _isTransformable &&
                widget.showRotateHandle)
              Positioned(
                top: -48,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    key: ValueKey('rotate-${widget.block.id}'),
                    width: controlSize,
                    height: controlSize,
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
                      child: Icon(
                        Icons.rotate_right,
                        size: controlSize * 0.48,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
          ],
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

  Widget _buildVisualContent() {
    if (widget.imageProvider == null && widget.imageBytes == null) {
      return const Center(child: Icon(Icons.broken_image_outlined));
    }
    final image = Image(
      image: widget.imageProvider ?? MemoryImage(widget.imageBytes!),
      fit: widget.block.crop == null ? BoxFit.contain : BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) =>
          const Center(child: Icon(Icons.broken_image_outlined)),
    );
    final crop = widget.block.crop;
    Widget visual = crop == null
        ? image
        : Transform(
            alignment: Alignment(
              (crop.center.dx * 2) - 1,
              (crop.center.dy * 2) - 1,
            ),
            transform: Matrix4.diagonal3Values(
              1 / math.max(crop.width, 0.01),
              1 / math.max(crop.height, 0.01),
              1,
            ),
            child: image,
          );
    if (widget.block.flipX || widget.block.flipY) {
      visual = Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(
          widget.block.flipX ? -1 : 1,
          widget.block.flipY ? -1 : 1,
          1,
        ),
        child: visual,
      );
    }
    if (widget.block.brightness.abs() > 0.001 ||
        (widget.block.contrast).abs() > 0.001 ||
        (widget.block.saturation - 1).abs() > 0.001 ||
        widget.block.warmth.abs() > 0.001) {
      visual = ColorFiltered(
        colorFilter: _imageFilter(widget.block),
        child: visual,
      );
    }
    if (widget.block.imageMask == 'circle') {
      visual = ClipOval(child: visual);
    } else if (widget.block.imageMask == 'rounded' ||
        widget.block.cornerRadius > 0) {
      visual = ClipRRect(
        borderRadius: BorderRadius.circular(
          math.max(0, widget.block.cornerRadius),
        ),
        child: visual,
      );
    }
    final frameWidth = widget.block.frameWidth;
    if (frameWidth > 0) {
      visual = DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: Color(widget.block.frameColorValue ?? 0xFF3B3226),
            width: frameWidth,
          ),
          shape: widget.block.imageMask == 'circle'
              ? BoxShape.circle
              : BoxShape.rectangle,
          borderRadius: widget.block.imageMask == 'circle'
              ? null
              : BorderRadius.circular(math.max(0, widget.block.cornerRadius)),
        ),
        child: visual,
      );
    }
    return visual;
  }

  Widget _buildTextEditor() {
    final controller = _quillController;
    if (controller != null && _usesQuill) {
      controller.readOnly = !widget.textEditing;
      return QuillEditor.basic(
        key: ValueKey('block-quill-${widget.block.id}'),
        controller: controller,
        focusNode: _richFocusNode,
        config: QuillEditorConfig(
          scrollable: false,
          expands: true,
          padding: const EdgeInsets.all(8),
          showCursor: widget.textEditing,
          enableInteractiveSelection: widget.textEditing,
        ),
      );
    }
    return TextField(
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
    );
  }

  void _createQuillController() {
    final raw = widget.block.richTextDelta;
    if (raw == null || !_richDeltaHasFormatting(raw)) return;
    try {
      final document = Document.fromJson(List<dynamic>.from(raw));
      _quillController =
          QuillController(
              document: document,
              selection: TextSelection.collapsed(
                offset: math.max(0, document.length - 1),
              ),
            )
            ..readOnly = !widget.textEditing
            ..addListener(_handleQuillChanged);
      _lastQuillDelta = document.toDelta().toJson().toString();
    } catch (_) {
      // Keep the plain TextField fallback for malformed or incomplete Delta
      // payloads rather than preventing the entry from opening.
      _quillController = null;
    }
  }

  bool get _usesQuill => _richDeltaHasFormatting(widget.block.richTextDelta);

  bool _richDeltaHasFormatting(List<dynamic>? delta) =>
      delta?.any((operation) {
        if (operation is! Map) return false;
        final attributes = operation['attributes'];
        return attributes is Map && attributes.isNotEmpty;
      }) ??
      false;

  void _handleQuillChanged() {
    final controller = _quillController;
    if (controller == null || controller.readOnly) return;
    final delta = controller.document.toDelta().toJson();
    final fingerprint = delta.toString();
    if (fingerprint == _lastQuillDelta) return;
    _lastQuillDelta = fingerprint;
    final plain = controller.document.toPlainText();
    widget.onRichTextChanged?.call(
      plain.endsWith('\n') ? plain.substring(0, plain.length - 1) : plain,
      delta,
    );
  }

  ColorFilter _imageFilter(CanvasRenderable block) {
    final saturation = block.saturation.clamp(0.0, 2.0).toDouble();
    final inverse = 1 - saturation;
    final red = 0.213 * inverse;
    final green = 0.715 * inverse;
    final blue = 0.072 * inverse;
    final contrast = 1 + block.contrast.clamp(-1.0, 1.0).toDouble();
    final offset = 128 * (1 - contrast) + block.brightness * 255;
    final warmth = block.warmth.clamp(-1.0, 1.0).toDouble() * 36;
    return ColorFilter.matrix(<double>[
      (red + saturation) * contrast,
      green * contrast,
      blue * contrast,
      0,
      offset + warmth,
      red * contrast,
      (green + saturation) * contrast,
      blue * contrast,
      0,
      offset,
      red * contrast,
      green * contrast,
      (blue + saturation) * contrast,
      0,
      offset - warmth,
      0,
      0,
      0,
      1,
      0,
    ]);
  }

  void _scheduleTextFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.editing || !widget.textEditing) return;
      (_quillController == null ? _textFocusNode : _richFocusNode)
          .requestFocus();
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    });
  }

  Widget _buildMoveEdge({Key? key}) {
    return Listener(
      key: key,
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (_moveEdgePointer != null) return;
        _moveEdgePointer = event.pointer;
        _requestSelection(event.kind, pointerDown: true);
        widget.onMoveStart(event.position);
      },
      onPointerMove: (event) {
        if (_moveEdgePointer == event.pointer) {
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

  void _requestSelection(
    PointerDeviceKind? kind, {
    bool pointerDown = false,
  }) {
    final onSelectionRequested = widget.onSelectionRequested;
    if (kind != null && onSelectionRequested != null) {
      onSelectionRequested(kind, pointerDown: pointerDown);
      return;
    }
    widget.onTap();
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

  final CanvasRenderable block;

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

  final CanvasRenderable block;

  @override
  void paint(Canvas canvas, Size size) {
    final points = block.inkPoints ?? const <Map<String, dynamic>>[];
    if (points.length < 2 || block.w <= 0 || block.h <= 0) return;
    final renderPoints = [
      for (final point in points)
        InkStrokePoint.fromJson(point)
            .scale(size.width / block.w, size.height / block.h),
    ];
    InkStrokeRenderer.paint(
      canvas,
      points: renderPoints,
      color: Color(block.strokeColorValue ?? 0xFF3B3226),
      width: block.strokeWidth.clamp(0.5, 20).toDouble() * 10,
      opacity: block.opacity,
      strokeType: strokeType,
    );
  }

  @override
  bool shouldRepaint(covariant _InkPainter oldDelegate) =>
      oldDelegate.block.toJson().toString() != block.toJson().toString();

  InkStrokeType get strokeType => inkStrokeTypeFromName(block.strokeType);
}
