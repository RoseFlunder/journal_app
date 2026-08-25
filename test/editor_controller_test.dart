import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/editor/editor_controller.dart';
import 'package:journal_app/models/entry.dart';
import 'package:journal_app/models/document.dart';

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

void main() {
  test(
    'a transform transaction produces one save and supports undo/redo',
    () async {
      var saves = 0;
      final controller = EditorController(
        blocks: [_text()],
        initialBoard: const BoardSettings(),
        persistDocument: (_, _) async => saves++,
      );
      addTearDown(controller.dispose);

      controller.select('text');
      controller.beginTransaction('Transform');
      controller.moveSelection(const Offset(5, 3));
      controller.moveSelection(const Offset(2, -1));
      await controller.commitTransaction();

      expect(controller.blocks.single.x, 7);
      expect(controller.blocks.single.y, 2);
      expect(saves, 1);
      expect(controller.canUndo, isTrue);

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
      blocks: [_text()..locked = true],
      initialBoard: const BoardSettings(),
      persistDocument: (_, _) async {},
    );
    addTearDown(controller.dispose);

    controller.select('text');
    controller.beginTransaction('Transform');
    controller.moveSelection(const Offset(10, 0));
    await controller.commitTransaction();
    controller.deleteSelection();

    expect(controller.blocks, hasLength(1));
    expect(controller.blocks.single.x, 0);
    expect(controller.canUndo, isFalse);
  });

  test(
    'selection rotation updates unlocked blocks in one transaction',
    () async {
      var saves = 0;
      final controller = EditorController(
        blocks: [
          _text(id: 'one'),
          _text(id: 'two', x: 50),
          _text(id: 'locked', x: 100)..locked = true,
        ],
        initialBoard: const BoardSettings(),
        persistDocument: (_, _) async => saves++,
      );
      addTearDown(controller.dispose);

      controller.selectMany(['one', 'two', 'locked']);
      controller.beginTransaction('Transform');
      controller.rotateSelection(0.5);
      controller.rotateSelection(0.25);
      await controller.commitTransaction();

      expect(
        controller.blocks.firstWhere((block) => block.id == 'one').rotation,
        closeTo(0.75, 0.001),
      );
      expect(
        controller.blocks.firstWhere((block) => block.id == 'two').rotation,
        closeTo(0.75, 0.001),
      );
      expect(
        controller.blocks.firstWhere((block) => block.id == 'locked').rotation,
        0,
      );
      expect(saves, 1);
      expect(controller.canUndo, isTrue);
    },
  );

  test('additive selection keeps both blocks selected', () {
    final controller = EditorController(
      blocks: [
        _text(id: 'one'),
        _text(id: 'two', x: 50),
      ],
      initialBoard: const BoardSettings(),
      persistDocument: (_, _) async {},
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
      blocks: [
        _text(id: 'one'),
        _text(id: 'two', x: 50),
      ],
      initialBoard: const BoardSettings(),
      persistDocument: (_, _) async {},
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
    controller.beginTransaction('Move group');
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
      blocks: [
        _text(id: 'one'),
        _text(id: 'two', x: 50),
      ],
      initialBoard: const BoardSettings(),
      persistDocument: (_, _) async {},
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
      blocks: [
        _text(id: 'one'),
        _text(id: 'two', x: 50),
        _text(id: 'top', x: 90),
      ],
      initialBoard: const BoardSettings(),
      persistDocument: (_, _) async {},
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
    'template insertion remaps groups and is undoable as one command',
    () async {
      final controller = EditorController(
        blocks: const [],
        initialBoard: const BoardSettings(),
        persistDocument: (_, _) async {},
      );
      addTearDown(controller.dispose);
      final group = ContentBlock(
        id: 'template-group',
        type: BlockType.group,
        childIds: ['template-child'],
        hidden: true,
      );
      final child = _text(id: 'template-child', x: 4, y: 5)..groupId = group.id;
      controller.insertBlocks([group, child], offset: const Offset(10, 20));
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
      final document = EntryDocument.fromEntry(entry);
      expect(document.nodes, hasLength(1));
      expect(document.nodes.single.transform.x, -8);
      expect(document.nodes.single.opacity, 0.7);
      expect(
        () => document.nodes.add(document.nodes.single),
        throwsUnsupportedError,
      );

      final restored = document.toEntry();
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
    final document = EntryDocument.fromEntry(
      Entry(
        id: 'nested-document',
        createdAt: DateTime.utc(2026),
        blocks: [group, ...children],
      ),
    );

    expect(document.nodes, hasLength(1));
    expect(document.nodes.single.type, BlockType.group);
    expect(document.nodes.single.children, hasLength(2));

    final restored = document.toEntry();
    expect(restored.blocks, hasLength(3));
    expect(restored.blocks.first.type, BlockType.group);
    expect(restored.blocks.first.childIds, ['child-a', 'child-b']);
    expect(
      restored.blocks.skip(1).every((block) => block.groupId == 'group'),
      isTrue,
    );
  });
}
