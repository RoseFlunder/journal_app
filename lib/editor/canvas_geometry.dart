import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/entry.dart';

/// Pure world/screen geometry used by canvas interaction code.
class CanvasGeometry {
  const CanvasGeometry._();

  static Offset rotate(Offset point, double angle) {
    final cosine = math.cos(angle);
    final sine = math.sin(angle);
    return Offset(
      point.dx * cosine - point.dy * sine,
      point.dx * sine + point.dy * cosine,
    );
  }

  static Size effectiveBlockSize(
    ContentBlock block, {
    required double minWidth,
    required double minHeight,
  }) => Size(math.max(minWidth, block.w), math.max(minHeight, block.h));

  static Offset blockCenter(
    ContentBlock block, {
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
    final scaledSize = Size(size.width * scale, size.height * scale);
    return Offset(
          (block.x + worldOrigin.dx) * scale,
          (block.y + worldOrigin.dy) * scale,
        ) +
        Offset(scaledSize.width / 2, scaledSize.height / 2);
  }

  static bool containsBlock(
    Offset point,
    ContentBlock block, {
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
    final width = size.width * scale;
    final height = size.height * scale;
    final offset =
        point -
        blockCenter(
          block,
          worldOrigin: worldOrigin,
          scale: scale,
          minWidth: minWidth,
          minHeight: minHeight,
        );
    final local = rotate(offset, -block.rotation);
    return local.dx.abs() <= width / 2 && local.dy.abs() <= height / 2;
  }
}
