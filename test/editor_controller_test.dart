import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/editor/editor_controller.dart';
import 'package:journal_app/editor/editor_state.dart';
import 'package:journal_app/models/entry.dart';
import 'package:journal_app/models/document.dart';
import 'package:journal_app/services/entry_document_codec.dart';

ContentBlock _text({String id = 'text', double x = 0, double y = 0}) =>
    ContentBlock(
      id: id,
      type: BlockType.text,
      text: 'Hello',
      x: x,
      y: y,
      w: 40,
      h: 20,
    );

EntryDocument _documentFromBlocks(
  Iterable<ContentBlock> blocks, {
  BoardSettings board = const BoardSettings(),
}) => EntryDocumentCodec.fromLegacyBlocks(
  id: 'test-entry',
  title: 'Test entry',
  createdAt: DateTime.utc(2026),
  blocks: blocks,
  board: board,
);

extension _LegacyControllerInspection on EditorController {
  /// Test-only inspection adapter; production code consumes [document].
  List<ContentBlock> get blocks => EntryDocumentCodec.toEntry(document).blocks;
}

void main() {
  test(
    'a transform transaction produces one save and supports undo/redo',
    () async {
      var saves = 0;
      final controller = EditorController(
        document: _documentFromBlocks([_text()]),
        persistDocument: (EntryDocument _) async => saves++,
      );
      addTearDown(controller.dispose);

      controller.select('text');
      expect(controller.state.selection, contains('text'));
      expect(
        EntryDocumentCodec.toEntry(controller.state.document).blocks.single.id,
        'text',
      );
      controller.beginTransformTransaction('Transform');
      controller.moveSelection(const Offset(5, 3));
      controller.moveSelection(const Offset(2, -1));
      await controller.commitTransaction();

      expect(controller.blocks.single.x, 7);
      expect(controller.blocks.single.y, 2);
      expect(saves, 1);
      expect(controller.canUndo, isTrue);
      expect(controller.state.saveState, EditorSaveState.saved);

      await controller.undo();
      expect(controller.blocks.single.x, 0);
      expect(controller.blocks.single.y, 0);
      await controller.redo();
      expect(controller.blocks.single.x, 7);
      expect(controller.blocks.single.y, 2);
      expect(saves, 3);
    },
  );

  test('locked content cannot be changed or deleted', () async {
    final controller = EditorController(
      document: _documentFromBlocks([_text()..locked = true]),
      persistDocument: (EntryDocument _) async {},
    );
    addTearDown(controller.dispose);

    controller.select('text');
    controller.beginTransformTransaction('Transform');
    controller.moveSelection(const Offset(10, 0));
    await controller.commitTransaction();
    controller.deleteSelection();

    expect(controller.blocks, hasLength(1));
    expect(controller.blocks.single.x, 0);
    expect(controller.canUndo, isFalse);
  });

  test(
    'selected drawable stroke styling updates unlocked ink and shapes together',
    () async {
      var saves = 0;
      final controller = EditorController(
        document: _documentFromBlocks([
          ContentBlock(
            id: 'ink',
            type: BlockType.ink,
            w: 20,
            h: 20,
            strokeColorValue: 0xFF3B3226,
            opacity: 1,
          ),
          ContentBlock(
            id: 'shape',
            type: BlockType.shape,
            w: 30,
            h: 20,
            strokeColorValue: 0xFF3B3226,
            opacity: 1,
          ),
          ContentBlock(
            id: 'locked-shape',
            type: BlockType.shape,
            w: 30,
            h: 20,
            strokeColorValue: 0xFF3B3226,
            opacity: 1,
            locked: true,
          ),
          _text(id: 'text'),
        ]),
        persistDocument: (EntryDocument _) async => saves++,
      );
      addTearDown(controller.dispose);

      controller.selectMany(['ink', 'shape', 'locked-shape', 'text']);
      controller.beginStyleTransaction('Format stroke');
      controller.updateSelectedDrawableStroke(
        colorValue: 0xFF873F4D,
        opacity: 0.4,
      );
      await controller.commitTransaction();

      for (final id in ['ink', 'shape']) {
        final block = controller.blocks.firstWhere((item) => item.id == id);
        expect(block.strokeColorValue, 0xFF873F4D);
        expect(block.opacity, 0.4);
      }
      final locked = controller.blocks.firstWhere(
        (block) => block.id == 'locked-shape',
      );
      expect(locked.strokeColorValue, 0xFF3B3226);
      expect(locked.opacity, 1);
      expect(saves, 1);

      await controller.undo();
      expect(
        controller.blocks.firstWhere((block) => block.id == 'ink').opacity,
        1,
      );
      expect(
        controller.blocks
            .firstWhere((block) => block.id == 'shape')
            .strokeColorValue,
        0xFF3B3226,
      );
    },
  );

  test('touch rotation orbits unlocked blocks around a fixed pivot in one transaction', () async {
    var saves = 0;
    final controller = EditorController(
      document: _documentFromBlocks([
        _text(id: 'one'),
        _text(id: 'two', x: 50),
        _text(id: 'locked', x: 100)..locked = true,
      ]),
      persistDocument: (EntryDocument _) async => saves++,
    );
    addTearDown(controller.dispose);

    controller.selectMany(['one', 'two', 'locked']);
    controller.beginTransformTransaction('Transform');
    controller.rotateBlocksAround(
      {'one', 'two', 'locked'},
      const Offset(20, 10),
      math.pi / 2,
    );
    controller.rotateBlocksAround(
      {'one', 'two', 'locked'},
      const Offset(20, 10),
      math.pi / 2,
    );
    await controller.commitTransaction();

    final one = controller.blocks.firstWhere((block) => block.id == 'one');
    final two = controller.blocks.firstWhere((block) => block.id == 'two');
    final locked = controller.blocks.firstWhere(
      (block) => block.id == 'locked',
    );
    expect(one.x, closeTo(0, 0.001));
    expect(one.y, closeTo(0, 0.001));
    expect(one.rotation, closeTo(math.pi, 0.001));
    expect(two.x, closeTo(-50, 0.001));
    expect(two.y, closeTo(0, 0.001));
    expect(two.rotation, closeTo(math.pi, 0.001));
    expect(locked.x, 100);
    expect(locked.y, 0);
    expect(locked.rotation, 0);
    expect(saves, 1);
    expect(controller.canUndo, isTrue);

    await controller.undo();
    expect(controller.blocks.firstWhere((block) => block.id == 'two').x, 50);
  });

  test('additive selection keeps both blocks selected', () {
    final controller = EditorController(
      document: _documentFromBlocks([
        _text(id: 'one'),
        _text(id: 'two', x: 50),
      ]),
      persistDocument: (EntryDocument _) async {},
    );
    addTearDown(controller.dispose);

    controller.select('one');
    controller.select('two', additive: true);
    expect(controller.selection, {'one', 'two'});
    controller.select('one', additive: true);
    expect(controller.selection, {'two'});
  });

  test('grouping persists membership and moves children together', () async {
    final controller = EditorController(
      document: _documentFromBlocks([
        _text(id: 'one'),
        _text(id: 'two', x: 50),
      ]),
      persistDocument: (EntryDocument _) async {},
    );
    addTearDown(controller.dispose);

    controller.selectMany(['one', 'two']);
    controller.groupSelection();
    await Future<void>.delayed(Duration.zero);
    final group = controller.blocks.singleWhere(
      (block) => block.type == BlockType.group,
    );
    expect(group.childIds, ['one', 'two']);
    expect(
      controller.blocks
          .where((block) => block.type == BlockType.text)
          .map((block) => block.groupId),
      everyElement(group.id),
    );

    controller.select('one');
    controller.beginTransformTransaction('Move group');
    controller.moveSelection(const Offset(4, 2));
    await controller.commitTransaction();
    expect(controller.blocks.firstWhere((block) => block.id == 'one').x, 4);
    expect(controller.blocks.firstWhere((block) => block.id == 'two').x, 54);

    controller.ungroupSelection();
    await Future<void>.delayed(Duration.zero);
    expect(
      controller.blocks.where((block) => block.type == BlockType.group),
      isEmpty,
    );
    expect(
      controller.blocks
          .where((block) => block.type == BlockType.text)
          .every((block) => block.groupId == null),
      isTrue,
    );
  });

  test('duplicate and clipboard preserve group membership', () async {
    final controller = EditorController(
      document: _documentFromBlocks([
        _text(id: 'one'),
        _text(id: 'two', x: 50),
      ]),
      persistDocument: (EntryDocument _) async {},
    );
    addTearDown(controller.dispose);

    controller.selectMany(['one', 'two']);
    controller.groupSelection();
    await Future<void>.delayed(Duration.zero);
    controller.select('one');
    controller.duplicateSelection();
    await Future<void>.delayed(Duration.zero);
    expect(
      controller.blocks.where((b) => b.type == BlockType.group),
      hasLength(2),
    );
    final duplicatedChildren = controller.blocks
        .where((b) => b.type == BlockType.text && b.groupId != null)
        .where((b) => b.id != 'one' && b.id != 'two')
        .toList();
    expect(duplicatedChildren, hasLength(2));
    final duplicateGroupId = duplicatedChildren.first.groupId;
    expect(
      duplicatedChildren.every((b) => b.groupId == duplicateGroupId),
      isTrue,
    );

    controller.copySelection();
    controller.paste();
    await Future<void>.delayed(Duration.zero);
    expect(
      controller.blocks.where((b) => b.type == BlockType.group),
      hasLength(3),
    );
  });

  test('layer commands rename and reorder without breaking groups', () async {
    final controller = EditorController(
      document: _documentFromBlocks([
        _text(id: 'one'),
        _text(id: 'two', x: 50),
        _text(id: 'top', x: 90),
      ]),
      persistDocument: (EntryDocument _) async {},
    );
    addTearDown(controller.dispose);

    controller.selectMany(['one', 'two']);
    controller.groupSelection();
    await Future<void>.delayed(Duration.zero);
    controller.select('one');
    controller.renameSelection('Notes');
    await Future<void>.delayed(Duration.zero);
    expect(
      controller.blocks
          .where((b) => b.groupId != null)
          .every((b) => b.name == 'Notes'),
      isTrue,
    );
    controller.moveLayerForward();
    await Future<void>.delayed(Duration.zero);
    expect(controller.blocks.lastWhere((b) => b.groupId != null).name, 'Notes');
  });

  test(
    'node graph insertion remaps groups and is undoable as one command',
    () async {
      final controller = EditorController(
        document: _documentFromBlocks(const []),
        persistDocument: (EntryDocument _) async {},
      );
      addTearDown(controller.dispose);
      final group = ContentBlock(
        id: 'graph-group',
        type: BlockType.group,
        childIds: ['graph-child'],
        hidden: true,
      );
      final child = _text(id: 'graph-child', x: 4, y: 5)..groupId = group.id;
      final graph = EntryDocumentCodec.fromLegacyBlocks(
        id: 'graph',
        title: 'Composition',
        createdAt: DateTime.utc(2026),
        blocks: [group, child],
      );
      controller.insertNodeGraph(graph.nodes, offset: const Offset(10, 20));
      await Future<void>.delayed(Duration.zero);

      expect(controller.blocks, hasLength(2));
      final insertedGroup = controller.blocks.firstWhere(
        (block) => block.type == BlockType.group,
      );
      final insertedChild = controller.blocks.firstWhere(
        (block) => block.type == BlockType.text,
      );
      expect(insertedGroup.childIds, [insertedChild.id]);
      expect(insertedChild.groupId, insertedGroup.id);
      expect(insertedChild.x, 14);
      await controller.undo();
      expect(controller.blocks, isEmpty);
    },
  );

  test('board settings and creative node payloads round-trip', () {
    final entry = Entry(
      id: 'entry',
      createdAt: DateTime.utc(2026),
      board: const BoardSettings(gridVisible: true, gridSize: 12),
      blocks: [
        ContentBlock(
          id: 'shape',
          type: BlockType.shape,
          shape: 'ellipse',
          x: -12,
          y: 8,
          w: 32,
          h: 24,
          strokeColorValue: 0xFF123456,
          fillColorValue: 0x33123456,
        ),
      ],
    );

    final restored = Entry.fromJson(entry.toJson());
    expect(restored.board.gridVisible, isTrue);
    expect(restored.board.gridSize, 12);
    expect(restored.blocks.single.type, BlockType.shape);
    expect(restored.blocks.single.shape, 'ellipse');
    expect(restored.blocks.single.x, -12);
  });

  test(
    'immutable document boundary preserves node transforms and payloads',
    () {
      final entry = Entry(
        id: 'document-entry',
        title: 'Sketches',
        createdAt: DateTime.utc(2026),
        blocks: [_text(x: -8, y: 14)..opacity = 0.7],
      );
      final document = EntryDocumentCodec.fromEntry(entry);
      expect(document.nodes, hasLength(1));
      expect(document.nodes.single.transform.x, -8);
      expect(document.nodes.single.opacity, 0.7);
      expect(
        () => document.nodes.add(document.nodes.single),
        throwsUnsupportedError,
      );

      final restored = EntryDocumentCodec.toEntry(document);
      expect(restored.title, 'Sketches');
      expect(restored.blocks.single.x, -8);
      expect(restored.blocks.single.opacity, 0.7);
    },
  );

  test('immutable document boundary nests group children locally', () {
    final children = [
      _text(id: 'child-a', x: 4, y: 8),
      _text(id: 'child-b', x: 44, y: 8),
    ];
    final group = ContentBlock(
      id: 'group',
      type: BlockType.group,
      x: 4,
      y: 8,
      w: 80,
      h: 20,
      childIds: ['child-a', 'child-b'],
      hidden: true,
    );
    for (final child in children) {
      child.groupId = group.id;
    }
    final document = EntryDocumentCodec.fromEntry(
      Entry(
        id: 'nested-document',
        createdAt: DateTime.utc(2026),
        blocks: [group, ...children],
      ),
    );

    expect(document.nodes, hasLength(1));
    expect(document.nodes.single.type, BlockType.group);
    expect(document.nodes.single.children, hasLength(2));
    expect(document.nodes.single.children.first.transform.x, 0);
    expect(document.nodes.single.children.first.transform.y, 0);
    expect(document.nodes.single.children.last.transform.x, 40);

    final restored = EntryDocumentCodec.toEntry(document);
    expect(restored.blocks, hasLength(3));
    expect(restored.blocks.first.type, BlockType.group);
    expect(restored.blocks.first.childIds, ['child-a', 'child-b']);
    expect(
      restored.blocks.skip(1).every((block) => block.groupId == 'group'),
      isTrue,
    );
  });

  test('immutable render projection flattens visible leaves in world space', () {
    final document = EntryDocument(
      id: 'render-projection',
      title: 'Render',
      createdAt: DateTime.utc(2026),
      modifiedAt: DateTime.utc(2026),
      nodes: [
        CanvasNode(
          id: 'group',
          type: BlockType.group,
          transform: const Transform2D(
            x: 20,
            y: 30,
            width: 100,
            height: 80,
          ),
          children: [
            CanvasNode(
              id: 'visible-child',
              type: BlockType.text,
              transform: const Transform2D(
                x: 8,
                y: 12,
                width: 40,
                height: 20,
              ),
              payload: const {'text': 'Child'},
            ),
            CanvasNode(
              id: 'hidden-child',
              type: BlockType.shape,
              transform: const Transform2D(x: 4, y: 4, width: 20, height: 20),
              visible: false,
            ),
          ],
        ),
      ],
    );

    final renderNodes = document.renderNodes;
    expect(renderNodes, hasLength(1));
    expect(renderNodes.single.id, 'visible-child');
    expect(renderNodes.single.transform.x, 28);
    expect(renderNodes.single.transform.y, 42);
    expect(renderNodes.single.children, isEmpty);
    expect(
      () => renderNodes.add(renderNodes.single),
      throwsUnsupportedError,
    );
  });

  test('immutable editor APIs detach legacy adapters and persist documents', () async {
    final document = EntryDocument(
      id: 'immutable-editor',
      title: 'Immutable',
      createdAt: DateTime.utc(2026),
      modifiedAt: DateTime.utc(2026),
      nodes: [
        CanvasNode(
          id: 'node',
          type: BlockType.text,
          transform: const Transform2D(x: 2, y: 3, width: 40, height: 20),
          payload: const {'text': 'Hello'},
        ),
      ],
    );
    final saved = <EntryDocument>[];
    final controller = EditorController(
      document: document,
      persistDocument: (EntryDocument next) async => saved.add(next),
    );
    addTearDown(controller.dispose);

    final detached = controller.blocks.single;
    detached.x = 999;
    expect(controller.document.nodes.single.transform.x, 2);
    expect(
      () => controller.state.document.nodes.add(controller.state.document.nodes.single),
      throwsUnsupportedError,
    );

    controller.select('node');
    controller.beginTransformTransaction('Move');
    controller.moveSelection(const Offset(4, 0));
    await controller.commitTransaction();

    expect(saved, hasLength(1));
    expect(saved.single.nodes.single.transform.x, 6);
  });

  test('undo and clipboard snapshots retain referenced media IDs', () async {
    final controller = EditorController(
      document: EntryDocument(
        id: 'asset-retention',
        title: 'Assets',
        createdAt: DateTime.utc(2026),
        modifiedAt: DateTime.utc(2026),
        nodes: [
          CanvasNode(
            id: 'image',
            type: BlockType.image,
            transform: const Transform2D(width: 40, height: 40),
            payload: const {'assetId': 'asset-1'},
          ),
        ],
      ),
      persistDocument: (next) async {},
    );
    addTearDown(controller.dispose);

    controller.select('image');
    controller.copySelection();
    controller.deleteSelection();
    await Future<void>.delayed(Duration.zero);

    expect(controller.document.nodes, isEmpty);
    expect(controller.retainedAssetIds, contains('asset-1'));
    await controller.undo();
    expect(controller.retainedAssetIds, contains('asset-1'));
  });

  test('document-native group movement preserves local child transforms', () async {
    final document = EntryDocument(
      id: 'nested-editor',
      title: 'Nested',
      createdAt: DateTime.utc(2026),
      modifiedAt: DateTime.utc(2026),
      nodes: [
        CanvasNode(
          id: 'group',
          type: BlockType.group,
          transform: const Transform2D(x: 20, y: 30, width: 100, height: 80),
          children: [
            CanvasNode(
              id: 'child',
              type: BlockType.text,
              transform: const Transform2D(x: 8, y: 12, width: 40, height: 20),
              payload: const {'text': 'Child'},
            ),
          ],
        ),
      ],
    );
    final saved = <EntryDocument>[];
    final controller = EditorController(
      document: document,
      persistDocument: (next) async => saved.add(next),
    );
    addTearDown(controller.dispose);

    controller.select('group');
    controller.beginTransformTransaction('Move group');
    controller.moveSelection(const Offset(5, 7));
    await controller.commitTransaction();

    final moved = controller.document.nodes.single;
    expect(moved.transform.x, 25);
    expect(moved.transform.y, 37);
    expect(moved.children.single.transform.x, 8);
    expect(moved.children.single.transform.y, 12);
    expect(saved.single.nodes.single.children.single.transform.x, 8);

    await controller.undo();
    expect(controller.document.nodes.single.transform.x, 20);
    expect(controller.document.nodes.single.children.single.transform.x, 8);
  });
}
