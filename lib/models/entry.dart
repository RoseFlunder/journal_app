import 'dart:ui';

import 'package:uuid/uuid.dart';

/// Font families that can be selected in the editor.
///
/// A null value intentionally means the current theme default. This keeps
/// older entries compatible and lets titles and body text retain their
/// different defaults.
abstract final class JournalFonts {
  static const caveat = 'Caveat';
  static const lora = 'Lora';

  static String? normalize(String? value) => switch (value) {
    caveat => caveat,
    lora => lora,
    _ => null,
  };
}

/// The kinds of content that can be freely placed on a journal page.
/// The block kinds understood by the creative board. The first three values
/// are the original persisted journal formats; the others are additive.
enum BlockType { text, image, sticker, ink, shape, group }

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

/// A piece of freely positioned content on a journal page.
///
/// Position and size are stored in logical workspace units, independent of
/// screen size. Coordinates may be negative or extend beyond the initial
/// workspace area.
class ContentBlock {
  ContentBlock({
    required this.id,
    required this.type,
    this.text = '',
    this.assetId,
    this.stickerId,
    this.x = 0,
    this.y = 0,
    this.w = 0,
    this.h = 0,
    this.rotation = 0,
    this.fontSize = 21,
    this.fontFamily,
    this.textColorValue,
    this.bold = false,
    this.italic = false,
    this.locked = false,
    this.hidden = false,
    this.opacity = 1,
    this.name,
    this.richTextDelta,
    this.crop,
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
    this.shape = 'rectangle',
    this.strokeColorValue,
    this.fillColorValue,
    this.strokeWidth = 1,
    this.inkPoints,
    this.childIds,
    this.groupId,
  });

  final String id;
  BlockType type;

  /// Content of a [BlockType.text] block.
  String text;

  /// Asset id (key in the assets box) for a [BlockType.image] block.
  String? assetId;

  /// Bundled sticker id for a [BlockType.sticker] block. Sticker files live
  /// in the Flutter asset bundle and are never copied into Hive.
  String? stickerId;

  double x;
  double y;
  double w;
  double h;
  double rotation;

  /// Text styling. These fields are ignored for image and sticker blocks.
  double fontSize;
  String? fontFamily;
  int? textColorValue;
  bool bold;
  bool italic;

  /// Board-level metadata. The legacy renderer ignores these until the new
  /// controller consumes them, preserving older journals unchanged.
  bool locked;
  bool hidden;
  double opacity;
  String? name;

  /// Quill-compatible Delta JSON. [text] remains the legacy/search fallback.
  List<dynamic>? richTextDelta;

  /// Normalized crop coordinates for image and sticker nodes.
  Rect? crop;
  bool flipX;
  bool flipY;

  /// Non-destructive image presentation settings. Original asset bytes stay
  /// untouched and these values are shared by image and sticker nodes.
  String imageMask;
  double cornerRadius;
  int? frameColorValue;
  double frameWidth;
  double brightness;
  double contrast;
  double saturation;
  double warmth;

  /// Forward-compatible shape, ink, and group payloads.
  String shape;
  int? strokeColorValue;
  int? fillColorValue;
  double strokeWidth;
  List<Map<String, dynamic>>? inkPoints;
  List<String>? childIds;
  String? groupId;

