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

/// The botanical scrapbook sticker sheet shipped with Cozy Bloom Journal.
///
/// The source sheet is split into transparent PNGs so the picker can offer
/// every sticker independently while preserving the original proportions.
class StickerCatalog {
  const StickerCatalog._();

  static const _root = 'assets/stickers/extracted';

  static const definitions = <StickerDefinition>[
    StickerDefinition(id: 'bouquet', label: 'Bouquet', assetPath: '$_root/sticker_01.png', aspectRatio: 0.719, defaultSize: Size(26, 36)),
    StickerDefinition(id: 'flower-books', label: 'Flower books', assetPath: '$_root/sticker_02.png', aspectRatio: 1.208, defaultSize: Size(36, 30)),
    StickerDefinition(id: 'butterfly', label: 'Butterfly', assetPath: '$_root/sticker_03.png', aspectRatio: 1.073, defaultSize: Size(34, 32)),
    StickerDefinition(id: 'take-it-easy', label: 'Take it easy', assetPath: '$_root/sticker_04.png', aspectRatio: 0.813, defaultSize: Size(29, 36)),
    StickerDefinition(id: 'coffee-mug', label: 'Coffee mug', assetPath: '$_root/sticker_05.png', aspectRatio: 1.181, defaultSize: Size(36, 30)),
    StickerDefinition(id: 'gingham-heart', label: 'Gingham heart', assetPath: '$_root/sticker_06.png', aspectRatio: 1.063, defaultSize: Size(35, 33)),
    StickerDefinition(id: 'open-journal', label: 'Open journal', assetPath: '$_root/sticker_07.png', aspectRatio: 1.293, defaultSize: Size(36, 28)),
    StickerDefinition(id: 'bird', label: 'Bird', assetPath: '$_root/sticker_08.png', aspectRatio: 1.086, defaultSize: Size(36, 33)),
    StickerDefinition(id: 'lavender', label: 'Lavender', assetPath: '$_root/sticker_09.png', aspectRatio: 0.607, defaultSize: Size(22, 36)),
    StickerDefinition(id: 'postage-stamp', label: 'Postage stamp', assetPath: '$_root/sticker_10.png', aspectRatio: 0.778, defaultSize: Size(28, 36)),
    StickerDefinition(id: 'daisy', label: 'Daisy', assetPath: '$_root/sticker_11.png', aspectRatio: 1.074, defaultSize: Size(36, 34)),
    StickerDefinition(id: 'tulip', label: 'Tulip', assetPath: '$_root/sticker_12.png', aspectRatio: 0.683, defaultSize: Size(25, 36)),
    StickerDefinition(id: 'pink-bow', label: 'Pink bow', assetPath: '$_root/sticker_13.png', aspectRatio: 1.084, defaultSize: Size(36, 33)),
    StickerDefinition(id: 'just-breathe', label: 'Just breathe', assetPath: '$_root/sticker_14.png', aspectRatio: 1.304, defaultSize: Size(36, 28)),
    StickerDefinition(id: 'large-bouquet', label: 'Large bouquet', assetPath: '$_root/sticker_15.png', aspectRatio: 0.798, defaultSize: Size(29, 36)),
    StickerDefinition(id: 'leafy-branch', label: 'Leafy branch', assetPath: '$_root/sticker_16.png', aspectRatio: 0.584, defaultSize: Size(21, 36)),
    StickerDefinition(id: 'pink-flower', label: 'Pink flower', assetPath: '$_root/sticker_17.png', aspectRatio: 1.107, defaultSize: Size(36, 32)),
    StickerDefinition(id: 'golden-butterfly', label: 'Golden butterfly', assetPath: '$_root/sticker_18.png', aspectRatio: 1.216, defaultSize: Size(36, 33)),
    StickerDefinition(id: 'flower-tag', label: 'Flower tag', assetPath: '$_root/sticker_19.png', aspectRatio: 0.467, defaultSize: Size(18, 36)),
    StickerDefinition(id: 'sparkle-one', label: 'Sparkle', assetPath: '$_root/sticker_20.png', aspectRatio: 0.946, defaultSize: Size(34, 36)),
    StickerDefinition(id: 'sparkle-two', label: 'Small sparkle', assetPath: '$_root/sticker_21.png', aspectRatio: 0.893, defaultSize: Size(32, 36)),
    StickerDefinition(id: 'sparkle-three', label: 'Tiny sparkle', assetPath: '$_root/sticker_22.png', aspectRatio: 0.914, defaultSize: Size(33, 36)),
    StickerDefinition(id: 'tea-cup', label: 'Tea cup', assetPath: '$_root/sticker_23.png', aspectRatio: 1.326, defaultSize: Size(36, 27)),
    StickerDefinition(id: 'red-heart', label: 'Red heart', assetPath: '$_root/sticker_24.png', aspectRatio: 0.84, defaultSize: Size(30, 36)),
    StickerDefinition(id: 'cookie', label: 'Cookie', assetPath: '$_root/sticker_25.png', aspectRatio: 1.122, defaultSize: Size(36, 32)),
    StickerDefinition(id: 'little-joys', label: 'Little joys', assetPath: '$_root/sticker_26.png', aspectRatio: 1.338, defaultSize: Size(36, 27)),
    StickerDefinition(id: 'leafy-sprig', label: 'Leafy sprig', assetPath: '$_root/sticker_27.png', aspectRatio: 0.595, defaultSize: Size(21, 36)),
    StickerDefinition(id: 'cookie-crumbs', label: 'Cookie crumbs', assetPath: '$_root/sticker_28.png', aspectRatio: 1.059, defaultSize: Size(36, 34)),
    StickerDefinition(id: 'small-daisy', label: 'Small daisy', assetPath: '$_root/sticker_29.png', aspectRatio: 0.975, defaultSize: Size(35, 36)),
    StickerDefinition(id: 'takeaway-coffee', label: 'Takeaway coffee', assetPath: '$_root/sticker_30.png', aspectRatio: 0.73, defaultSize: Size(26, 36)),
    StickerDefinition(id: 'envelope', label: 'Flower envelope', assetPath: '$_root/sticker_31.png', aspectRatio: 1.195, defaultSize: Size(36, 30)),
    StickerDefinition(id: 'framed-photo', label: 'Framed photo', assetPath: '$_root/sticker_32.png', aspectRatio: 0.899, defaultSize: Size(32, 36)),
    StickerDefinition(id: 'branch', label: 'Branch', assetPath: '$_root/sticker_33.png', aspectRatio: 0.588, defaultSize: Size(21, 36)),
    StickerDefinition(id: 'coffee-books', label: 'Coffee and books', assetPath: '$_root/sticker_34.png', aspectRatio: 1.274, defaultSize: Size(36, 28)),
    StickerDefinition(id: 'tulips-vase', label: 'Tulips in vase', assetPath: '$_root/sticker_35.png', aspectRatio: 0.532, defaultSize: Size(19, 36)),
    StickerDefinition(id: 'purple-heart', label: 'Purple heart', assetPath: '$_root/sticker_36.png', aspectRatio: 1.035, defaultSize: Size(36, 35)),
    StickerDefinition(id: 'small-pink-flower', label: 'Small pink flower', assetPath: '$_root/sticker_37.png', aspectRatio: 1.066, defaultSize: Size(36, 34)),
    StickerDefinition(id: 'bloom', label: 'Bloom', assetPath: '$_root/sticker_38.png', aspectRatio: 1.293, defaultSize: Size(36, 28)),
    StickerDefinition(id: 'flower-sprig', label: 'Flower sprig', assetPath: '$_root/sticker_39.png', aspectRatio: 0.573, defaultSize: Size(21, 36)),
    StickerDefinition(id: 'green-bow', label: 'Green bow', assetPath: '$_root/sticker_40.png', aspectRatio: 1.109, defaultSize: Size(36, 32)),
    StickerDefinition(id: 'collect-moments', label: 'Collect beautiful moments', assetPath: '$_root/sticker_41.png', aspectRatio: 1.244, defaultSize: Size(36, 29)),
    StickerDefinition(id: 'pink-flower-two', label: 'Pink flower', assetPath: '$_root/sticker_42.png', aspectRatio: 1.018, defaultSize: Size(36, 35)),
    StickerDefinition(id: 'purple-cloud', label: 'Purple cloud', assetPath: '$_root/sticker_43.png', aspectRatio: 1.267, defaultSize: Size(36, 28)),
    StickerDefinition(id: 'camera', label: 'Flower camera', assetPath: '$_root/sticker_44.png', aspectRatio: 1.223, defaultSize: Size(36, 29)),
    StickerDefinition(id: 'flowering-branch', label: 'Flowering branch', assetPath: '$_root/sticker_45.png', aspectRatio: 0.843, defaultSize: Size(30, 36)),
    StickerDefinition(id: 'paper-notes', label: 'Paper notes', assetPath: '$_root/sticker_46.png', aspectRatio: 1.369, defaultSize: Size(36, 26)),
    StickerDefinition(id: 'decorative-ticket', label: 'Decorative ticket', assetPath: '$_root/sticker_47.png', aspectRatio: 1.536, defaultSize: Size(36, 23)),
    StickerDefinition(id: 'green-heart', label: 'Green heart', assetPath: '$_root/sticker_48.png', aspectRatio: 1.116, defaultSize: Size(36, 32)),
    StickerDefinition(id: 'paperclip', label: 'Paperclip', assetPath: '$_root/sticker_49.png', aspectRatio: 0.705, defaultSize: Size(25, 36)),
  ];

  static StickerDefinition? byId(String? id) {
    if (id == null) return null;
    for (final sticker in definitions) {
      if (sticker.id == id) return sticker;
    }
    return null;
  }
}
