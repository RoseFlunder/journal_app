import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../editor/entry_canvas.dart';
import '../../../../models/document.dart';

/// Feature-native canvas host. It renders the immutable node projection and
/// forwards gesture intents to the configured editor view model callbacks.
class EditorCanvasView extends StatelessWidget {
  const EditorCanvasView({
    super.key,
    required this.workspaceSize,
    required this.worldOrigin,
    required this.nodes,
    required this.board,
    required this.cameraScale,
    required this.editing,
    required this.selectedId,
    required this.selectedIds,
    required this.textEditingId,
    required this.onSelect,
    required this.onEditText,
    required this.onTransformChanged,
    required this.onTextChanged,
    required this.onInteractionStart,
    required this.onInteractionEnd,
    required this.onMoveSelection,
    required this.onRotateSelection,
    required this.onTouchRotateSelection,
    required this.selectMode,
    required this.drawMode,
    required this.inkColorValue,
    required this.inkWidth,
    required this.inkOpacity,
    required this.onLassoSelected,
    required this.onInkNodeCreated,
    required this.imageBytes,
    required this.imageProvider,
    required this.onOpenImage,
    required this.onOpenImageId,
    this.onResizeActiveChanged,
    this.onEditImageId,
  });

  final Size workspaceSize;
  final Offset worldOrigin;
  final Iterable<CanvasNode> nodes;
  final BoardSettings board;
  final double cameraScale;
  final bool editing;
  final String? selectedId;
  final Set<String> selectedIds;
  final String? textEditingId;
  final ValueChanged<String?> onSelect;
  final ValueChanged<String> onEditText;
  final CanvasTransformChanged onTransformChanged;
  final void Function(String blockId, String text, {List<dynamic>? delta})?
  onTextChanged;
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;
  final ValueChanged<Offset> onMoveSelection;
  final ValueChanged<double> onRotateSelection;
  final TouchSelectionRotation onTouchRotateSelection;
  final bool selectMode;
  final bool drawMode;
  final int inkColorValue;
  final double inkWidth;
  final double inkOpacity;
  final ValueChanged<Set<String>> onLassoSelected;
  final CanvasNodeCreated onInkNodeCreated;
  final Uint8List? Function(String assetId) imageBytes;
  final ImageProvider<Object>? Function(String assetId)? imageProvider;
  final ValueChanged<CanvasRenderable> onOpenImage;
  final ValueChanged<String> onOpenImageId;
  final ValueChanged<String>? onEditImageId;
  final ValueChanged<bool>? onResizeActiveChanged;

  @override
  Widget build(BuildContext context) => EntryCanvas(
          workspaceSize: workspaceSize,
          worldOrigin: worldOrigin,
          nodes: nodes,
          board: board,
          cameraScale: cameraScale,
          editing: editing,
          selectedId: selectedId,
          selectedIds: selectedIds,
          textEditingId: textEditingId,
          onResizeActiveChanged: onResizeActiveChanged,
          onSelect: onSelect,
          onEditText: onEditText,
          onTransformChanged: onTransformChanged,
          onTextChanged: onTextChanged,
          onInteractionStart: onInteractionStart,
          onInteractionEnd: onInteractionEnd,
          onMoveSelection: onMoveSelection,
          onRotateSelection: onRotateSelection,
          onTouchRotateSelection: onTouchRotateSelection,
          selectMode: selectMode,
          drawMode: drawMode,
          inkColorValue: inkColorValue,
          inkWidth: inkWidth,
          inkOpacity: inkOpacity,
          onLassoSelected: onLassoSelected,
          onInkNodeCreated: onInkNodeCreated,
          imageBytes: imageBytes,
          imageProvider: imageProvider,
          onOpenImage: onOpenImage,
          onOpenImageId: onOpenImageId,
          onEditImageId: onEditImageId,
          onEditImage: onEditImageId == null ? null : (_) {},
        );
}
