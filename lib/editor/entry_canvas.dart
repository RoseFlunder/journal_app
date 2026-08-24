import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/entry.dart';
import '../widgets/page_viewport.dart';
import 'block_widget.dart';

class EntryCanvas extends StatefulWidget {
  const EntryCanvas({
    super.key,
    required this.blocks,
    this.board = const BoardSettings(),
    required this.editing,
    required this.selectedId,
    this.selectedIds = const <String>{},
    required this.textEditingId,
    required this.onSelect,
    required this.onEditText,
    required this.onChanged,
    this.onTextChanged,
    this.onResizeActiveChanged,
    this.onInteractionStart,
    this.onInteractionEnd,
    this.onMoveSelection,
    this.selectMode = false,
    this.onLassoSelected,
    required this.imageBytes,
    this.imageProvider,
    required this.onOpenImage,
    this.workspaceSize = PageViewport.pageSize,
    this.worldOrigin = Offset.zero,
  });

  final List<ContentBlock> blocks;
  final BoardSettings board;
  final bool editing;
  final String? selectedId;
  final Set<String> selectedIds;
  final String? textEditingId;
  final ValueChanged<String?> onSelect;
  final ValueChanged<String> onEditText;
  final ValueChanged<ContentBlock> onChanged;
  final void Function(String blockId, String text)? onTextChanged;
  final ValueChanged<bool>? onResizeActiveChanged;
  final VoidCallback? onInteractionStart;
  final VoidCallback? onInteractionEnd;
  final ValueChanged<Offset>? onMoveSelection;
  final bool selectMode;
  final ValueChanged<Set<String>>? onLassoSelected;
  final Uint8List? Function(String assetId) imageBytes;
  final ImageProvider<Object>? Function(String assetId)? imageProvider;
  final ValueChanged<ContentBlock> onOpenImage;
  final Size workspaceSize;
  final Offset worldOrigin;

  static const minWidth = 16.0;
  static const minHeight = 10.0;

  @override
  State<EntryCanvas> createState() => _EntryCanvasState();
}

class _EntryCanvasState extends State<EntryCanvas> {
  static const _resizeHandleSize = 48.0;
  _BlockMoveSession? _moveSession;
  _BlockResizeSession? _resizeSession;
  Matrix4? _resizeGlobalToCanvas;
  int? _resizePointer;
  bool _resizeActiveNotified = false;
  int _interactionDepth = 0;
  int? _lassoPointer;
  Offset? _lassoStart;
  Offset? _lassoEnd;

