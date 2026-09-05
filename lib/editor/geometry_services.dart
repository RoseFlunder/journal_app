import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/document.dart';

/// Pure transform calculations shared by rendering and interaction code.
class TransformService {
  const TransformService._();

  static Offset rotate(Offset point, double angle) {
    final cosine = math.cos(angle);
    final sine = math.sin(angle);
    return Offset(
      point.dx * cosine - point.dy * sine,
      point.dx * sine + point.dy * cosine,
    );
  }

  static Size effectiveBlockSize(
    CanvasRenderable block, {
    required double minWidth,
    required double minHeight,
  }) => Size(math.max(minWidth, block.w), math.max(minHeight, block.h));

  static Offset blockCenter(
    CanvasRenderable block, {
    required Offset worldOrigin,
    required double scale,
    required double minWidth,
    required double minHeight,
  }) {
    final size = effectiveBlockSize(
      block,
      minWidth: minWidth,
      minHeight: minHeight,
    );
    return Offset(
          (block.x + worldOrigin.dx) * scale,
          (block.y + worldOrigin.dy) * scale,
        ) +
        Offset(size.width * scale / 2, size.height * scale / 2);
  }
}

/// Pure block hit-testing in the displayed coordinate space.
class HitTestService {
  const HitTestService._();

  static bool containsBlock(
    Offset point,
    CanvasRenderable block, {
    required Offset worldOrigin,
    required double scale,
    required double minWidth,
    required double minHeight,
  }) {
    final size = TransformService.effectiveBlockSize(
      block,
      minWidth: minWidth,
      minHeight: minHeight,
    );
    final width = size.width * scale;
    final height = size.height * scale;
    final offset =
        point -
        TransformService.blockCenter(
          block,
          worldOrigin: worldOrigin,
          scale: scale,
          minWidth: minWidth,
          minHeight: minHeight,
        );
    final local = TransformService.rotate(offset, -block.rotation);
    return local.dx.abs() <= width / 2 && local.dy.abs() <= height / 2;
  }
}

/// Pure bounds calculations for groups, alignment, and fit-content behavior.
class BoundsService {
  const BoundsService._();

  static Rect axisAligned(Iterable<CanvasRenderable> blocks) {
    final items = blocks.toList(growable: false);
    if (items.isEmpty) return Rect.zero;
    var bounds = _blockRect(items.first);
    for (final block in items.skip(1)) {
      bounds = bounds.expandToInclude(_blockRect(block));
    }
    return bounds;
  }

  static Rect rotated(Iterable<CanvasRenderable> blocks) {
    final items = blocks.toList(growable: false);
    if (items.isEmpty) return Rect.zero;
    var bounds = rotatedBlock(items.first);
    for (final block in items.skip(1)) {
      bounds = bounds.expandToInclude(rotatedBlock(block));
    }
    return bounds;
  }

  static Rect _blockRect(CanvasRenderable block) =>
      Rect.fromLTWH(block.x, block.y, block.w, block.h);

  static Rect rotatedBlock(CanvasRenderable block) {
    final rect = _blockRect(block);
    final center = rect.center;
    final corners =
        <Offset>[
          rect.topLeft,
          rect.topRight,
          rect.bottomRight,
          rect.bottomLeft,
        ].map(
          (corner) =>
              center + TransformService.rotate(corner - center, block.rotation),
        );
    var bounds = Rect.fromPoints(corners.first, corners.first);
    for (final corner in corners.skip(1)) {
      bounds = bounds.expandToInclude(Rect.fromPoints(corner, corner));
    }
    return bounds;
  }
}

/// Pure grid snapping calculations.
class SnappingService {
  const SnappingService._();

  static double snapValue(double value, double gridSize) {
    final size = math.max(1, gridSize);
    return (value / size).roundToDouble() * size;
  }

  static Offset snapOffset(Offset value, BoardSettings board) => Offset(
    snapValue(value.dx, board.gridSize),
    snapValue(value.dy, board.gridSize),
  );
}
