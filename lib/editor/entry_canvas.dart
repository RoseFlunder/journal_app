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
  });

  final List<ContentBlock> blocks;
  final bool editing;
  final String? selectedId;
  final String? textEditingId;
  final ValueChanged<String?> onSelect;
  final ValueChanged<String> onEditText;
  final ValueChanged<ContentBlock> onChanged;

  static const minWidth = 16.0;
  static const minHeight = 10.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = math.min(
          constraints.maxWidth / PageViewport.modelPageSize.width,
          constraints.maxHeight / PageViewport.modelPageSize.height,
        );
        final pageSize = PageViewport.modelPageSize * scale;
        final left = (constraints.maxWidth - pageSize.width) / 2;
        final top = (constraints.maxHeight - pageSize.height) / 2;

        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: pageSize.width,
              height: pageSize.height,
              child: Stack(
                children: [
                  for (final block in blocks)
                    Positioned(
                      left: block.x * scale,
                      top: block.y * scale,
                      width: math.max(minWidth, block.w) * scale,
                      height: math.max(minHeight, block.h) * scale,
                      child: BlockWidget(
                        block: block,
                        selected: selectedId == block.id,
                        editing: editing,
                        textEditing: textEditingId == block.id,
                        onTap: () => onSelect(block.id),
                        onEditText: () => onEditText(block.id),
                        onMove: (delta) => onChanged(
                          block
                            ..x = (block.x + delta.dx / scale)
                                .clamp(0, PageViewport.modelPageSize.width - block.w)
                            ..y = (block.y + delta.dy / scale)
                                .clamp(0, PageViewport.modelPageSize.height - block.h),
                        ),
                        onResize: (delta) => onChanged(
                          block
                            ..w = (block.w + delta.dx / scale)
                                .clamp(minWidth, PageViewport.modelPageSize.width - block.x)
                            ..h = (block.h + delta.dy / scale)
                                .clamp(minHeight, PageViewport.modelPageSize.height - block.y),
                        ),
                        onTextChanged: (text) => onChanged(block..text = text),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}