  @override
  void dispose() {
    _moveSession = null;
    _resizeSession = null;
    _resizeGlobalToCanvas = null;
    _resizePointer = null;
    if (_resizeActiveNotified) {
      _resizeActiveNotified = false;
      final onResizeActiveChanged = widget.onResizeActiveChanged;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onResizeActiveChanged?.call(false);
      });
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant EntryCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    final activeBlockIds = {
      if (_moveSession case final session?) session.blockId,
      if (_resizeSession case final session?) session.blockId,
    };
    final resizeSelectionChanged =
        _resizeSession != null && _resizeSession!.blockId != widget.selectedId;
    if (!widget.editing ||
        resizeSelectionChanged ||
        activeBlockIds.any(
          (id) => !widget.blocks.any((block) => block.id == id),
        )) {
      _moveSession = null;
      _resizeSession = null;
      _resizeGlobalToCanvas = null;
      _resizePointer = null;
      if (_resizeActiveNotified) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _setResizeActive(false);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = PageViewport.modelToRenderScale;
        ContentBlock? selectedBlock;
        if (widget.editing && widget.selectedId != null) {
          for (final block in widget.blocks) {
            if (block.id == widget.selectedId) {
              selectedBlock = block;
              break;
            }
          }
        }

        return SizedBox(
          width: widget.workspaceSize.width,
          height: widget.workspaceSize.height,
          child: Stack(
            children: [
              if (widget.board.gridVisible)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _GridPainter(
                        spacing: math.max(2, widget.board.gridSize) * scale,
                      ),
                    ),
                  ),
                ),
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: widget.editing
                      ? (event) {
                          final point = event.localPosition;
                          if (selectedBlock != null &&
                              _containsResizeHandle(
                                point,
                                selectedBlock,
                                scale,
                              )) {
                            return;
                          }
                          final hitsBlock = widget.blocks.any(
                            (block) =>
                                !block.hidden &&
                                _containsBlock(point, block, scale),
                          );
                          if (!hitsBlock) {
                            if (widget.selectMode) {
                              _lassoPointer = event.pointer;
                              _lassoStart = point;
                              _lassoEnd = point;
                              setState(() {});
                            } else {
                              widget.onSelect(null);
                            }
                          }
                        }
                      : null,
                  onPointerMove: widget.editing
                      ? (event) {
                          if (_lassoPointer != event.pointer) return;
                          setState(() => _lassoEnd = event.localPosition);
                        }
                      : null,
                  onPointerUp: widget.editing ? _finishLasso : null,
                  onPointerCancel: widget.editing ? _finishLasso : null,
                  child: Stack(
                    children: [
                      for (final block in widget.blocks.where(
                        (block) => !block.hidden,
                      ))
                        Positioned(
                          left: (block.x + widget.worldOrigin.dx) * scale,
                          top: (block.y + widget.worldOrigin.dy) * scale,
                          width:
                              math.max(EntryCanvas.minWidth, block.w) * scale,
                          height:
                              math.max(EntryCanvas.minHeight, block.h) * scale,
                          child: Transform.rotate(
                            angle: block.rotation,
                            child: Opacity(
                              opacity: block.opacity,
                              child: BlockWidget(
                                block: block,
                                selected: widget.selectedIds.isEmpty
                                    ? widget.selectedId == block.id
                                    : widget.selectedIds.contains(block.id),
                                editing: widget.editing,
                                locked: block.locked,
                                textEditing: widget.textEditingId == block.id,
                                onTap: () => widget.onSelect(block.id),
                                onEditText: () => widget.onEditText(block.id),
                                onMoveStart: (globalPosition) =>
                                    _startMove(context, block, globalPosition),
                                onMoveUpdate: (globalPosition) =>
                                    _updateMove(context, block, globalPosition),
                                onMoveEnd: _endMove,
                                onRotate: (delta) {
                                  if (!block.locked) {
                                    widget.onChanged(block..rotation += delta);
                                  }
                                },
                                onTransformStart: _beginInteraction,
                                onTransformEnd: _endInteraction,
                                imageBytes:
                                    _visualId(block) == null ||
                                        widget.imageProvider != null
                                    ? null
                                    : widget.imageBytes(_visualId(block)!),
                                imageProvider: _visualId(block) == null
                                    ? null
                                    : widget.imageProvider?.call(
                                        _visualId(block)!,
                                      ),
                                onOpenImage: block.type == BlockType.image
                                    ? () => widget.onOpenImage(block)
                                    : null,
                                onTextChanged: (text) {
                                  if (block.locked) return;
                                  final onTextChanged = widget.onTextChanged;
                                  if (onTextChanged != null) {
                                    onTextChanged(block.id, text);
                                  } else {
                                    widget.onChanged(block..text = text);
                                  }
                                },
                                preserveAspectRatio:
                                    block.type == BlockType.image ||
                                    block.type == BlockType.sticker,
                              ),
                            ),
                          ),
                        ),
                      if (selectedBlock != null && !selectedBlock.locked)
                        ..._buildResizeHandles(context, selectedBlock, scale),
                      if (_lassoStart != null && _lassoEnd != null)
                        Positioned.fromRect(
                          rect: Rect.fromPoints(_lassoStart!, _lassoEnd!),
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: const Color(0x33C97068),
                                border: Border.all(
                                  color: const Color(0xFFC97068),
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  ContentBlock _resizedBlock(
    ContentBlock block,
    _BlockResizeSession session,
    Offset pointer,
  ) {
    if (block.locked) return block;
    final localDelta = _rotate(
      pointer - session.startPointer,
      -session.rotation,
    );
    var width = session.startSize.width;
    var height = session.startSize.height;
    if (session.horizontal < 0) {
      width -= localDelta.dx;
    } else if (session.horizontal > 0) {
      width += localDelta.dx;
    }
    if (session.vertical < 0) {
      height -= localDelta.dy;
    } else if (session.vertical > 0) {
      height += localDelta.dy;
    }
    if (block.type != BlockType.image && block.type != BlockType.sticker) {
      if (width < EntryCanvas.minWidth) width = EntryCanvas.minWidth;
      if (height < EntryCanvas.minHeight) height = EntryCanvas.minHeight;
    } else {
      final ratio = session.aspectRatio;
      final proposed = session.horizontal == 0 ? height * ratio : width;
      width = math.max(EntryCanvas.minWidth, proposed);
      height = math.max(EntryCanvas.minHeight, width * ratio);
    }
    final oppositeLocal = Offset(
      -session.horizontal * width / 2,
      -session.vertical * height / 2,
    );
    final center =
        session.oppositeAnchor - _rotate(oppositeLocal, session.rotation);
    return block
      ..x = center.dx - width / 2
      ..y = center.dy - height / 2
      ..w = width
      ..h = height;
  }

  void _startMove(
    BuildContext canvasContext,
    ContentBlock block,
    Offset globalPosition,
  ) {
    if (block.locked) return;
    final pointer = _globalToModel(canvasContext, globalPosition);
    if (pointer == null) return;
    _beginInteraction();
    _moveSession = _BlockMoveSession(
      blockId: block.id,
      grabOffset: pointer - Offset(block.x, block.y),
      startPointer: pointer,
      lastPointer: pointer,
      multi:
          widget.selectedIds.length > 1 &&
          widget.selectedIds.contains(block.id),
    );
  }

  void _updateMove(
    BuildContext canvasContext,
    ContentBlock block,
    Offset globalPosition,
  ) {
    if (block.locked) return;
    final session = _moveSession;
    if (session == null || session.blockId != block.id) return;
    final pointer = _globalToModel(canvasContext, globalPosition);
    if (pointer == null) return;
    if (session.multi) {
      widget.onMoveSelection?.call(pointer - session.lastPointer);
      session.lastPointer = pointer;
      return;
    }
    final position = pointer - session.grabOffset;
    widget.onChanged(
      block
        ..x = position.dx
        ..y = position.dy,
    );
  }

  void _endMove() {
    _moveSession = null;
    _endInteraction();
  }

  void _startResize(
    BuildContext canvasContext,
    ContentBlock block,
    Offset globalPosition,
    _ResizeHandle handle,
  ) {
    if (block.locked) return;
    final renderObject = canvasContext.findRenderObject();
    if (renderObject is! RenderBox) return;
    _resizeGlobalToCanvas = Matrix4.inverted(renderObject.getTransformTo(null));
    final pointer = _resizePointerToModel(globalPosition);
    if (pointer == null) return;
    _beginInteraction();
    final width = math.max(EntryCanvas.minWidth, block.w);
    final height = math.max(EntryCanvas.minHeight, block.h);
    final center = Offset(block.x + width / 2, block.y + height / 2);
    final oppositeLocal = Offset(
      -handle.horizontal * width / 2,
      -handle.vertical * height / 2,
    );
    _resizeSession = _BlockResizeSession(
      blockId: block.id,
      startPointer: pointer,
      startSize: Size(width, height),
      aspectRatio: height / width,
      rotation: block.rotation,
      oppositeAnchor: center + _rotate(oppositeLocal, block.rotation),
      horizontal: handle.horizontal,
      vertical: handle.vertical,
    );
  }

  void _updateResize(
    BuildContext canvasContext,
    ContentBlock block,
    Offset globalPosition,
  ) {
    final session = _resizeSession;
    if (session == null || session.blockId != block.id) return;
    final pointer = _resizePointerToModel(globalPosition);
    if (pointer == null) return;
    widget.onChanged(_resizedBlock(block, session, pointer));
  }

  void _endResize() {
    _resizeSession = null;
    _resizeGlobalToCanvas = null;
    _resizePointer = null;
    _setResizeActive(false);
    _endInteraction();
  }

  void _beginInteraction() {
    if (_interactionDepth++ == 0) widget.onInteractionStart?.call();
  }

  void _endInteraction() {
    if (_interactionDepth == 0) return;
    if (--_interactionDepth == 0) widget.onInteractionEnd?.call();
  }

  void _finishLasso(PointerEvent event) {
    if (_lassoPointer != event.pointer) return;
    final start = _lassoStart;
    final end = _lassoEnd;
    _lassoPointer = null;
    _lassoStart = null;
    _lassoEnd = null;
    if (start == null || end == null) return;
    final selection = Rect.fromPoints(start, end);
    if (selection.width > 8 || selection.height > 8) {
      final ids = widget.blocks
          .where((block) => !block.hidden)
          .where((block) {
            final rect = Rect.fromLTWH(
              (block.x + widget.worldOrigin.dx) *
                  PageViewport.modelToRenderScale,
              (block.y + widget.worldOrigin.dy) *
                  PageViewport.modelToRenderScale,
              block.w * PageViewport.modelToRenderScale,
              block.h * PageViewport.modelToRenderScale,
            );
            return selection.overlaps(rect);
          })
          .map((block) => block.id)
          .toSet();
      widget.onLassoSelected?.call(ids);
    }
    setState(() {});
  }

  List<Widget> _buildResizeHandles(
    BuildContext canvasContext,
    ContentBlock block,
    double scale,
  ) => _ResizeHandle.values.map((handle) {
    final width = math.max(EntryCanvas.minWidth, block.w);
    final height = math.max(EntryCanvas.minHeight, block.h);
    final center = Offset(
      block.x + widget.worldOrigin.dx + width / 2,
      block.y + widget.worldOrigin.dy + height / 2,
    );
    final local = Offset(
      width * handle.horizontal / 2,
      height * handle.vertical / 2,
    );
    final point = center + _rotate(local, block.rotation);
    // Keep handles outside the object edge so they do not steal a move drag.
    final handleOffset =
        point * scale +
        Offset(handle.horizontal * 28, handle.vertical * 28) -
        const Offset(_resizeHandleSize / 2, _resizeHandleSize / 2);
    return Positioned(
      left: handleOffset.dx,
      top: handleOffset.dy,
      width: _resizeHandleSize,
      height: _resizeHandleSize,
      child: RawGestureDetector(
        key: ValueKey(
          handle == _ResizeHandle.bottomRight
              ? 'resize-${block.id}'
              : 'resize-${block.id}-${handle.name}',
        ),
        gestures: {
          EagerGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                EagerGestureRecognizer.new,
                (recognizer) {},
              ),
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            if (_resizePointer != null) return;
            _resizePointer = event.pointer;
            _setResizeActive(true);
            _startResize(canvasContext, block, event.position, handle);
          },
          onPointerMove: (event) {
            if (_resizePointer == event.pointer) {
              _updateResize(canvasContext, block, event.position);
            }
          },
          onPointerUp: (event) {
            if (_resizePointer == event.pointer) _endResize();
          },
          onPointerCancel: (event) {
            if (_resizePointer == event.pointer) _endResize();
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFC97068), width: 3),
            ),
            child: Icon(handle.icon, size: 20, color: const Color(0xFFC97068)),
          ),
        ),
      ),
    );
  }).toList();

