import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../models/entry.dart';
import '../widgets/page_viewport.dart';
import 'block_widget.dart';
import 'canvas_geometry.dart';

typedef TouchSelectionRotation = void Function(
  Set<String> blockIds,
  Offset pivot,
  double delta,
);

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
    this.onRotateSelection,
    this.onTouchRotateSelection,
    this.selectMode = false,
    this.drawMode = false,
    this.inkColorValue = 0xFF3B3226,
    this.inkWidth = 1.8,
    this.inkOpacity = 1,
    this.onLassoSelected,
    this.onInkCreated,
    required this.imageBytes,
    this.imageProvider,
    required this.onOpenImage,
    this.onEditImage,
    this.workspaceSize = PageViewport.pageSize,
    this.worldOrigin = Offset.zero,
    this.cameraScale = 1,
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
  final void Function(String blockId, String text, {List<dynamic>? delta})?
  onTextChanged;
  final ValueChanged<bool>? onResizeActiveChanged;
  final VoidCallback? onInteractionStart;
  final VoidCallback? onInteractionEnd;
  final ValueChanged<Offset>? onMoveSelection;
  final ValueChanged<double>? onRotateSelection;
  final TouchSelectionRotation? onTouchRotateSelection;
  final bool selectMode;
  final bool drawMode;
  final int inkColorValue;
  final double inkWidth;
  final double inkOpacity;
  final ValueChanged<Set<String>>? onLassoSelected;
  final ValueChanged<ContentBlock>? onInkCreated;
  final Uint8List? Function(String assetId) imageBytes;
  final ImageProvider<Object>? Function(String assetId)? imageProvider;
  final ValueChanged<ContentBlock> onOpenImage;
  final ValueChanged<ContentBlock>? onEditImage;
  final Size workspaceSize;
  final Offset worldOrigin;
  final double cameraScale;

  static const minWidth = 16.0;
  static const minHeight = 10.0;

  @override
  State<EntryCanvas> createState() => _EntryCanvasState();
}

class _EntryCanvasState extends State<EntryCanvas> {
  static final _uuid = Uuid();
  static const _resizeHandleSize = 48.0;
  static const _resizeMarkerSize = 10.0;
  _BlockMoveSession? _moveSession;
  _BlockResizeSession? _resizeSession;
  Matrix4? _resizeGlobalToCanvas;
  int? _resizePointer;
  bool _resizeActiveNotified = false;
  int _interactionDepth = 0;
  int? _lassoPointer;
  Offset? _lassoStart;
  Offset? _lassoEnd;
  int? _inkPointer;
  final List<Offset> _inkPoints = <Offset>[];
  final Map<int, Offset> _selectionRotationPointers = <int, Offset>{};
  List<int> _selectionRotationPointerIds = const <int>[];
  Set<String> _selectionRotationTargetIds = const <String>{};
  Offset? _selectionRotationPivot;
  bool _selectionRotating = false;
  bool _selectionRotationAwaitingClear = false;
  double? _selectionRotationAngle;
  int? _pendingClearSelectionPointer;

