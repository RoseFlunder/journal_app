import 'package:flutter/foundation.dart';

/// A compact, non-destructive image appearance preset.
@immutable
class ImageFilterPreset {
  const ImageFilterPreset({
    required this.id,
    required this.label,
    required this.brightness,
    required this.contrast,
    required this.saturation,
    required this.warmth,
  });

  final String id;
  final String label;
  final double brightness;
  final double contrast;
  final double saturation;
  final double warmth;

  static const original = ImageFilterPreset(
    id: 'original',
    label: 'Original',
    brightness: 0,
    contrast: 0,
    saturation: 1,
    warmth: 0,
  );

  static const soft = ImageFilterPreset(
    id: 'soft',
    label: 'Soft',
    brightness: 0.08,
    contrast: -0.08,
    saturation: 0.90,
    warmth: 0.08,
  );

  static const warm = ImageFilterPreset(
    id: 'warm',
    label: 'Warm',
    brightness: 0.03,
    contrast: 0.05,
    saturation: 1.08,
    warmth: 0.35,
  );

  static const cool = ImageFilterPreset(
    id: 'cool',
    label: 'Cool',
    brightness: 0,
    contrast: 0.05,
    saturation: 0.95,
    warmth: -0.35,
  );

  static const vintage = ImageFilterPreset(
    id: 'vintage',
    label: 'Vintage',
    brightness: 0.04,
    contrast: -0.08,
    saturation: 0.72,
    warmth: 0.28,
  );

  static const mono = ImageFilterPreset(
    id: 'mono',
    label: 'Mono',
    brightness: 0.02,
    contrast: 0.05,
    saturation: 0,
    warmth: 0,
  );

  static const values = <ImageFilterPreset>[
    original,
    soft,
    warm,
    cool,
    vintage,
    mono,
  ];

  bool matches({
    required double brightness,
    required double contrast,
    required double saturation,
    required double warmth,
  }) =>
      (this.brightness - brightness).abs() < 0.001 &&
      (this.contrast - contrast).abs() < 0.001 &&
      (this.saturation - saturation).abs() < 0.001 &&
      (this.warmth - warmth).abs() < 0.001;
}
