import 'package:flutter/foundation.dart';

import '../../../../services/image_source.dart';
import '../../../../services/image_processing.dart';
import '../../../../services/repositories.dart';

/// Coordinates image processing and asset persistence for the editor feature.
/// The view remains responsible only for platform picking and presentation.
class ImageInsertionUseCase {
  const ImageInsertionUseCase({required this.assets, required this.processor});

  final AssetRepository assets;
  final ImageProcessingService processor;

  Future<ProcessedImage> prepare(PickedImage picked) =>
      compute(processor.process, picked.bytes);

  Future<({ProcessedImage image, String assetId})> processAndStore({
    required PickedImage picked,
  }) async {
    final image = await prepare(picked);
    final descriptor = await assets.putAsset(
      AssetKind.image,
      image.mime,
      image.bytes,
    );
    return (image: image, assetId: descriptor.id);
  }
}
