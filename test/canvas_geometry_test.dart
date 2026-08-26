import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/editor/canvas_geometry.dart';
import 'package:journal_app/models/entry.dart';

void main() {
  test('rotates points without depending on widget state', () {
    final result = CanvasGeometry.rotate(const Offset(10, 0), math.pi / 2);

    expect(result.dx, closeTo(0, 0.0001));
    expect(result.dy, closeTo(10, 0.0001));
  });

  test('hit tests the local geometry of a rotated block', () {
    final block = ContentBlock(
      id: 'rotated',
      type: BlockType.text,
      x: 10,
      y: 20,
      w: 40,
      h: 20,
      rotation: math.pi / 2,
    );

    expect(
      CanvasGeometry.containsBlock(
        const Offset(30, 40),
        block,
        worldOrigin: Offset.zero,
        scale: 1,
        minWidth: 1,
        minHeight: 1,
      ),
      isTrue,
    );
    expect(
      CanvasGeometry.containsBlock(
        const Offset(55, 40),
        block,
        worldOrigin: Offset.zero,
        scale: 1,
        minWidth: 1,
        minHeight: 1,
      ),
      isFalse,
    );
  });
}
