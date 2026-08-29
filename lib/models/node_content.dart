import 'dart:collection';

import 'canvas.dart';

/// Typed immutable payloads used by the permanent document model. The
/// compatibility constructor on [CanvasNode] still accepts legacy maps while
/// callers migrate to these values; persistence never relies on those maps.
sealed class CanvasNodeContent {
  const CanvasNodeContent();

  BlockType get type;

  Map<String, dynamic> toPayload();

  factory CanvasNodeContent.fromLegacy(BlockType type, Map<String, dynamic> raw) =>
      switch (type) {
        BlockType.text => TextNodeContent.fromLegacy(raw),
        BlockType.image => ImageNodeContent.fromLegacy(raw),
        BlockType.sticker => StickerNodeContent.fromLegacy(raw),
        BlockType.ink => InkNodeContent.fromLegacy(raw),
        BlockType.shape => ShapeNodeContent.fromLegacy(raw),
        BlockType.group => const GroupNodeContent(),
      };
}

class TextNodeContent extends CanvasNodeContent {
  TextNodeContent({
    this.text = '',
    this.fontSize = 21,
    this.fontFamily,
    this.textColorValue,
    this.bold = false,
    this.italic = false,
    List<dynamic>? richTextDelta,
  }) : richTextDelta = richTextDelta == null
           ? null
           : List<dynamic>.unmodifiable(
               richTextDelta.map(_freezeValue),
             );

  final String text;
  final double fontSize;
  final String? fontFamily;
  final int? textColorValue;
  final bool bold;
  final bool italic;
  final List<dynamic>? richTextDelta;

  /// Plain text derived from Delta inserts. Delta remains the authoritative
  /// representation when present.
  String get plainText {
    if (richTextDelta == null) return text;
    final buffer = StringBuffer();
    for (final operation in richTextDelta!) {
      if (operation is Map && operation['insert'] is String) {
        buffer.write(operation['insert']);
      }
    }
    final value = buffer.toString();
    return value.endsWith('\n') ? value.substring(0, value.length - 1) : value;
  }

  @override
  BlockType get type => BlockType.text;

  factory TextNodeContent.fromLegacy(Map<String, dynamic> raw) =>
      TextNodeContent(
        text: raw['text'] as String? ?? '',
        fontSize: (raw['fontSize'] as num?)?.toDouble() ?? 21,
        fontFamily: raw['fontFamily'] as String?,
        textColorValue: (raw['textColorValue'] as num?)?.toInt(),
        bold: raw['bold'] as bool? ?? false,
        italic: raw['italic'] as bool? ?? false,
        richTextDelta: raw['richTextDelta'] is List
            ? List<dynamic>.unmodifiable(raw['richTextDelta'] as List)
            : null,
      );

  @override
  Map<String, dynamic> toPayload() => <String, dynamic>{
        'text': text,
        'fontSize': fontSize,
        'fontFamily': fontFamily,
        'textColorValue': textColorValue,
        'bold': bold,
        'italic': italic,
        'richTextDelta': richTextDelta,
      };
}

class ImageNodeContent extends CanvasNodeContent {
  ImageNodeContent({
    this.assetId,
    Map<String, double>? crop,
    this.flipX = false,
    this.flipY = false,
    this.imageMask = 'rectangle',
    this.cornerRadius = 0,
    this.frameColorValue,
    this.frameWidth = 0,
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 1,
    this.warmth = 0,
  }) : crop = crop == null
           ? null
           : UnmodifiableMapView<String, double>(Map<String, double>.from(crop));

  final String? assetId;
  final Map<String, double>? crop;
  final bool flipX;
  final bool flipY;
  final String imageMask;
  final double cornerRadius;
  final int? frameColorValue;
  final double frameWidth;
  final double brightness;
  final double contrast;
  final double saturation;
  final double warmth;

  @override
  BlockType get type => BlockType.image;

