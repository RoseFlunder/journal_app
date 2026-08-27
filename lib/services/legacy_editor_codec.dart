import '../models/entry.dart';
import '../models/document.dart';

/// Transitional aliases used while the renderer migrates to [CanvasNode].
/// Only this codec edge knows the mutable storage-era editor model; feature
/// views should not import `models/entry.dart` directly.
typedef LegacyCanvasBlock = ContentBlock;
typedef LegacyBlockType = BlockType;

/// Converts a legacy render value once at the canvas compatibility edge.
CanvasNode toCanvasNode(CanvasRenderable block) => switch (block) {
  CanvasNode node => node,
  ContentBlock legacy => CanvasNode.fromBlock(legacy),
  _ => CanvasNode.fromJson(block.toJson()),
};

/// Converts a read-only render value for compatibility callbacks that still
/// expose the legacy mutable block shape. This is the only conversion used by
/// the renderer compatibility edge; document and feature code stays node
/// native.
ContentBlock toLegacyCanvasBlock(CanvasRenderable block) => switch (block) {
  ContentBlock legacy => legacy,
  CanvasNode node => node.toBlock(),
  _ => ContentBlock.fromJson(block.toJson()),
};
