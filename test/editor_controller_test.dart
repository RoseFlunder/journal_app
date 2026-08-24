import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/editor/editor_controller.dart';
import 'package:journal_app/models/entry.dart';

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
}