  void _setResizeActive(bool active) {
    if (_resizeActiveNotified == active) return;
    _resizeActiveNotified = active;
    widget.onResizeActiveChanged?.call(active);
  }

  Offset? _resizePointerToModel(Offset globalPosition) {
    final transform = _resizeGlobalToCanvas;
    if (transform == null) return null;
    return MatrixUtils.transformPoint(transform, globalPosition) /
            PageViewport.modelToRenderScale -
        widget.worldOrigin;
  }

  Offset _rotate(Offset point, double angle) {
    final cosine = math.cos(angle);
    final sine = math.sin(angle);
    return Offset(
      point.dx * cosine - point.dy * sine,
      point.dx * sine + point.dy * cosine,
    );
  }

  bool _containsResizeHandle(Offset point, ContentBlock block, double scale) {
    final width = math.max(EntryCanvas.minWidth, block.w);
    final height = math.max(EntryCanvas.minHeight, block.h);
    final center = Offset(
      (block.x + widget.worldOrigin.dx) * scale + width * scale / 2,
      (block.y + widget.worldOrigin.dy) * scale + height * scale / 2,
    );
    return _ResizeHandle.values.any((handle) {
      final local = Offset(
        width * scale * handle.horizontal / 2,
        height * scale * handle.vertical / 2,
      );
      return Rect.fromCenter(
        center:
            center +
            _rotate(local, block.rotation) +
            Offset(handle.horizontal * 28, handle.vertical * 28),
        width: _resizeHandleSize,
        height: _resizeHandleSize,
      ).contains(point);
    });
  }

