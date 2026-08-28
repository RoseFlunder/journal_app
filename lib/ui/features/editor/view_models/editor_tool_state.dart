import 'dart:ui';

import '../../../../models/canvas.dart';

/// Immutable transient settings used while creating vector ink.
class InkSettings {
  const InkSettings({
    this.colorValue = 0xFF3B3226,
    this.opacity = 1,
    this.width = 1.8,
    this.strokeType = InkStrokeType.pen,
  });

  final int colorValue;
  final double opacity;
  final double width;
  final InkStrokeType strokeType;

  int get pickerValue =>
      Color(colorValue)
          .withValues(alpha: opacity.clamp(0.0, 1.0).toDouble())
          .toARGB32();

  InkSettings copyWith({
    int? colorValue,
    double? opacity,
    double? width,
    InkStrokeType? strokeType,
  }) => InkSettings(
    colorValue: colorValue ?? this.colorValue,
    opacity: opacity ?? this.opacity,
    width: width ?? this.width,
    strokeType: strokeType ?? this.strokeType,
  );

  @override
  bool operator ==(Object other) =>
      other is InkSettings &&
      other.colorValue == colorValue &&
      other.opacity == opacity &&
      other.width == width &&
      other.strokeType == strokeType;

  @override
  int get hashCode => Object.hash(colorValue, opacity, width, strokeType);
}