  @override
  void dispose() {
    _moveSession = null;
    _resizeSession = null;
    _resizeGlobalToCanvas = null;
    _resizePointer = null;
    _resizeActiveNotified = false;
    _selectionRotationPointers.clear();
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
    final rotationSelectionChanged =
        _selectionRotating &&
        !setEquals(
          _selectionRotationTargetIds,
          _rotationTargets().map((block) => block.id).toSet(),
        );
    if (!widget.editing ||
        resizeSelectionChanged ||
        rotationSelectionChanged ||
        activeBlockIds.any(
          (id) => !widget.blocks.any((block) => block.id == id),
        )) {
      if (_selectionRotating) _finishSelectionRotation();
      _moveSession = null;
      _resizeSession = null;
      _resizeGlobalToCanvas = null;
      _resizePointer = null;
      _selectionRotationPointers.clear();
      _selectionRotationPointerIds = const <int>[];
      _selectionRotationTargetIds = const <String>{};
      _selectionRotationPivot = null;
      _selectionRotating = false;
      _selectionRotationAwaitingClear = false;
      _selectionRotationAngle = null;
      _pendingClearSelectionPointer = null;
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
                          _handleSelectionRotationDown(event);
                          if (widget.drawMode) {
                            _inkPointer = event.pointer;
                            _inkPoints
                              ..clear()
                              ..add(_localToModel(point));
                            setState(() {});
                            return;
                          }
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
                            } else if (_selectionRotating) {
                              // The selected blocks own this page-wide touch
                              // gesture until either rotation finger lifts.
                            } else if (_shouldDeferTouchSelectionClear(event)) {
                              _pendingClearSelectionPointer = event.pointer;
                            } else {
                              widget.onSelect(null);
                            }
                          }
                        }
                      : null,
                  onPointerMove: widget.editing
                      ? (event) {
                          _handleSelectionRotationMove(event);
                          if (_inkPointer == event.pointer) {
                            _inkPoints.add(_localToModel(event.localPosition));
                            setState(() {});
                            return;
                          }
                          if (_lassoPointer != event.pointer) return;
                          setState(() => _lassoEnd = event.localPosition);
                        }
                      : null,
                  onPointerUp: widget.editing
                      ? (event) {
                          _handleSelectionRotationUp(event);
                          if (_inkPointer == event.pointer) {
                            _finishInk();
                          } else {
                            _finishLasso(event);
                          }
                        }
                      : null,
                  onPointerCancel: widget.editing
                      ? (event) {
                          _handleSelectionRotationUp(event);
                          if (_inkPointer == event.pointer) {
                            _cancelInk();
                          } else {
                            _finishLasso(event);
                          }
                        }
                      : null,
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
                          child: IgnorePointer(
                            ignoring: widget.drawMode,
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
                                  controlScale: widget.cameraScale,
                                  textEditing: widget.textEditingId == block.id,
                                  onTap: () => widget.onSelect(block.id),
                                  onEditText: () => widget.onEditText(block.id),
                                  onMoveStart: (globalPosition) => _startMove(
                                    context,
                                    block,
                                    globalPosition,
                                  ),
                                  onMoveUpdate: (globalPosition) => _updateMove(
                                    context,
                                    block,
                                    globalPosition,
                                  ),
                                  onMoveEnd: _endMove,
                                  onRotate: (delta) =>
                                      _rotateBlockOrSelection(block, delta),
                                  onTransformStart: _beginInteraction,
                                  onTransformEnd: _endInteraction,
                                  showRotateHandle: _showRotateHandle,
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
                                  onEditImage:
                                      block.type == BlockType.image ||
                                          block.type == BlockType.sticker
                                      ? () => widget.onEditImage?.call(block)
                                      : null,
                                  onTextChanged: (text) {
                                    if (block.locked) return;
                                    final onTextChanged = widget.onTextChanged;
                                    if (onTextChanged != null) {
                                      onTextChanged(block.id, text);
                                    } else {
                                      final next = block.clone()..text = text;
                                      block.text = next.text;
                                      widget.onChanged(next);
                                    }
                                  },
                                  onRichTextChanged: (text, delta) => widget
                                      .onTextChanged
                                      ?.call(block.id, text, delta: delta),
                                  preserveAspectRatio:
                                      block.type == BlockType.image ||
                                      block.type == BlockType.sticker,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (selectedBlock != null && !selectedBlock.locked)
                        ..._buildResizeHandles(context, selectedBlock, scale),
                      if (_inkPoints.length > 1)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _InkPreviewPainter(
                                points: _inkPoints,
                                worldOrigin: widget.worldOrigin,
                                color: Color(widget.inkColorValue),
                                width: widget.inkWidth,
                                opacity: widget.inkOpacity,
                              ),
                            ),
                          ),
                        ),
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

  bool get _showRotateHandle =>
      kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS);

  bool _isSelected(ContentBlock block) => widget.selectedIds.isEmpty
      ? widget.selectedId == block.id
      : widget.selectedIds.contains(block.id);

  Iterable<ContentBlock> _rotationTargets() => widget.blocks.where(
    (block) => !block.hidden && _isSelected(block) && !block.locked,
  );

  bool _shouldDeferTouchSelectionClear(PointerDownEvent event) =>
      event.kind == PointerDeviceKind.touch && _rotationTargets().isNotEmpty;

  void _handleSelectionRotationDown(PointerDownEvent event) {
    if (!widget.editing || widget.drawMode || widget.selectMode) return;
    if (_selectionRotationPointers.isEmpty) {
      _selectionRotationAwaitingClear = false;
      _selectionRotating = false;
      _selectionRotationPointerIds = const <int>[];
      _selectionRotationTargetIds = const <String>{};
      _selectionRotationPivot = null;
      _selectionRotationAngle = null;
    }
    _selectionRotationPointers[event.pointer] = event.localPosition;
    if (_selectionRotationPointers.length != 2 ||
        _selectionRotationAwaitingClear ||
        _selectionRotating) {
      return;
    }

    final targets = _rotationTargets().map((block) => block.id).toSet();
    if (targets.isEmpty) return;
    final pointerIds = _selectionRotationPointers.keys.take(2).toList();
    final first = _selectionRotationPointers[pointerIds[0]]!;
    final second = _selectionRotationPointers[pointerIds[1]]!;
    _pendingClearSelectionPointer = null;
    if (_moveSession != null) {
      _moveSession = null;
    } else {
      _beginInteraction();
    }
    _selectionRotating = true;
    _selectionRotationPointerIds = pointerIds;
    _selectionRotationTargetIds = Set<String>.unmodifiable(targets);
    _selectionRotationPivot = _localToModel((first + second) / 2);
    _selectionRotationAngle = _pointerAngle(pointerIds);
  }

  void _handleSelectionRotationMove(PointerMoveEvent event) {
    if (!_selectionRotationPointers.containsKey(event.pointer)) return;
    _selectionRotationPointers[event.pointer] = event.localPosition;
    if (!_selectionRotating) return;
    final angle = _pointerAngle(_selectionRotationPointerIds);
    final previous = _selectionRotationAngle;
    final pivot = _selectionRotationPivot;
    if (angle == null || previous == null || pivot == null) return;
    var delta = angle - previous;
    if (delta > math.pi) delta -= math.pi * 2;
    if (delta < -math.pi) delta += math.pi * 2;
    widget.onTouchRotateSelection?.call(
      _selectionRotationTargetIds,
      pivot,
      delta,
    );
    _selectionRotationAngle = angle;
  }

  void _handleSelectionRotationUp(PointerEvent event) {
    _selectionRotationPointers.remove(event.pointer);
    if (_selectionRotating &&
        _selectionRotationPointerIds.contains(event.pointer)) {
      _finishSelectionRotation();
      _selectionRotationAwaitingClear = _selectionRotationPointers.isNotEmpty;
    }
    if (_pendingClearSelectionPointer == event.pointer) {
      _pendingClearSelectionPointer = null;
      widget.onSelect(null);
    }
    if (_selectionRotationPointers.isEmpty) {
      _selectionRotationAwaitingClear = false;
      _selectionRotationPointerIds = const <int>[];
    }
  }

  void _finishSelectionRotation() {
    if (_selectionRotating) _endInteraction();
    _selectionRotating = false;
    _selectionRotationTargetIds = const <String>{};
    _selectionRotationPivot = null;
    _selectionRotationAngle = null;
  }

  double? _pointerAngle(List<int> pointerIds) {
    if (pointerIds.length < 2) return null;
    final first = _selectionRotationPointers[pointerIds[0]];
    final second = _selectionRotationPointers[pointerIds[1]];
    if (first == null || second == null) return null;
    final delta = second - first;
    return math.atan2(delta.dy, delta.dx);
  }

  void _rotateBlockOrSelection(ContentBlock block, double delta) {
    if (block.locked || !_isSelected(block)) return;
    final rotateSelection = widget.onRotateSelection;
    if (rotateSelection != null) {
      rotateSelection(delta);
      return;
    }
    final next = block.clone()..rotation += delta;
    block.rotation = next.rotation;
    widget.onChanged(next);
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
      if (session.horizontal == 0) {
        width = math.max(EntryCanvas.minWidth, height * ratio);
      } else {
        width = math.max(EntryCanvas.minWidth, width);
        height = math.max(EntryCanvas.minHeight, width / ratio);
      }
    }
    final oppositeLocal = Offset(
      -session.horizontal * width / 2,
      -session.vertical * height / 2,
    );
    final center =
        session.oppositeAnchor - _rotate(oppositeLocal, session.rotation);
    return block.clone()
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
    if (block.locked || _selectionRotating) return;
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
    if (block.locked || _selectionRotating) return;
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
    final next = block.clone()
      ..x = position.dx
      ..y = position.dy;
    block
      ..x = next.x
      ..y = next.y;
    widget.onChanged(next);
  }

  void _endMove() {
    if (_moveSession == null) return;
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
      aspectRatio: width / height,
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
    final next = _resizedBlock(block, session, pointer);
    block
      ..x = next.x
      ..y = next.y
      ..w = next.w
      ..h = next.h;
    widget.onChanged(next);
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

  Offset _localToModel(Offset point) =>
      point / PageViewport.modelToRenderScale - widget.worldOrigin;

  void _finishInk() {
    _inkPointer = null;
    if (_inkPoints.length < 2) {
      _inkPoints.clear();
      setState(() {});
      return;
    }
    var minX = _inkPoints.first.dx;
    var maxX = minX;
    var minY = _inkPoints.first.dy;
    var maxY = minY;
    for (final point in _inkPoints.skip(1)) {
      minX = math.min(minX, point.dx);
      maxX = math.max(maxX, point.dx);
      minY = math.min(minY, point.dy);
      maxY = math.max(maxY, point.dy);
    }
    const padding = 2.0;
    final block = ContentBlock(
      id: _uuid.v4(),
      type: BlockType.ink,
      x: minX - padding,
      y: minY - padding,
      w: math.max(EntryCanvas.minWidth, maxX - minX + padding * 2),
      h: math.max(EntryCanvas.minHeight, maxY - minY + padding * 2),
      strokeColorValue: widget.inkColorValue,
      strokeWidth: widget.inkWidth,
      opacity: widget.inkOpacity,
      inkPoints: [
        for (final point in _inkPoints)
          {'x': point.dx - minX + padding, 'y': point.dy - minY + padding},
      ],
    );
    _inkPoints.clear();
    setState(() {});
    widget.onInkCreated?.call(block);
  }

  void _cancelInk() {
    _inkPointer = null;
    _inkPoints.clear();
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
    final handleSize = _screenHandleSize;
    final handleOffset =
        point * scale +
        Offset(
          handle.horizontal * handleSize * 0.58,
          handle.vertical * handleSize * 0.58,
        ) -
        Offset(handleSize / 2, handleSize / 2);
    return Positioned(
      left: handleOffset.dx,
      top: handleOffset.dy,
      width: handleSize,
      height: handleSize,
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
            decoration: const BoxDecoration(),
            child: Center(
              child: SizedBox(
                width: _resizeMarkerSize,
                height: _resizeMarkerSize,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFFC97068),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
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
    return CanvasGeometry.rotate(point, angle);
  }

  bool _containsResizeHandle(Offset point, ContentBlock block, double scale) {
    final width = math.max(EntryCanvas.minWidth, block.w);
    final height = math.max(EntryCanvas.minHeight, block.h);
    final center = Offset(
      (block.x + widget.worldOrigin.dx) * scale + width * scale / 2,
      (block.y + widget.worldOrigin.dy) * scale + height * scale / 2,
    );
    return _ResizeHandle.values.any((handle) {
      final handleSize = _screenHandleSize;
      final local = Offset(
        width * scale * handle.horizontal / 2,
        height * scale * handle.vertical / 2,
      );
      return Rect.fromCenter(
        center:
            center +
            _rotate(local, block.rotation) +
            Offset(
              handle.horizontal * handleSize * 0.58,
              handle.vertical * handleSize * 0.58,
            ),
        width: handleSize,
        height: handleSize,
      ).contains(point);
    });
  }

  double get _screenHandleSize =>
      _resizeHandleSize / math.max(widget.cameraScale, 0.01);

  Offset? _globalToModel(BuildContext context, Offset globalPosition) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return null;
    return renderObject.globalToLocal(globalPosition) /
            PageViewport.modelToRenderScale -
        widget.worldOrigin;
  }

  bool _containsBlock(Offset point, ContentBlock block, double scale) =>
      CanvasGeometry.containsBlock(
        point,
        block,
        worldOrigin: widget.worldOrigin,
        scale: scale,
        minWidth: EntryCanvas.minWidth,
        minHeight: EntryCanvas.minHeight,
      );

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

class _InkPreviewPainter extends CustomPainter {
  const _InkPreviewPainter({
    required this.points,
    required this.worldOrigin,
    required this.color,
    required this.width,
    required this.opacity,
  });

  final List<Offset> points;
  final Offset worldOrigin;
  final Color color;
  final double width;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final path = Path();
    for (var index = 0; index < points.length; index++) {
      final point =
          (points[index] + worldOrigin) * PageViewport.modelToRenderScale;
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = width * PageViewport.modelToRenderScale
        ..color = color.withValues(alpha: opacity),
    );
  }

  @override
  bool shouldRepaint(covariant _InkPreviewPainter oldDelegate) => true;
}
