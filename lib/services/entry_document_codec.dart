import 'dart:math' as math;
import 'dart:ui';

import '../models/document.dart';
import '../models/entry.dart';

/// Translates the immutable editor document to and from legacy storage
/// records. This is the only production boundary where [Entry] and
/// [ContentBlock] are allowed to participate in document conversion.
abstract final class EntryDocumentCodec {
  /// Decodes a legacy flattened entry graph into a nested immutable document.
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

  /// Encodes an immutable document into the flattened record shape expected
  /// by the current Hive store.
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

  /// Builds an immutable document from legacy block fixtures without
  /// exposing the mutable adapter through the document model.
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

  /// Converts one storage block to an immutable node. This helper is useful
  /// only for compatibility-edge fixtures and adapter tests.
  static CanvasNode nodeFromBlock(
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

  /// Converts one immutable node to a detached storage adapter.
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
        .where(
          (block) =>
              block.groupId == null &&
              (block.type != BlockType.group || block.childIds != null),
        )
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
