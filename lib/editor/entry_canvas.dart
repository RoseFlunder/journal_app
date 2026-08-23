import 'dart:math' as math;

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
                            (block) => Rect.fromLTWH(
                              (block.x + worldOrigin.dx) * scale,
                              (block.y + worldOrigin.dy) * scale,
                              math.max(minWidth, block.w) * scale,
                              math.max(minHeight, block.h) * scale,
                            ).contains(point),
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
                              onMove: (delta) => onChanged(
                                block
                                  ..x = block.x + delta.dx / scale
                                  ..y = block.y + delta.dy / scale,
                              ),
                              onResize: (delta) => onChanged(
                                block
                                  ..w = math.max(
                                    minWidth,
                                    block.w + delta.dx / scale,
                                  )
                                  ..h = math.max(
                                    minHeight,
                                    block.h + delta.dy / scale,
                                  ),
                              ),
                              onRotate: (delta) =>
                                  onChanged(block..rotation += delta),
                              onTextChanged: (text) =>
                                  onChanged(block..text = text),
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
}
