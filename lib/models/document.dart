import 'dart:collection';

import 'entry.dart';

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
  CanvasNode({
    required this.id,
    required this.type,
    required this.transform,
    Map<String, dynamic> payload = const {},
    this.opacity = 1,
    this.locked = false,
    this.visible = true,
    this.accessibilityLabel,
  }) : payload = UnmodifiableMapView(Map<String, dynamic>.from(payload));

  final String id;
  final BlockType type;
  final Transform2D transform;
  final Map<String, dynamic> payload;
  final double opacity;
  final bool locked;
  final bool visible;
  final String? accessibilityLabel;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'transform': transform.toJson(),
    'payload': payload,
    'opacity': opacity,
    'locked': locked,
    'visible': visible,
    'accessibilityLabel': accessibilityLabel,
  };

  factory CanvasNode.fromBlock(ContentBlock block) => CanvasNode(
    id: block.id,
    type: block.type,
    transform: Transform2D(
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
    );
  }

  ContentBlock toBlock() {
    final json = Map<String, dynamic>.from(payload)
      ..['id'] = id
      ..['type'] = type.name
      ..addAll(transform.toJson())
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
  EntryDocument({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.modifiedAt,
    Iterable<CanvasNode> nodes = const [],
    this.board = const BoardSettings(),
    this.view,
    this.music,
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
  final String? music;
  final int revision;
  final int schemaVersion;

  factory EntryDocument.fromEntry(Entry entry) => EntryDocument(
    id: entry.id,
    title: entry.title,
    createdAt: entry.createdAt,
    modifiedAt: entry.modifiedAt,
    nodes: entry.blocks.map(CanvasNode.fromBlock),
    board: entry.board,
    view: entry.view,
    music: entry.music,
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
    nodes: (json['nodes'] as List<dynamic>? ?? const []).whereType<Map>().map(
      (node) => CanvasNode.fromJson(Map<String, dynamic>.from(node)),
    ),
    board: BoardSettings.fromJson(
      json['board'] is Map
          ? Map<String, dynamic>.from(json['board'] as Map)
          : null,
    ),
    view: json['view'] is Map
        ? ViewState.fromJson(Map<String, dynamic>.from(json['view'] as Map))
        : null,
    music: json['music'] as String?,
    revision: (json['revision'] as num?)?.toInt() ?? 0,
    schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
  );

  Entry toEntry() => Entry(
    id: id,
    title: title,
    createdAt: createdAt,
    modifiedAt: modifiedAt,
    blocks: nodes.map((node) => node.toBlock()).toList(),
    board: board,
    view: view,
    music: music,
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
    'music': music,
    'revision': revision,
    'schemaVersion': schemaVersion,
  };
}
