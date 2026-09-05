import 'dart:typed_data';

import 'package:image/image.dart' as img;

enum PhotoFrame { none, white, cream, black }

Uint8List applyPhotoFrame((Uint8List, PhotoFrame) input) {
  final (bytes, frame) = input;
  if (frame == PhotoFrame.none) return bytes;
  final photo = img.decodeImage(bytes);
  if (photo == null) throw const FormatException('Could not read the photo.');
  final color = switch (frame) {
    PhotoFrame.cream => img.ColorRgb8(247, 239, 224),
    PhotoFrame.black => img.ColorRgb8(35, 32, 29),
    _ => img.ColorRgb8(255, 255, 255),
  };
  final framed = img.copyExpandCanvas(
    photo,
    padding: (photo.width.clamp(1, photo.height) * 0.045).round().clamp(1, 100),
    backgroundColor: color,
  );
  return Uint8List.fromList(img.encodePng(framed));
}