  ContentBlock clone() => ContentBlock.fromJson(toJson());

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'text': text,
    'assetId': assetId,
    'stickerId': stickerId,
    'x': x,
    'y': y,
    'w': w,
    'h': h,
    'rotation': rotation,
    'fontSize': fontSize,
    'fontFamily': fontFamily,
    'textColorValue': textColorValue,
    'bold': bold,
    'italic': italic,
    'locked': locked,
    'hidden': hidden,
    'opacity': opacity,
    'name': name,
    'richTextDelta': richTextDelta,
    'crop': crop == null
        ? null
        : {
            'left': crop!.left,
            'top': crop!.top,
            'right': crop!.right,
            'bottom': crop!.bottom,
          },
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
    'shape': shape,
    'strokeColorValue': strokeColorValue,
    'fillColorValue': fillColorValue,
    'strokeWidth': strokeWidth,
    'inkPoints': inkPoints,
    'childIds': childIds,
    'groupId': groupId,
  };

  factory ContentBlock.fromJson(Map<String, dynamic> json) => ContentBlock(
    id: json['id'] as String,
    type: _blockType(json['type'] as String?),
    text: json['text'] as String? ?? '',
    assetId: json['assetId'] as String?,
    stickerId: json['stickerId'] as String?,
    x: (json['x'] as num?)?.toDouble() ?? 0,
    y: (json['y'] as num?)?.toDouble() ?? 0,
    w: (json['w'] as num?)?.toDouble() ?? 0,
    h: (json['h'] as num?)?.toDouble() ?? 0,
    rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
    fontSize: (json['fontSize'] as num?)?.toDouble() ?? 21,
    fontFamily: JournalFonts.normalize(json['fontFamily'] as String?),
    textColorValue: (json['textColorValue'] as num?)?.toInt(),
    bold: json['bold'] as bool? ?? false,
    italic: json['italic'] as bool? ?? false,
    locked: json['locked'] as bool? ?? false,
    hidden: json['hidden'] as bool? ?? false,
    opacity: ((json['opacity'] as num?)?.toDouble() ?? 1)
        .clamp(0.0, 1.0)
        .toDouble(),
    name: json['name'] as String?,
    richTextDelta: json['richTextDelta'] is List
        ? List<dynamic>.from(json['richTextDelta'] as List)
        : null,
    crop: _crop(json['crop']),
    flipX: json['flipX'] as bool? ?? false,
    flipY: json['flipY'] as bool? ?? false,
    imageMask: json['imageMask'] as String? ?? 'rectangle',
    cornerRadius: (json['cornerRadius'] as num?)?.toDouble() ?? 0,
    frameColorValue: (json['frameColorValue'] as num?)?.toInt(),
    frameWidth: (json['frameWidth'] as num?)?.toDouble() ?? 0,
    brightness: (json['brightness'] as num?)?.toDouble() ?? 0,
    contrast: (json['contrast'] as num?)?.toDouble() ?? 0,
    saturation: (json['saturation'] as num?)?.toDouble() ?? 1,
    warmth: (json['warmth'] as num?)?.toDouble() ?? 0,
    shape: json['shape'] as String? ?? 'rectangle',
    strokeColorValue: (json['strokeColorValue'] as num?)?.toInt(),
    fillColorValue: (json['fillColorValue'] as num?)?.toInt(),
    strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 1,
    inkPoints: (json['inkPoints'] as List<dynamic>?)
        ?.whereType<Map<Object?, Object?>>()
        .map((point) => Map<String, dynamic>.from(point))
        .toList(),
    childIds: (json['childIds'] as List<dynamic>?)
        ?.whereType<String>()
        .toList(),
    groupId: json['groupId'] as String?,
  );

  static BlockType _blockType(String? value) => switch (value) {
    'image' => BlockType.image,
    'sticker' => BlockType.sticker,
    'ink' => BlockType.ink,
    'shape' => BlockType.shape,
    'group' => BlockType.group,
    _ => BlockType.text,
  };

  static Rect? _crop(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    return Rect.fromLTRB(
      (json['left'] as num?)?.toDouble() ?? 0,
      (json['top'] as num?)?.toDouble() ?? 0,
      (json['right'] as num?)?.toDouble() ?? 1,
      (json['bottom'] as num?)?.toDouble() ?? 1,
    );
  }
}

/// Per-page camera state. `zoom == 1` means the default readable scale.
/// Pan offsets are world-space units and are intentionally not page-bounded.
class ViewState {
  const ViewState({this.zoom = 1, this.panX = 0, this.panY = 0});

  final double zoom;
  final double panX;
  final double panY;

