import 'package:uuid/uuid.dart';

/// The kinds of content that can be freely placed on a journal page.
enum BlockType { text, image, sticker }

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
  };

  factory ContentBlock.fromJson(Map<String, dynamic> json) => ContentBlock(
    id: json['id'] as String,
    type: BlockType.values.byName(json['type'] as String? ?? 'text'),
    text: json['text'] as String? ?? '',
    assetId: json['assetId'] as String?,
    stickerId: json['stickerId'] as String?,
    x: (json['x'] as num?)?.toDouble() ?? 0,
    y: (json['y'] as num?)?.toDouble() ?? 0,
    w: (json['w'] as num?)?.toDouble() ?? 0,
    h: (json['h'] as num?)?.toDouble() ?? 0,
    rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
  );
}

/// Per-page camera state. `zoom == 1` means the default readable scale.
/// Pan offsets are world-space units and are intentionally not page-bounded.
class ViewState {
  ViewState({this.zoom = 1, this.panX = 0, this.panY = 0});

  double zoom;
  double panX;
  double panY;

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
  }) : title = title ?? '',
       blocks = blocks ?? [],
       modifiedAt = modifiedAt ?? createdAt;

  static const _uuid = Uuid();

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

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'modifiedAt': modifiedAt.toIso8601String(),
    'blocks': blocks.map((b) => b.toJson()).toList(),
    'music': music,
    'view': view?.toJson(),
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
    );
  }

  static Map<String, dynamic> _stringMap(Object value) =>
      Map<String, dynamic>.from(value as Map);
}
