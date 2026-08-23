import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class PickedImage {
  const PickedImage({required this.bytes, required this.mime});

  final Uint8List bytes;
  final String mime;
}

abstract class ImageSourceService {
  Future<PickedImage?> pickImage(BuildContext context);
}

class PlatformImageSource implements ImageSourceService {
  PlatformImageSource({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<PickedImage?> pickImage(BuildContext context) async {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.windows) {
      return _pickFile();
    }

    final source = await _pickMobileSource(context);
    if (source == null) return null;
    final file = await _picker.pickImage(source: source);
    if (file == null) return null;
    return PickedImage(bytes: await file.readAsBytes(), mime: _mime(file.name));
  }

  Future<PickedImage?> _pickFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.image,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    return PickedImage(bytes: bytes, mime: _mime(file.name));
  }

  Future<ImageSource?> _pickMobileSource(BuildContext context) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
  }

  String _mime(String name) {
    final extension = name.split('.').last.toLowerCase();
    return switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      _ => 'application/octet-stream',
    };
  }
}

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

class ImageProcessor {
  const ImageProcessor({this.maxSide = 1600, this.jpegQuality = 80});

  final int maxSide;
  final int jpegQuality;

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

    final scale = maxSide / decoded.width.clamp(decoded.height, double.infinity);
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