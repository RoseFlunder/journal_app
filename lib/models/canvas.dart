import 'dart:ui';

/// Font families that can be selected in the editor.
///
/// A null value intentionally means the current theme default. This keeps
/// older entries compatible and lets titles and body text retain their
/// different defaults.
abstract final class JournalFonts {
  static const caveat = 'Caveat';
  static const lora = 'Lora';
  static const patrickHand = 'Patrick Hand';
  static const playfairDisplay = 'Playfair Display';

  static String? normalize(String? value) => switch (value) {
    caveat => caveat,
    lora => lora,
    patrickHand => patrickHand,
    playfairDisplay => playfairDisplay,
    _ => null,
  };
}

/// The kinds of content that can be freely placed on a journal page.
enum BlockType { text, image, sticker, ink, shape, group }

/// Visual preset used when rendering vector ink strokes.
enum InkStrokeType { pen, marker, brush, highlighter }

InkStrokeType inkStrokeTypeFromName(Object? value) => switch (value) {
  'marker' => InkStrokeType.marker,
  'brush' => InkStrokeType.brush,
  'highlighter' => InkStrokeType.highlighter,
  _ => InkStrokeType.pen,
};

extension InkStrokeTypeLabel on InkStrokeType {
  String get label => switch (this) {
    InkStrokeType.pen => 'Pen',
    InkStrokeType.marker => 'Marker',
    InkStrokeType.brush => 'Brush pen',
    InkStrokeType.highlighter => 'Highlighter',
  };

  double get widthMultiplier => switch (this) {
    InkStrokeType.pen => 1,
    InkStrokeType.marker => 1.4,
    InkStrokeType.brush => 1.15,
    InkStrokeType.highlighter => 2.4,
  };

  double get opacityMultiplier => switch (this) {
    InkStrokeType.pen => 1,
    InkStrokeType.marker => 0.72,
    InkStrokeType.brush => 0.92,
    InkStrokeType.highlighter => 0.3,
  };

  StrokeCap get strokeCap => switch (this) {
    InkStrokeType.marker || InkStrokeType.highlighter => StrokeCap.square,
    _ => StrokeCap.round,
  };
}

/// Presentation and snapping settings for a journal page. Coordinates remain
/// model-local so rendering is independent of screen size.
class BoardSettings {
  const BoardSettings({
    this.backgroundColorValue = 0xFFF4EDDC,
    this.gridVisible = false,
    this.snapToGrid = false,
    this.gridSize = 8,
  });

  final int backgroundColorValue;
  final bool gridVisible;
  final bool snapToGrid;
  final double gridSize;

  BoardSettings copyWith({
    int? backgroundColorValue,
    bool? gridVisible,
    bool? snapToGrid,
    double? gridSize,
  }) => BoardSettings(
    backgroundColorValue: backgroundColorValue ?? this.backgroundColorValue,
    gridVisible: gridVisible ?? this.gridVisible,
    snapToGrid: snapToGrid ?? this.snapToGrid,
    gridSize: gridSize ?? this.gridSize,
  );

  Map<String, dynamic> toJson() => {
    'backgroundColorValue': backgroundColorValue,
    'gridVisible': gridVisible,
    'snapToGrid': snapToGrid,
    'gridSize': gridSize,
  };

  factory BoardSettings.fromJson(Map<String, dynamic>? json) => BoardSettings(
    backgroundColorValue:
        (json?['backgroundColorValue'] as num?)?.toInt() ?? 0xFFF4EDDC,
    gridVisible: json?['gridVisible'] as bool? ?? false,
    snapToGrid: json?['snapToGrid'] as bool? ?? false,
    gridSize: (json?['gridSize'] as num?)?.toDouble() ?? 8,
  );
}

/// Read-only content contract used by renderers and geometry services.
abstract interface class CanvasRenderable {
  String get id;
  bool get isOpaque;
  BlockType get type;
  String get text;
  String? get assetId;
  String? get stickerId;
  double get x;
  double get y;
  double get w;
  double get h;
  double get rotation;
  double get fontSize;
  String? get fontFamily;
  int? get textColorValue;
  bool get bold;
  bool get italic;
  bool get locked;
  bool get hidden;
  double get opacity;
  String? get name;
  List<dynamic>? get richTextDelta;
  Rect? get crop;
  bool get flipX;
  bool get flipY;
  String get imageMask;
  double get cornerRadius;
  int? get frameColorValue;
  double get frameWidth;
  double get brightness;
  double get contrast;
  double get saturation;
  double get warmth;
  String get shape;
  int? get strokeColorValue;
  int? get fillColorValue;
  double get strokeWidth;
  String get strokeType;
  List<Map<String, dynamic>>? get inkPoints;
  List<String>? get childIds;
  String? get groupId;
  Map<String, dynamic> toJson();
}
