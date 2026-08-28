import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

class PickedImage {
  const PickedImage({required this.bytes, required this.mime});

  final Uint8List bytes;
  final String mime;
}

/// A platform-neutral origin selected by the presentation layer.
enum ImagePickOrigin { file, gallery, camera }

/// Reads image bytes from a platform source without rendering any UI.
abstract interface class ImageSourceService {
  Set<ImagePickOrigin> get supportedOrigins;

  Future<PickedImage?> pickImage(ImagePickOrigin origin);
}

class PlatformImageSource implements ImageSourceService {
  PlatformImageSource({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Set<ImagePickOrigin> get supportedOrigins =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.windows
      ? const {ImagePickOrigin.file}
      : const {ImagePickOrigin.gallery, ImagePickOrigin.camera};

  @override
  Future<PickedImage?> pickImage(ImagePickOrigin origin) async {
    if (!supportedOrigins.contains(origin)) {
      throw UnsupportedError('Image source $origin is not available here.');
    }
    if (origin == ImagePickOrigin.file) return _pickFile();
    final file = await _picker.pickImage(
      source: origin == ImagePickOrigin.gallery
          ? ImageSource.gallery
          : ImageSource.camera,
    );
    if (file == null) return null;
    return PickedImage(bytes: await file.readAsBytes(), mime: _mime(file.name));
  }

  Future<PickedImage?> _pickFile() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    return PickedImage(bytes: bytes, mime: _mime(file.name));
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