  factory ImageNodeContent.fromLegacy(Map<String, dynamic> raw) =>
      ImageNodeContent(
        assetId: raw['assetId'] as String?,
        crop: _crop(raw['crop']),
        flipX: raw['flipX'] as bool? ?? false,
        flipY: raw['flipY'] as bool? ?? false,
        imageMask: raw['imageMask'] as String? ?? 'rectangle',
        cornerRadius: (raw['cornerRadius'] as num?)?.toDouble() ?? 0,
        frameColorValue: (raw['frameColorValue'] as num?)?.toInt(),
        frameWidth: (raw['frameWidth'] as num?)?.toDouble() ?? 0,
        brightness: (raw['brightness'] as num?)?.toDouble() ?? 0,
        contrast: (raw['contrast'] as num?)?.toDouble() ?? 0,
        saturation: (raw['saturation'] as num?)?.toDouble() ?? 1,
        warmth: (raw['warmth'] as num?)?.toDouble() ?? 0,
      );

  @override
  Map<String, dynamic> toPayload() => <String, dynamic>{
        'assetId': assetId,
        'crop': crop,
        'flipX': flipX,
        'flipY': flipY,
        'imageMask': imageMask,
        'cornerRadius': cornerRadius,
        'frameColorValue': frameColorValue,
        'frameWidth': frameWidth,
        'brightness': brightness,
        'contrast': contrast,
        'saturation': saturation,
        'warmth': warmth,
      };
}

class StickerNodeContent extends ImageNodeContent {
  // The explicit forwarding keeps the typed visual defaults visible in the
  // public constructor instead of hiding them behind generated parameters.
  // ignore: use_super_parameters
  StickerNodeContent({
    this.stickerId,
    String? assetId,
    Map<String, double>? crop,
    bool flipX = false,
    bool flipY = false,
    String imageMask = 'rectangle',
    double cornerRadius = 0,
    int? frameColorValue,
    double frameWidth = 0,
    double brightness = 0,
    double contrast = 0,
    double saturation = 1,
    double warmth = 0,
  }) : super(
         assetId: assetId,
         crop: crop,
         flipX: flipX,
         flipY: flipY,
         imageMask: imageMask,
         cornerRadius: cornerRadius,
         frameColorValue: frameColorValue,
         frameWidth: frameWidth,
         brightness: brightness,
         contrast: contrast,
         saturation: saturation,
         warmth: warmth,
       );

  final String? stickerId;

  @override
  BlockType get type => BlockType.sticker;

  factory StickerNodeContent.fromLegacy(Map<String, dynamic> raw) =>
      StickerNodeContent(
        stickerId: raw['stickerId'] as String?,
        assetId: raw['assetId'] as String?,
        crop: _crop(raw['crop']),
        flipX: raw['flipX'] as bool? ?? false,
        flipY: raw['flipY'] as bool? ?? false,
        imageMask: raw['imageMask'] as String? ?? 'rectangle',
        cornerRadius: (raw['cornerRadius'] as num?)?.toDouble() ?? 0,
        frameColorValue: (raw['frameColorValue'] as num?)?.toInt(),
        frameWidth: (raw['frameWidth'] as num?)?.toDouble() ?? 0,
        brightness: (raw['brightness'] as num?)?.toDouble() ?? 0,
        contrast: (raw['contrast'] as num?)?.toDouble() ?? 0,
        saturation: (raw['saturation'] as num?)?.toDouble() ?? 1,
        warmth: (raw['warmth'] as num?)?.toDouble() ?? 0,
      );

  @override
  Map<String, dynamic> toPayload() => <String, dynamic>{
        ...super.toPayload(),
        'stickerId': stickerId,
      };
}

