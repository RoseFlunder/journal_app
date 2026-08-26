import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import 'entry.dart';
import 'page_music.dart';

/// Immutable world-space transform shared by every board node.
class Transform2D {
  const Transform2D({
    this.x = 0,
    this.y = 0,
    this.width = 0,
    this.height = 0,
    this.rotation = 0,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final double rotation;

  Transform2D copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
  }) => Transform2D(
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
    rotation: rotation ?? this.rotation,
  );

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'w': width,
    'h': height,
    'rotation': rotation,
  };

  factory Transform2D.fromJson(Map<String, dynamic> json) => Transform2D(
    x: (json['x'] as num?)?.toDouble() ?? 0,
    y: (json['y'] as num?)?.toDouble() ?? 0,
    width: (json['w'] as num?)?.toDouble() ?? 0,
    height: (json['h'] as num?)?.toDouble() ?? 0,
    rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
  );
}

/// Immutable discriminated board node. Payload remains JSON-compatible so
/// RichText Delta, image adjustments, ink strokes, and future node types can
/// evolve without changing the common transform contract.
class CanvasNode {
  static const _unset = Object();

  CanvasNode({
    required this.id,
    required this.type,
    required this.transform,
    Map<String, dynamic> payload = const {},
    this.opacity = 1,
    this.locked = false,
    this.visible = true,
    this.accessibilityLabel,
    Iterable<CanvasNode> children = const [],
  }) : payload = _freezeMap(payload),
       children = UnmodifiableListView(List<CanvasNode>.from(children));

  final String id;
  final BlockType type;
  final Transform2D transform;
  final Map<String, dynamic> payload;
  final double opacity;
  final bool locked;
  final bool visible;
  final String? accessibilityLabel;
  final List<CanvasNode> children;

  CanvasNode copyWith({
    String? id,
    BlockType? type,
    Transform2D? transform,
    Map<String, dynamic>? payload,
    double? opacity,
    bool? locked,
    bool? visible,
    Object? accessibilityLabel = _unset,
    Iterable<CanvasNode>? children,
  }) => CanvasNode(
    id: id ?? this.id,
    type: type ?? this.type,
    transform: transform ?? this.transform,
    payload: payload ?? this.payload,
    opacity: opacity ?? this.opacity,
    locked: locked ?? this.locked,
    visible: visible ?? this.visible,
    accessibilityLabel: identical(accessibilityLabel, _unset)
        ? this.accessibilityLabel
        : accessibilityLabel as String?,
    children: children ?? this.children,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'transform': transform.toJson(),
    'payload': payload,
    'opacity': opacity,
    'locked': locked,
    'visible': visible,
    'accessibilityLabel': accessibilityLabel,
    'children': children.map((node) => node.toJson()).toList(),
  };

