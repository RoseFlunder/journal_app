import 'dart:ui';

import 'package:perfect_freehand/perfect_freehand.dart';

import '../../../../models/canvas.dart';

/// One page-local sample in a freehand stroke.
///
/// Pressure is optional so journals created before pressure capture was added
/// continue to render using velocity-simulated pressure.
class InkStrokePoint {
  const InkStrokePoint(this.position, {this.pressure});

  final Offset position;
  final double? pressure;

  factory InkStrokePoint.fromJson(Map<String, dynamic> json) => InkStrokePoint(
    Offset(
      (json['x'] as num?)?.toDouble() ?? 0,
      (json['y'] as num?)?.toDouble() ?? 0,
    ),
    pressure: (json['p'] as num?)?.toDouble(),
  );

  Map<String, double> toJson() => <String, double>{
    'x': position.dx,
    'y': position.dy,
    'p': ?pressure,
  };

  InkStrokePoint translate(Offset delta) =>
      InkStrokePoint(position + delta, pressure: pressure);

  InkStrokePoint scale(double x, double y) => InkStrokePoint(
    Offset(position.dx * x, position.dy * y),
    pressure: pressure,
  );
}

/// Turns pointer samples into a smooth, pressure-sensitive filled outline.
abstract final class InkStrokeRenderer {
  static void paint(
    Canvas canvas, {
    required List<InkStrokePoint> points,
    required Color color,
    required double width,
    required double opacity,
    required InkStrokeType strokeType,
    bool isComplete = true,
  }) {
    if (points.length < 2 || width <= 0 || opacity <= 0) return;

    final usesRealPressure = points.every((point) => point.pressure != null);
    final outline = getStroke(
      <PointVector>[
        for (final point in points)
          PointVector(point.position.dx, point.position.dy, point.pressure),
      ],
      options: _options(
        strokeType,
        width: width * strokeType.widthMultiplier,
        simulatePressure: !usesRealPressure,
        isComplete: isComplete,
      ),
    );
    if (outline.isEmpty) return;

    canvas.drawPath(
      _smoothClosedPath(outline),
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.fill
        ..color = color.withValues(
          alpha: (opacity * strokeType.opacityMultiplier).clamp(0.0, 1.0),
        ),
    );
  }

  static StrokeOptions _options(
    InkStrokeType strokeType, {
    required double width,
    required bool simulatePressure,
    required bool isComplete,
  }) => switch (strokeType) {
    InkStrokeType.pen => StrokeOptions(
      size: width,
      thinning: .45,
      smoothing: .7,
      streamline: .48,
      simulatePressure: simulatePressure,
      isComplete: isComplete,
    ),
    InkStrokeType.brush => StrokeOptions(
      size: width,
      thinning: .78,
      smoothing: .68,
      streamline: .42,
      simulatePressure: simulatePressure,
      start: StrokeEndOptions.start(customTaper: width * .8),
      end: StrokeEndOptions.end(customTaper: width * 1.6),
      isComplete: isComplete,
    ),
    InkStrokeType.marker => StrokeOptions(
      size: width,
      thinning: 0,
      smoothing: .82,
      streamline: .55,
      simulatePressure: false,
      start: StrokeEndOptions.start(cap: false),
      end: StrokeEndOptions.end(cap: false),
      isComplete: isComplete,
    ),
    InkStrokeType.highlighter => StrokeOptions(
      size: width,
      thinning: 0,
      smoothing: .88,
      streamline: .62,
      simulatePressure: false,
      start: StrokeEndOptions.start(cap: false),
      end: StrokeEndOptions.end(cap: false),
      isComplete: isComplete,
    ),
  };

  static Path _smoothClosedPath(List<Offset> outline) {
    final path = Path()..moveTo(outline.first.dx, outline.first.dy);
    for (var index = 0; index < outline.length - 1; index++) {
      final point = outline[index];
      final next = outline[index + 1];
      path.quadraticBezierTo(
        point.dx,
        point.dy,
        (point.dx + next.dx) / 2,
        (point.dy + next.dy) / 2,
      );
    }
    return path
      ..lineTo(outline.last.dx, outline.last.dy)
      ..close();
  }
}
