import 'package:flutter/material.dart';

import '../models/entry.dart';
import 'geometry_services.dart';

/// Pure world/screen geometry used by canvas interaction code.
class CanvasGeometry {
  const CanvasGeometry._();

  static Offset rotate(Offset point, double angle) {
    return TransformService.rotate(point, angle);
  }

  static Size effectiveBlockSize(
    ContentBlock block, {
    required double minWidth,
    required double minHeight,
  }) => TransformService.effectiveBlockSize(
    block,
    minWidth: minWidth,
    minHeight: minHeight,
  );

  static Offset blockCenter(
    ContentBlock block, {
    required Offset worldOrigin,
    required double scale,
    required double minWidth,
    required double minHeight,
  }) => TransformService.blockCenter(
    block,
    worldOrigin: worldOrigin,
    scale: scale,
    minWidth: minWidth,
    minHeight: minHeight,
  );
  static bool containsBlock(
    Offset point,
    ContentBlock block, {
    required Offset worldOrigin,
    required double scale,
    required double minWidth,
    required double minHeight,
  }) => HitTestService.containsBlock(
    point,
    block,
    worldOrigin: worldOrigin,
    scale: scale,
    minWidth: minWidth,
    minHeight: minHeight,
  );
}