  ViewState copyWith({double? zoom, double? panX, double? panY}) => ViewState(
    zoom: zoom ?? this.zoom,
    panX: panX ?? this.panX,
    panY: panY ?? this.panY,
  );

  Map<String, dynamic> toJson() => {'zoom': zoom, 'panX': panX, 'panY': panY};

  factory ViewState.fromJson(Map<String, dynamic> json) => ViewState(
    zoom: (json['zoom'] as num?)?.toDouble() ?? 1,
    panX: (json['panX'] as num?)?.toDouble() ?? 0,
    panY: (json['panY'] as num?)?.toDouble() ?? 0,
  );
}

/// One journal page.
class Entry {
  Entry({
    required this.id,
    required this.createdAt,
    String? title,
    DateTime? modifiedAt,
    List<ContentBlock>? blocks,
    this.music,
    this.view,
    this.titleFontSize = 28,
    this.titleFontFamily,
    this.titleTextColorValue,
    this.titleBold = true,
    this.titleItalic = false,
    this.schemaVersion = currentSchemaVersion,
    this.revision = 0,
    BoardSettings? board,
  }) : board = board ?? const BoardSettings(),
       title = title ?? '',
       blocks = blocks ?? [],
       modifiedAt = modifiedAt ?? createdAt;

  static const _uuid = Uuid();
  static const currentSchemaVersion = 2;

  factory Entry.newPage() {
    final now = DateTime.now();
    return Entry(id: _uuid.v4(), createdAt: now);
  }

  final String id;
  String title;
  final DateTime createdAt;
  DateTime modifiedAt;
  List<ContentBlock> blocks;

  /// Asset id of the page's background music (nullable), see milestone M6.
  String? music;

  /// The page's zoom/pan state, see milestone M3.
  ViewState? view;

  /// Formatting for the page title. Older entries use the defaults here.
  double titleFontSize;
  String? titleFontFamily;
  int? titleTextColorValue;
  bool titleBold;
  bool titleItalic;

  /// Versioned board metadata. Blocks remain the compatibility node list so
  /// existing journals can migrate in-place without a destructive rewrite.
  int schemaVersion;
  int revision;
  BoardSettings board;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'modifiedAt': modifiedAt.toIso8601String(),
    'blocks': blocks.map((b) => b.toJson()).toList(),
    'music': music,
    'view': view?.toJson(),
    'titleFontSize': titleFontSize,
    'titleFontFamily': titleFontFamily,
    'titleTextColorValue': titleTextColorValue,
    'titleBold': titleBold,
    'titleItalic': titleItalic,
    'schemaVersion': currentSchemaVersion,
    'revision': revision,
    'board': board.toJson(),
  };

  factory Entry.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.parse(json['createdAt'] as String);
    return Entry(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      createdAt: createdAt,
      modifiedAt: json['modifiedAt'] != null
          ? DateTime.parse(json['modifiedAt'] as String)
          : createdAt,
      blocks: (json['blocks'] as List<dynamic>? ?? const [])
          .map((b) => ContentBlock.fromJson(_stringMap(b)))
          .toList(),
      music: json['music'] as String?,
      view: json['view'] != null
          ? ViewState.fromJson(_stringMap(json['view']))
          : null,
      titleFontSize: (json['titleFontSize'] as num?)?.toDouble() ?? 28,
      titleFontFamily: JournalFonts.normalize(
        json['titleFontFamily'] as String?,
      ),
      titleTextColorValue: (json['titleTextColorValue'] as num?)?.toInt(),
      titleBold: json['titleBold'] as bool? ?? true,
      titleItalic: json['titleItalic'] as bool? ?? false,
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      board: BoardSettings.fromJson(
        json['board'] is Map ? _stringMap(json['board']) : null,
      ),
    );
  }

  static Map<String, dynamic> _stringMap(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const FormatException('Expected a JSON object');
    }
    return Map<String, dynamic>.from(value);
  }
}
