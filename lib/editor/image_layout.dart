import 'dart:math' as math;
import 'dart:ui';

Size imageBlockSize(
  int width,
  int height, {
  double maxWidth = 64,
  double maxHeight = 48,
}) {
  if (width <= 0 || height <= 0) return Size(maxWidth, maxHeight);
  final scale = math.min(maxWidth / width, maxHeight / height);
  return Size(width * scale, height * scale);
}
