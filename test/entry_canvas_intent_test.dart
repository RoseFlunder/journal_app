import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/editor/block_widget.dart';
import 'package:journal_app/editor/entry_canvas.dart';
import 'package:journal_app/models/document.dart';
import 'package:journal_app/models/entry.dart';

void main() {
  testWidgets('canvas emits immutable transform intents', (tester) async {
    final block = ContentBlock(
      id: 'intent-block',
      type: BlockType.text,
      text: 'Move me',
      x: 4,
      y: 4,
      w: 30,
      h: 20,
    );
    Transform2D? intent;

    await tester.pumpWidget(
      MaterialApp(
        home: EntryCanvas(
          workspaceSize: const Size(400, 300),
          nodes: [CanvasNode.fromBlock(block)],
          editing: true,
          selectedId: block.id,
          textEditingId: null,
          onSelect: (_) {},
          onEditText: (_) {},
          onTransformChanged: (id, transform) {
            expect(id, block.id);
            intent = transform;
          },
          imageBytes: (_) => null,
          onOpenImage: (_) {},
        ),
      ),
    );
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(BlockWidget)),
    );
    await gesture.moveBy(const Offset(20, 10));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));

    expect(intent, isNotNull);
    expect(intent!.x, closeTo(6, 0.01));
    expect(intent!.y, closeTo(5, 0.01));
    expect(block.x, 4);
    expect(block.y, 4);
  });
}
