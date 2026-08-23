import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/entry.dart';
import '../widgets/page_viewport.dart';
import 'block_widget.dart';

class EntryCanvas extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = PageViewport.modelToRenderScale;

        return SizedBox(
          width: workspaceSize.width,
          height: workspaceSize.height,
          child: Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: editing
                      ? (event) {
                          final point = event.localPosition;
                          final hitsBlock = blocks.any(
                            (block) => _containsBlock(point, block, scale),
                          );
                          if (!hitsBlock) onSelect(null);
                        }
                      : null,
                  child: Stack(
                    children: [
                      for (final block in blocks)
                        Positioned(
                          left: (block.x + worldOrigin.dx) * scale,
                          top: (block.y + worldOrigin.dy) * scale,
                          width: math.max(minWidth, block.w) * scale,
                          height: math.max(minHeight, block.h) * scale,
                          child: Transform.rotate(
                            angle: block.rotation,
                            child: BlockWidget(
                              block: block,
                              selected: selectedId == block.id,
                              editing: editing,
                              textEditing: textEditingId == block.id,
                              onTap: () => onSelect(block.id),
                              onEditText: () => onEditText(block.id),
                              onMove: (globalPosition, globalDelta) =>
                                  onChanged(
                                    block
                                      ..x =
                                          block.x +
                                          _canvasDelta(
                                                context,
                                                globalPosition,
                                                globalDelta,
                                              ).dx /
                                              scale
                                      ..y =
                                          block.y +
                                          _canvasDelta(
                                                context,
                                                globalPosition,
                                                globalDelta,
                                              ).dy /
                                              scale,
                                  ),
                              onResize: (globalPosition, globalDelta) =>
                                  onChanged(
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
                                  onChanged(block..rotation += delta),
                              imageBytes:
                                  _visualId(block) == null ||
                                      imageProvider != null
                                  ? null
                                  : imageBytes(_visualId(block)!),
                              imageProvider: _visualId(block) == null
                                  ? null
                                  : imageProvider?.call(_visualId(block)!),
                              onOpenImage: block.type == BlockType.image
                                  ? () => onOpenImage(block)
                                  : null,
                              onTextChanged: (text) =>
                                  onChanged(block..text = text),
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
    final width = math.max(minWidth, block.w + delta.dx / scale);
    if (block.type != BlockType.image && block.type != BlockType.sticker) {
      return block
        ..w = width
        ..h = math.max(minHeight, block.h + delta.dy / scale);
    }
    final aspectRatio = block.w <= 0 ? 1.0 : block.h / block.w;
    return block
      ..w = width
      ..h = math.max(minHeight, width * aspectRatio);
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
    final width = math.max(minWidth, block.w) * scale;
    final height = math.max(minHeight, block.h) * scale;
    final center = Offset(
      (block.x + worldOrigin.dx) * scale + width / 2,
      (block.y + worldOrigin.dy) * scale + height / 2,
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
