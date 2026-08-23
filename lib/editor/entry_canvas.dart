import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/entry.dart';
import '../widgets/page_viewport.dart';
import 'block_widget.dart';

class EntryCanvas extends StatefulWidget {
  const EntryCanvas({
    super.key,
    required this.blocks,
    required this.editing,
    required this.selectedId,
    required this.textEditingId,
    required this.onSelect,
    required this.onEditText,
    required this.onChanged,
    required this.imageBytes,
    this.imageProvider,
    required this.onOpenImage,
    this.workspaceSize = PageViewport.pageSize,
    this.worldOrigin = Offset.zero,
  });

  final List<ContentBlock> blocks;
  final bool editing;
  final String? selectedId;
  final String? textEditingId;
  final ValueChanged<String?> onSelect;
  final ValueChanged<String> onEditText;
  final ValueChanged<ContentBlock> onChanged;
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
  _BlockMoveSession? _moveSession;

  @override
  void didUpdateWidget(covariant EntryCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    final activeBlockId = _moveSession?.blockId;
    if (!widget.editing ||
        (activeBlockId != null &&
            !widget.blocks.any((block) => block.id == activeBlockId))) {
      _moveSession = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = PageViewport.modelToRenderScale;

        return SizedBox(
          width: widget.workspaceSize.width,
          height: widget.workspaceSize.height,
          child: Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: widget.editing
                      ? (event) {
                          final point = event.localPosition;
                          final hitsBlock = widget.blocks.any(
                            (block) => _containsBlock(point, block, scale),
                          );
                          if (!hitsBlock) widget.onSelect(null);
                        }
                      : null,
                  child: Stack(
                    children: [
                      for (final block in widget.blocks)
                        Positioned(
                          left: (block.x + widget.worldOrigin.dx) * scale,
                          top: (block.y + widget.worldOrigin.dy) * scale,
                          width:
                              math.max(EntryCanvas.minWidth, block.w) * scale,
                          height:
                              math.max(EntryCanvas.minHeight, block.h) * scale,
                          child: Transform.rotate(
                            angle: block.rotation,
                            child: BlockWidget(
                              block: block,
                              selected: widget.selectedId == block.id,
                              editing: widget.editing,
                              textEditing: widget.textEditingId == block.id,
                              onTap: () => widget.onSelect(block.id),
                              onEditText: () => widget.onEditText(block.id),
                              onMoveStart: (globalPosition) =>
                                  _startMove(context, block, globalPosition),
                              onMoveUpdate: (globalPosition) =>
                                  _updateMove(context, block, globalPosition),
                              onMoveEnd: _endMove,
                              onResize: (globalPosition, globalDelta) =>
                                  widget.onChanged(
                                    _resizedBlock(
                                      block,
                                      _canvasDelta(
                                        context,
                                        globalPosition,
                                        globalDelta,
                                      ),
                                      scale,
                                    ),
                                  ),
                              onRotate: (delta) =>
                                  widget.onChanged(block..rotation += delta),
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
                              onTextChanged: (text) =>
                                  widget.onChanged(block..text = text),
                              preserveAspectRatio:
                                  block.type == BlockType.image ||
                                  block.type == BlockType.sticker,
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

  ContentBlock _resizedBlock(ContentBlock block, Offset delta, double scale) {
    final width = math.max(EntryCanvas.minWidth, block.w + delta.dx / scale);
    if (block.type != BlockType.image && block.type != BlockType.sticker) {
      return block
        ..w = width
        ..h = math.max(EntryCanvas.minHeight, block.h + delta.dy / scale);
    }
    final aspectRatio = block.w <= 0 ? 1.0 : block.h / block.w;
    return block
      ..w = width
      ..h = math.max(EntryCanvas.minHeight, width * aspectRatio);
  }

  void _startMove(
    BuildContext canvasContext,
    ContentBlock block,
    Offset globalPosition,
  ) {
    final pointer = _globalToModel(canvasContext, globalPosition);
    if (pointer == null) return;
    _moveSession = _BlockMoveSession(
      blockId: block.id,
      grabOffset: pointer - Offset(block.x, block.y),
    );
  }

  void _updateMove(
    BuildContext canvasContext,
    ContentBlock block,
    Offset globalPosition,
  ) {
    final session = _moveSession;
    if (session == null || session.blockId != block.id) return;
    final pointer = _globalToModel(canvasContext, globalPosition);
    if (pointer == null) return;
    final position = pointer - session.grabOffset;
    widget.onChanged(
      block
        ..x = position.dx
        ..y = position.dy,
    );
  }

  void _endMove() => _moveSession = null;

  Offset? _globalToModel(BuildContext context, Offset globalPosition) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return null;
    return renderObject.globalToLocal(globalPosition) /
            PageViewport.modelToRenderScale -
        widget.worldOrigin;
  }

  Offset _canvasDelta(
    BuildContext context,
    Offset globalPosition,
    Offset globalDelta,
  ) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return globalDelta;
    final previousPosition = globalPosition - globalDelta;
    return renderObject.globalToLocal(globalPosition) -
        renderObject.globalToLocal(previousPosition);
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
  const _BlockMoveSession({required this.blockId, required this.grabOffset});

  final String blockId;
  final Offset grabOffset;
}
