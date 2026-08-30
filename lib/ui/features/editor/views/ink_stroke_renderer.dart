import 'dart:math' as math;
import 'dart:ui';

import '../../../../models/canvas.dart';

/// Paints the deterministic brush presets used by both the editor and the
/// brush gallery previews. Keeping the effects here means a selected brush
/// looks the same before and after a stroke is committed.
abstract final class InkStrokeRenderer {
  static void paint(
    Canvas canvas, {
    required List<Offset> points,
    required Color color,
    required double width,
    required double opacity,
    required InkStrokeType strokeType,
  }) {
    if (points.length < 2 || width <= 0 || opacity <= 0) return;
    final baseWidth = width * strokeType.widthMultiplier;
    final alpha = (opacity * strokeType.opacityMultiplier).clamp(0.0, 1.0);
    switch (strokeType) {
      case InkStrokeType.pencil:
        _drawPencil(canvas, points, color, baseWidth, alpha);
      case InkStrokeType.pen:
        _drawPath(canvas, points, color, baseWidth, alpha);
      case InkStrokeType.marker:
        _drawMarker(canvas, points, color, baseWidth, alpha);
      case InkStrokeType.brush:
        _drawVariable(canvas, points, color, baseWidth, alpha, .62, 1.32);
      case InkStrokeType.calligraphyPen:
        _drawVariable(
          canvas,
          points,
          color,
          baseWidth,
          alpha,
          .42,
          1.12,
          cap: StrokeCap.butt,
          join: StrokeJoin.bevel,
        );
      case InkStrokeType.calligraphyBrush:
        _drawVariable(
          canvas,
          points,
          color,
          baseWidth,
          alpha,
          .55,
          1.55,
          cap: StrokeCap.butt,
          join: StrokeJoin.bevel,
        );
        _drawBristles(canvas, points, color, baseWidth, alpha);
      case InkStrokeType.airbrush:
        _drawAirbrush(canvas, points, color, baseWidth, alpha);
      case InkStrokeType.oilBrush:
        _drawOil(canvas, points, color, baseWidth, alpha);
      case InkStrokeType.crayon:
        _drawCrayon(canvas, points, color, baseWidth, alpha);
      case InkStrokeType.highlighter:
        _drawMarker(canvas, points, color, baseWidth, alpha, opacityScale: .72);
    }
  }

  static Path _path(List<Offset> points, [double dx = 0, double dy = 0]) {
    final path = Path()..moveTo(points.first.dx + dx, points.first.dy + dy);
    for (var index = 1; index < points.length; index++) {
      path.lineTo(points[index].dx + dx, points[index].dy + dy);
    }
    return path;
  }

  static Paint _paint(
    Color color,
    double width,
    double alpha, {
    StrokeCap cap = StrokeCap.round,
    StrokeJoin join = StrokeJoin.round,
  }) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = cap
    ..strokeJoin = join
    ..strokeWidth = width
    ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0));

  static void _drawPath(
    Canvas canvas,
    List<Offset> points,
    Color color,
    double width,
    double alpha, {
    StrokeCap cap = StrokeCap.round,
    StrokeJoin join = StrokeJoin.round,
    double dx = 0,
    double dy = 0,
  }) {
    canvas.drawPath(
      _path(points, dx, dy),
      _paint(color, width, alpha, cap: cap, join: join),
    );
  }

  static void _drawMarker(
    Canvas canvas,
    List<Offset> points,
    Color color,
    double width,
    double alpha, {
    double opacityScale = 1,
  }) {
    // A faint undercoat and a flatter center give markers the broad, slightly
    // translucent overlap visible in Paint without requiring a texture asset.
    _drawPath(
      canvas,
      points,
      color,
      width * 1.14,
      alpha * .42 * opacityScale,
      cap: StrokeCap.square,
    );
    _drawPath(
      canvas,
      points,
      color,
      width * .92,
      alpha * opacityScale,
      cap: StrokeCap.square,
    );
  }

  static void _drawVariable(
    Canvas canvas,
    List<Offset> points,
    Color color,
    double width,
    double alpha,
    double minimum,
    double maximum, {
    StrokeCap cap = StrokeCap.round,
    StrokeJoin join = StrokeJoin.round,
  }) {
    final count = points.length - 1;
    for (var index = 0; index < count; index++) {
      final factor = minimum + (maximum - minimum) *
          (.5 + .5 * math.sin((index / math.max(1, count - 1)) * math.pi));
      canvas.drawLine(
        points[index],
        points[index + 1],
        _paint(color, width * factor, alpha, cap: cap, join: join),
      );
    }
  }

  static void _drawPencil(
    Canvas canvas,
    List<Offset> points,
    Color color,
    double width,
    double alpha,
  ) {
    _drawPath(canvas, points, color, width * .72, alpha);
    final rough = <Offset>[
      for (var index = 0; index < points.length; index++)
        points[index] +
            Offset(
              math.sin(index * 2.17) * width * .18,
              math.cos(index * 1.73) * width * .18,
            ),
    ];
    _drawPath(canvas, rough, color, width * .25, alpha * .48);
  }

  static void _drawBristles(
    Canvas canvas,
    List<Offset> points,
    Color color,
    double width,
    double alpha,
  ) {
    for (var strand = -1; strand <= 1; strand++) {
      final offset = width * .2 * strand;
      _drawPath(canvas, points, color, width * .12, alpha * .42, dy: offset);
    }
  }

  static void _drawAirbrush(
    Canvas canvas,
    List<Offset> points,
    Color color,
    double width,
    double alpha,
  ) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * 1.25)
      ..color = color.withValues(alpha: (alpha * .22).clamp(0.0, 1.0));
    final step = math.max(1, points.length ~/ 60);
    for (var index = 0; index < points.length; index += step) {
      canvas.drawCircle(points[index], width * .72, paint);
    }
    _drawPath(canvas, points, color, width * .26, alpha * .42);
  }

  static void _drawOil(
    Canvas canvas,
    List<Offset> points,
    Color color,
    double width,
    double alpha,
  ) {
    _drawPath(canvas, points, color, width * 1.05, alpha * .52);
    _drawPath(canvas, points, color, width * .72, alpha * .78, dy: width * .18);
    _drawPath(canvas, points, color, width * .34, alpha, dy: -width * .2);
  }

  static void _drawCrayon(
    Canvas canvas,
    List<Offset> points,
    Color color,
    double width,
    double alpha,
  ) {
    _drawPath(canvas, points, color, width * .78, alpha * .72);
    final speckPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: (alpha * .45).clamp(0.0, 1.0));
    final stride = math.max(1, points.length ~/ 45);
    for (var index = 0; index < points.length; index += stride) {
      final point = points[index];
      final jitter = Offset(
        math.sin(index * 3.1) * width * .48,
        math.cos(index * 2.4) * width * .48,
      );
      canvas.drawCircle(point + jitter, width * .08, speckPaint);
    }
  }
}