  factory CanvasNode.fromBlock(
    ContentBlock block, {
    Iterable<CanvasNode> children = const [],
    Transform2D? transform,
  }) => CanvasNode(
    id: block.id,
    type: block.type,
    transform:
        transform ??
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

  factory CanvasNode.fromJson(Map<String, dynamic> json) {
    final transform = json['transform'] is Map
        ? Transform2D.fromJson(
            Map<String, dynamic>.from(json['transform'] as Map),
          )
        : Transform2D.fromJson(json);
    final type = switch (json['type'] as String?) {
      'image' => BlockType.image,
      'sticker' => BlockType.sticker,
      'ink' => BlockType.ink,
      'shape' => BlockType.shape,
      'group' => BlockType.group,
      _ => BlockType.text,
    };
    return CanvasNode(
      id: json['id'] as String,
      type: type,
      transform: transform,
      payload: json['payload'] is Map
          ? Map<String, dynamic>.from(json['payload'] as Map)
          : const {},
      opacity: ((json['opacity'] as num?)?.toDouble() ?? 1)
          .clamp(0.0, 1.0)
          .toDouble(),
      locked: json['locked'] as bool? ?? false,
      visible: json['visible'] as bool? ?? true,
      accessibilityLabel: json['accessibilityLabel'] as String?,
      children: (json['children'] as List<dynamic>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map(
            (child) => CanvasNode.fromJson(Map<String, dynamic>.from(child)),
          ),
    );
  }

  ContentBlock toBlock({Transform2D? worldTransform}) {
    final resolvedTransform = worldTransform ?? transform;
    final json = Map<String, dynamic>.from(payload)
      ..['id'] = id
      ..['type'] = type.name
      ..addAll(resolvedTransform.toJson())
      ..['opacity'] = opacity
      ..['locked'] = locked
      ..['hidden'] = !visible
      ..['name'] = accessibilityLabel;
    return ContentBlock.fromJson(json);
  }
}

/// Immutable document boundary for repository, editor, archive, and sync
/// code. The legacy Entry adapter is intentionally retained only as a
/// temporary UI/storage bridge while fresh data adopts this shape.
class EntryDocument {
  static const _copyWithUnset = Object();

  EntryDocument({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.modifiedAt,
    Iterable<CanvasNode> nodes = const [],
    this.board = const BoardSettings(),
    this.view,
    this.music,
    this.titleFontSize = 28,
    this.titleFontFamily,
    this.titleTextColorValue,
    this.titleBold = true,
    this.titleItalic = false,
    this.revision = 0,
    this.schemaVersion = 1,
  }) : nodes = UnmodifiableListView(List<CanvasNode>.from(nodes));

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final List<CanvasNode> nodes;
  final BoardSettings board;
  final ViewState? view;
  final PageMusicTrack? music;
  final double titleFontSize;
  final String? titleFontFamily;
  final int? titleTextColorValue;
  final bool titleBold;
  final bool titleItalic;
  final int revision;
  final int schemaVersion;

  /// Compatibility view for the legacy canvas and storage adapters.
  ///
  /// New code should use [nodes]. The returned blocks are detached mutable
  /// adapters, so mutating one cannot mutate this document.
  @Deprecated('Use immutable nodes instead.')
  List<ContentBlock> get blocks => toEntry().blocks;

  EntryDocument copyWith({
    String? title,
    DateTime? modifiedAt,
    Iterable<CanvasNode>? nodes,
    BoardSettings? board,
    Object? view = _copyWithUnset,
    Object? music = _copyWithUnset,
    double? titleFontSize,
    Object? titleFontFamily = _copyWithUnset,
    Object? titleTextColorValue = _copyWithUnset,
    bool? titleBold,
    bool? titleItalic,
    int? revision,
    int? schemaVersion,
  }) => EntryDocument(
    id: id,
    title: title ?? this.title,
    createdAt: createdAt,
    modifiedAt: modifiedAt ?? this.modifiedAt,
    nodes: nodes ?? this.nodes,
    board: board ?? this.board,
    view: identical(view, _copyWithUnset) ? this.view : view as ViewState?,
    music: identical(music, _copyWithUnset)
        ? this.music
        : music as PageMusicTrack?,
    titleFontSize: titleFontSize ?? this.titleFontSize,
    titleFontFamily: identical(titleFontFamily, _copyWithUnset)
        ? this.titleFontFamily
        : titleFontFamily as String?,
    titleTextColorValue: identical(titleTextColorValue, _copyWithUnset)
        ? this.titleTextColorValue
        : titleTextColorValue as int?,
    titleBold: titleBold ?? this.titleBold,
    titleItalic: titleItalic ?? this.titleItalic,
    revision: revision ?? this.revision,
    schemaVersion: schemaVersion ?? this.schemaVersion,
  );

  factory EntryDocument.fromEntry(Entry entry) => EntryDocument(
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

  factory EntryDocument.fromJson(Map<String, dynamic> json) => EntryDocument(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    createdAt: DateTime.parse(json['createdAt'] as String),
    modifiedAt: DateTime.parse(
      json['modifiedAt'] as String? ?? json['createdAt'] as String,
    ),
    nodes: (json['nodes'] as List<dynamic>? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map((node) => CanvasNode.fromJson(Map<String, dynamic>.from(node))),
    board: BoardSettings.fromJson(
      json['board'] is Map
          ? Map<String, dynamic>.from(json['board'] as Map)
          : null,
    ),
    view: json['view'] is Map
        ? ViewState.fromJson(Map<String, dynamic>.from(json['view'] as Map))
        : null,
    music: PageMusicTrack.decode(json['music']),
    titleFontSize: (json['titleFontSize'] as num?)?.toDouble() ?? 28,
    titleFontFamily: json['titleFontFamily'] as String?,
    titleTextColorValue: (json['titleTextColorValue'] as num?)?.toInt(),
    titleBold: json['titleBold'] as bool? ?? true,
    titleItalic: json['titleItalic'] as bool? ?? false,
    revision: (json['revision'] as num?)?.toInt() ?? 0,
    schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
  );

  Entry toEntry() => Entry(
    id: id,
    title: title,
    createdAt: createdAt,
    modifiedAt: modifiedAt,
    blocks: nodes.expand(_flattenNode).toList(),
    board: board,
    view: view,
    music: music,
    titleFontSize: titleFontSize,
    titleFontFamily: titleFontFamily,
    titleTextColorValue: titleTextColorValue,
    titleBold: titleBold,
    titleItalic: titleItalic,
    revision: revision,
    schemaVersion: schemaVersion,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'modifiedAt': modifiedAt.toIso8601String(),
    'nodes': nodes.map((node) => node.toJson()).toList(),
    'board': board.toJson(),
    'view': view?.toJson(),
    'music': music?.toJson(),
    'titleFontSize': titleFontSize,
    'titleFontFamily': titleFontFamily,
    'titleTextColorValue': titleTextColorValue,
    'titleBold': titleBold,
    'titleItalic': titleItalic,
    'revision': revision,
    'schemaVersion': schemaVersion,
  };

  static List<CanvasNode> _topLevelNodes(List<ContentBlock> blocks) {
    final byId = {for (final block in blocks) block.id: block};
    final building = <String>{};
    CanvasNode build(ContentBlock block, ContentBlock? parent) {
      if (!building.add(block.id)) {
        return CanvasNode.fromBlock(block);
      }
      final children = block.type == BlockType.group
          ? (block.childIds ?? const <String>[])
                .map((id) => byId[id])
                .whereType<ContentBlock>()
                .map((child) => build(child, block))
          : const <CanvasNode>[];
      building.remove(block.id);
      return CanvasNode.fromBlock(
        block,
        transform: _localTransform(block, parent),
        children: children,
      );
    }

    return blocks
        .where(
          (block) =>
              block.groupId == null &&
              (block.type != BlockType.group || block.childIds != null),
        )
        .map((block) => build(block, null))
        .toList(growable: false);
  }

  static Iterable<ContentBlock> _flattenNode(
    CanvasNode node, {
    String? parentId,
  }) sync* {
    final block = node.toBlock();
    if (parentId != null) block.groupId = parentId;
    if (node.children.isNotEmpty) {
      block.childIds = node.children.map((child) => child.id).toList();
      block.hidden = true;
    }
    yield block;
    for (final child in node.children) {
      yield* _flattenNode(
        child.copyWith(
          transform: _worldTransform(child.transform, node.transform),
        ),
        parentId: node.id,
      );
    }
  }

  static Transform2D _localTransform(
    ContentBlock block,
    ContentBlock? parent,
  ) {
    final world = Transform2D(
      x: block.x,
      y: block.y,
      width: block.w,
      height: block.h,
      rotation: block.rotation,
    );
    if (parent == null) return world;
    return _toLocal(
      world,
      Transform2D(
        x: parent.x,
        y: parent.y,
        width: parent.w,
        height: parent.h,
        rotation: parent.rotation,
      ),
    );
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

  static Transform2D _worldTransform(
    Transform2D local,
    Transform2D parent,
  ) {
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

Map<String, dynamic> _freezeMap(Map<Object?, Object?> source) =>
    UnmodifiableMapView(<String, dynamic>{
      for (final entry in source.entries)
        entry.key.toString(): _freezeValue(entry.value),
    });

Object? _freezeValue(Object? value) => switch (value) {
  Map<Object?, Object?> map => _freezeMap(map),
  List<Object?> list => UnmodifiableListView<Object?>(
    list.map(_freezeValue).toList(growable: false),
  ),
  _ => value,
};
