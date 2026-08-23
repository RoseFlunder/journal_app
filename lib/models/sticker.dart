import 'package:flutter/material.dart';

/// Metadata for a bundled sticker. The id is persisted with a content block;
/// the asset path is resolved from this catalog at render time.
class StickerDefinition {
  const StickerDefinition({
    required this.id,
    required this.label,
    required this.assetPath,
    required this.aspectRatio,
    required this.defaultSize,
  });

  final String id;
  final String label;
  final String assetPath;
  final double aspectRatio;
  final Size defaultSize;
}

/// The first small sticker pack shipped with Cozy Bloom Journal.
class StickerCatalog {
  const StickerCatalog._();

  static const definitions = <StickerDefinition>[
    StickerDefinition(
      id: 'daisy',
      label: 'Daisy',
      assetPath: 'assets/stickers/daisy.png',
      aspectRatio: 1,
      defaultSize: Size(28, 28),
    ),
    StickerDefinition(
      id: 'butterfly',
      label: 'Butterfly',
      assetPath: 'assets/stickers/butterfly.png',
      aspectRatio: 1.25,
      defaultSize: Size(32, 26),
    ),
  ];

  static StickerDefinition? byId(String? id) {
    if (id == null) return null;
    for (final sticker in definitions) {
      if (sticker.id == id) return sticker;
    }
    return null;
  }
}