  Offset? _globalToModel(BuildContext context, Offset globalPosition) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return null;
    return renderObject.globalToLocal(globalPosition) /
            PageViewport.modelToRenderScale -
        widget.worldOrigin;
  }

  bool _containsBlock(Offset point, ContentBlock block, double scale) {
    final width = math.max(EntryCanvas.minWidth, block.w) * scale;
    final height = math.max(EntryCanvas.minHeight, block.h) * scale;
    final center = Offset(
      (block.x + widget.worldOrigin.dx) * scale + width / 2,
      (block.y + widget.worldOrigin.dy) * scale + height / 2,
    );
    final offset = point - center;
    final cosine = math.cos(-block.rotation);
    final sine = math.sin(-block.rotation);
    final local = Offset(
      offset.dx * cosine - offset.dy * sine,
      offset.dx * sine + offset.dy * cosine,
    );
    return local.dx.abs() <= width / 2 && local.dy.abs() <= height / 2;
  }

  String? _visualId(ContentBlock block) =>
      block.type == BlockType.sticker ? block.stickerId : block.assetId;
}

class _BlockMoveSession {
  _BlockMoveSession({
    required this.blockId,
    required this.grabOffset,
    required this.startPointer,
    required this.lastPointer,
    required this.multi,
  });

  final String blockId;
  final Offset grabOffset;
  final Offset startPointer;
  Offset lastPointer;
  final bool multi;
}

