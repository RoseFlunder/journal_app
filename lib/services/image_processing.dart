import 'dart:typed_data';

import 'package:image/image.dart' as img;

class ProcessedImage {
  const ProcessedImage({
    required this.bytes,
    required this.mime,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final String mime;
  final int width;
  final int height;
}

abstract interface class ImageProcessingService {
  ProcessedImage process(Uint8List bytes);
}

class ImageProcessor implements ImageProcessingService {
  const ImageProcessor({this.maxSide = 1600, this.jpegQuality = 80});

  final int maxSide;
  final int jpegQuality;

  @override
  ProcessedImage process(Uint8List bytes) {
    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {
      throw const FormatException('The selected file is not a valid image.');
    }
    if (decoded == null) {
      throw const FormatException('The selected file is not a valid image.');
    }

    final scale =
        maxSide / decoded.width.clamp(decoded.height, double.infinity);
    final resized = scale < 1
        ? img.copyResize(
            decoded,
            width: (decoded.width * scale).round(),
            height: (decoded.height * scale).round(),
          )
        : decoded;
    return ProcessedImage(
      bytes: Uint8List.fromList(img.encodeJpg(resized, quality: jpegQuality)),
      mime: 'image/jpeg',
      width: resized.width,
      height: resized.height,
    );
  }
}
