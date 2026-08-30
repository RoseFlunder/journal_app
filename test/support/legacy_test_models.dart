import 'dart:math' as math;
import 'dart:ui';

import 'package:uuid/uuid.dart';

import 'package:journal_app/models/document.dart';
import 'package:journal_app/models/page_music.dart';
import 'package:journal_app/models/view_state.dart';

export 'package:journal_app/models/canvas.dart';
export 'package:journal_app/models/view_state.dart';

/// Test fixture projection for older widget scenarios. This intentionally
/// lives below test/ and is not part of the application or storage API.
class ContentBlock implements CanvasRenderable {
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
    this.strokeType = 'pen',
    this.inkPoints,
    this.childIds,
    this.groupId,
  });

  @override
  final String id;
  @override
  BlockType type;
  @override
  String text;
  @override
  String? assetId;
  @override
  String? stickerId;
  @override
  double x;
  @override
  double y;
  @override
  double w;
  @override
  double h;
  @override
  double rotation;
  @override
  double fontSize;
  @override
  String? fontFamily;
  @override
  int? textColorValue;
  @override
  bool bold;
  @override
  bool italic;
  @override
  bool locked;
  @override
  bool hidden;
  @override
  double opacity;
  @override
  String? name;
  @override
  List<dynamic>? richTextDelta;
  @override
  Rect? crop;
  @override
  bool flipX;
  @override
  bool flipY;
  @override
  String imageMask;
  @override
  double cornerRadius;
  @override
  int? frameColorValue;
  @override
  double frameWidth;
  @override
  double brightness;
  @override
  double contrast;
  @override
  double saturation;
  @override
  double warmth;
  @override
  String shape;
  @override
  int? strokeColorValue;
  @override
  int? fillColorValue;
  @override
  double strokeWidth;
  @override
  String strokeType;
  @override
  List<Map<String, dynamic>>? inkPoints;
  @override
  List<String>? childIds;
  @override
  String? groupId;

  @override
  bool get isOpaque => false;

  ContentBlock clone() => ContentBlock.fromJson(toJson());

  @override
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
        'strokeType': strokeType,
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
        strokeType: json['strokeType'] as String? ?? 'pen',
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
  })  : board = board ?? const BoardSettings(),
        title = title ?? '',
        blocks = blocks ?? [],
        modifiedAt = modifiedAt ?? createdAt;

  static const _uuid = Uuid();
  static const currentSchemaVersion = 3;

  factory Entry.newPage() {
    final now = DateTime.now();
    return Entry(id: _uuid.v4(), createdAt: now);
  }

  final String id;
  String title;
  final DateTime createdAt;
  DateTime modifiedAt;
  List<ContentBlock> blocks;
  PageMusicTrack? music;
  ViewState? view;
  double titleFontSize;
  String? titleFontFamily;
  int? titleTextColorValue;
  bool titleBold;
  bool titleItalic;
  int schemaVersion;
  int revision;
  BoardSettings board;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'blocks': blocks.map((b) => b.toJson()).toList(),
        'music': music?.toJson(),
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
      music: PageMusicTrack.decode(json['music']),
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

abstract final class EntryDocumentCodec {
  static EntryDocument fromEntry(Entry entry) => EntryDocument(
        id: entry.id,
        title: entry.title,
        createdAt: entry.createdAt,
        modifiedAt: entry.modifiedAt,
        nodes: _topLevelNodes(entry.blocks),
        board: entry.board,
        view: entry.view,
        music: entry.music,
        titleFontSize: entry.titleFontSize,
        titleFontFamily: entry.titleFontFamily,
        titleTextColorValue: entry.titleTextColorValue,
        titleBold: entry.titleBold,
        titleItalic: entry.titleItalic,
        revision: entry.revision,
        schemaVersion: entry.schemaVersion,
      );

  static Entry toEntry(EntryDocument document) => Entry(
        id: document.id,
        title: document.title,
        createdAt: document.createdAt,
        modifiedAt: document.modifiedAt,
        blocks: _flattenNodes(document.nodes).toList(growable: false),
        board: document.board,
        view: document.view,
        music: document.music,
        titleFontSize: document.titleFontSize,
        titleFontFamily: document.titleFontFamily,
        titleTextColorValue: document.titleTextColorValue,
        titleBold: document.titleBold,
        titleItalic: document.titleItalic,
        revision: document.revision,
        schemaVersion: document.schemaVersion,
      );

  static EntryDocument fromLegacyBlocks({
    required String id,
    required String title,
    required DateTime createdAt,
    required Iterable<ContentBlock> blocks,
    BoardSettings board = const BoardSettings(),
  }) => fromEntry(
        Entry(
          id: id,
          title: title,
          createdAt: createdAt,
          blocks: blocks.map((block) => block.clone()).toList(growable: false),
          board: board,
        ),
      );

