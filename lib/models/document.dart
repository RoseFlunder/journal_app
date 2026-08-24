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
