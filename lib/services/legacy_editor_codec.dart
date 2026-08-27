import '../models/entry.dart';

/// Transitional aliases used while the renderer migrates to [CanvasNode].
/// Only this codec edge knows the mutable storage-era editor model; feature
/// views should not import `models/entry.dart` directly.
typedef LegacyCanvasBlock = ContentBlock;
typedef LegacyBlockType = BlockType;