  static CanvasNode nodeFromBlock(
    ContentBlock block, {
    Iterable<CanvasNode> children = const [],
    Transform2D? transform,
  }) => CanvasNode(
        id: block.id,
        type: block.type,
        transform: transform ??
            Transform2D(
              x: block.x,
              y: block.y,
              width: block.w,
              height: block.h,
              rotation: block.rotation,
            ),
        payload: block.toJson(),
        opacity: block.opacity,
        locked: block.locked,
        visible: !block.hidden,
        accessibilityLabel: block.name,
        children: children,
      );

  static ContentBlock blockFromNode(
    CanvasNode node, {
    Transform2D? worldTransform,
  }) {
    final resolvedTransform = worldTransform ?? node.transform;
    final json = Map<String, dynamic>.from(node.payload)
      ..['id'] = node.id
      ..['type'] = node.type.name
      ..addAll(resolvedTransform.toJson())
      ..['opacity'] = node.opacity
      ..['locked'] = node.locked
      ..['hidden'] = !node.visible
      ..['name'] = node.accessibilityLabel;
    return ContentBlock.fromJson(json);
  }

  static List<CanvasNode> _topLevelNodes(List<ContentBlock> blocks) {
    final byId = {for (final block in blocks) block.id: block};
    final building = <String>{};
    CanvasNode build(ContentBlock block, ContentBlock? parent) {
      if (!building.add(block.id)) return nodeFromBlock(block);
      final children = block.type == BlockType.group
          ? (block.childIds ?? const <String>[])
              .map((id) => byId[id])
              .whereType<ContentBlock>()
              .map((child) => build(child, block))
          : const <CanvasNode>[];
      building.remove(block.id);
      return nodeFromBlock(
        block,
        transform: _localTransform(block, parent),
        children: children,
      );
    }
    return blocks
        .where((block) => block.groupId == null &&
            (block.type != BlockType.group || block.childIds != null))
        .map((block) => build(block, null))
        .toList(growable: false);
  }

  static Iterable<ContentBlock> _flattenNodes(
    Iterable<CanvasNode> nodes, {
    Transform2D? parentWorld,
    String? parentId,
  }) sync* {
    for (final node in nodes) {
      final world = parentWorld == null
          ? node.transform
          : _worldTransform(node.transform, parentWorld);
      final block = blockFromNode(node, worldTransform: world);
      if (parentId != null) block.groupId = parentId;
      if (node.children.isNotEmpty) {
        block.childIds = node.children.map((child) => child.id).toList();
        block.hidden = true;
      }
      yield block;
      yield* _flattenNodes(
        node.children,
        parentWorld: world,
        parentId: node.id,
      );
    }
  }

  static Transform2D _localTransform(ContentBlock block, ContentBlock? parent) {
    final world = Transform2D(
      x: block.x,
      y: block.y,
      width: block.w,
      height: block.h,
      rotation: block.rotation,
    );
    if (parent == null) return world;
    return _toLocal(world, Transform2D(
      x: parent.x,
      y: parent.y,
      width: parent.w,
      height: parent.h,
      rotation: parent.rotation,
    ));
  }

  static Transform2D _toLocal(Transform2D world, Transform2D parent) {
    final parentCenter = Offset(parent.width / 2, parent.height / 2);
    final worldParentCenter = Offset(
      parent.x + parentCenter.dx,
      parent.y + parentCenter.dy,
    );
    final worldCenter = Offset(
      world.x + world.width / 2,
      world.y + world.height / 2,
    );
    final localCenter = parentCenter +
        _rotate(worldCenter - worldParentCenter, -parent.rotation);
    return Transform2D(
      x: localCenter.dx - world.width / 2,
      y: localCenter.dy - world.height / 2,
      width: world.width,
      height: world.height,
      rotation: world.rotation - parent.rotation,
    );
  }

  static Transform2D _worldTransform(Transform2D local, Transform2D parent) {
    final parentCenter = Offset(parent.width / 2, parent.height / 2);
    final localCenter = Offset(
      local.x + local.width / 2,
      local.y + local.height / 2,
    );
    final worldParentCenter = Offset(
      parent.x + parentCenter.dx,
      parent.y + parentCenter.dy,
    );
    final worldCenter = worldParentCenter +
        _rotate(localCenter - parentCenter, parent.rotation);
    return Transform2D(
      x: worldCenter.dx - local.width / 2,
      y: worldCenter.dy - local.height / 2,
      width: local.width,
      height: local.height,
      rotation: parent.rotation + local.rotation,
    );
  }

  static Offset _rotate(Offset point, double angle) {
    final cosine = math.cos(angle);
    final sine = math.sin(angle);
    return Offset(
      point.dx * cosine - point.dy * sine,
      point.dx * sine + point.dy * cosine,
    );
  }
}