class _BlockResizeSession {
  const _BlockResizeSession({
    required this.blockId,
    required this.startPointer,
    required this.startSize,
    required this.aspectRatio,
    required this.rotation,
    required this.oppositeAnchor,
    required this.horizontal,
    required this.vertical,
  });

  final String blockId;
  final Offset startPointer;
  final Size startSize;
  final double aspectRatio;
  final double rotation;
  final Offset oppositeAnchor;
  final double horizontal;
  final double vertical;
}

enum _ResizeHandle {
  topLeft(-1, -1, Icons.north_west),
  top(0, -1, Icons.unfold_more),
  topRight(1, -1, Icons.north_east),
  right(1, 0, Icons.unfold_less),
  bottomRight(1, 1, Icons.south_east),
  bottom(0, 1, Icons.unfold_more),
  bottomLeft(-1, 1, Icons.south_west),
  left(-1, 0, Icons.unfold_less);

  const _ResizeHandle(this.horizontal, this.vertical, this.icon);
  final double horizontal;
  final double vertical;
  final IconData icon;
}

class _GridPainter extends CustomPainter {
  const _GridPainter({required this.spacing});

  final double spacing;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF3B3226).withValues(alpha: 0.09)
      ..strokeWidth = 1;
    for (var x = 0.0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      oldDelegate.spacing != spacing;
}