class InkNodeContent extends CanvasNodeContent {
  InkNodeContent({
    this.strokeColorValue,
    this.strokeWidth = 1,
    this.strokeType = 'pen',
    Iterable<Map<String, dynamic>> inkPoints = const [],
  }) : inkPoints = List<Map<String, dynamic>>.unmodifiable(
         inkPoints.map(
           (point) => Map<String, dynamic>.unmodifiable(
             <String, dynamic>{
               for (final entry in point.entries)
                 entry.key: _freezeValue(entry.value),
             },
           ),
         ),
       );

  final int? strokeColorValue;
  final double strokeWidth;
  final String strokeType;
  final List<Map<String, dynamic>> inkPoints;

  @override
  BlockType get type => BlockType.ink;

  factory InkNodeContent.fromLegacy(Map<String, dynamic> raw) => InkNodeContent(
        strokeColorValue: (raw['strokeColorValue'] as num?)?.toInt(),
        strokeWidth: (raw['strokeWidth'] as num?)?.toDouble() ?? 1,
        strokeType: raw['strokeType'] as String? ?? 'pen',
        inkPoints: raw['inkPoints'] is List
            ? List<Map<String, dynamic>>.unmodifiable(
                (raw['inkPoints'] as List)
                    .whereType<Map<Object?, Object?>>()
                    .map((point) => Map<String, dynamic>.from(point)),
              )
            : const [],
      );

  @override
  Map<String, dynamic> toPayload() => <String, dynamic>{
        'strokeColorValue': strokeColorValue,
        'strokeWidth': strokeWidth,
        'strokeType': strokeType,
        'inkPoints': inkPoints,
      };
}

class ShapeNodeContent extends CanvasNodeContent {
  const ShapeNodeContent({
    this.shape = 'rectangle',
    this.strokeColorValue,
    this.fillColorValue,
    this.strokeWidth = 1,
  });

  final String shape;
  final int? strokeColorValue;
  final int? fillColorValue;
  final double strokeWidth;

  @override
  BlockType get type => BlockType.shape;

  factory ShapeNodeContent.fromLegacy(Map<String, dynamic> raw) => ShapeNodeContent(
        shape: raw['shape'] as String? ?? 'rectangle',
        strokeColorValue: (raw['strokeColorValue'] as num?)?.toInt(),
        fillColorValue: (raw['fillColorValue'] as num?)?.toInt(),
        strokeWidth: (raw['strokeWidth'] as num?)?.toDouble() ?? 1,
      );

  @override
  Map<String, dynamic> toPayload() => <String, dynamic>{
        'shape': shape,
        'strokeColorValue': strokeColorValue,
        'fillColorValue': fillColorValue,
        'strokeWidth': strokeWidth,
      };
}

class GroupNodeContent extends CanvasNodeContent {
  const GroupNodeContent();

  @override
  BlockType get type => BlockType.group;

  @override
  Map<String, dynamic> toPayload() => const <String, dynamic>{};
}

class OpaqueNodeContent extends CanvasNodeContent {
  OpaqueNodeContent(Map<String, dynamic> raw)
      : raw = UnmodifiableMapView(
          <String, dynamic>{
            for (final entry in raw.entries)
              entry.key: _freezeValue(entry.value),
          },
        );

  final Map<String, dynamic> raw;

  @override
  BlockType get type => BlockType.text;

  @override
  Map<String, dynamic> toPayload() => const <String, dynamic>{};
}

Map<String, double>? _crop(Object? value) {
  if (value is! Map) return null;
  return <String, double>{
    for (final key in const ['left', 'top', 'right', 'bottom'])
      if (value[key] is num) key: (value[key] as num).toDouble(),
  };
}

Object? _freezeValue(Object? value) => switch (value) {
      Map<Object?, Object?> map => UnmodifiableMapView<String, dynamic>(
          <String, dynamic>{
            for (final entry in map.entries)
              entry.key.toString(): _freezeValue(entry.value),
          },
        ),
      List<Object?> list => List<Object?>.unmodifiable(
          list.map(_freezeValue),
        ),
      _ => value,
    };
