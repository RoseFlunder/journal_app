import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/editor/editor_history.dart';
import 'package:journal_app/models/document.dart';
import 'package:journal_app/models/entry.dart';

void main() {
  test('records one transaction and moves it between undo and redo', () {
    final history = EditorHistory();
    final before = EditorDocumentSnapshot([
      ContentBlock(id: 'block', type: BlockType.text),
    ], const BoardSettings());
    final after = EditorDocumentSnapshot([
      ContentBlock(id: 'block', type: BlockType.text, text: 'Updated'),
    ], const BoardSettings());

    history.begin(before, 'Edit text');
    final transaction = history.takeTransaction();
    expect(transaction?.label, 'Edit text');
    history.record(
      EditorCommand.fromStates(
        label: transaction!.label,
        before: before,
        after: after,
      ),
    );

    expect(history.canUndo, isTrue);
    expect(
      history.takeUndo()?.revert(after).blocks.single.text,
      isEmpty,
    );
    expect(history.canRedo, isTrue);
    expect(
      history.takeRedo()?.apply(before).blocks.single.text,
      'Updated',
    );
  });

  test('cancelling a transaction returns its original state', () {
    final history = EditorHistory();
    final snapshot = EditorDocumentSnapshot(
      const <ContentBlock>[],
      const BoardSettings(),
    );

    history.begin(snapshot, 'Transform');
    expect(history.cancelTransaction(), same(snapshot));
    expect(history.inTransaction, isFalse);
    expect(history.canUndo, isFalse);
  });

  test('uses a compact typed command for transform-only edits', () {
    final before = EditorDocumentSnapshot([
      ContentBlock(id: 'block', type: BlockType.text, x: 4, y: 8),
    ], const BoardSettings());
    final after = EditorDocumentSnapshot([
      ContentBlock(id: 'block', type: BlockType.text, x: 12, y: 20),
    ], const BoardSettings());

    final command = EditorCommand.fromStates(
      label: 'Move',
      before: before,
      after: after,
    );

    expect(command, isA<TransformEditorCommand>());
    expect(command.affectedIds, contains('block'));
    expect(command.revert(after).toJson(), before.toJson());
    expect(command.apply(before).toJson(), after.toJson());
  });

  test('classifies board, node, and structural changes by intent', () {
    final before = EditorDocumentSnapshot([
      ContentBlock(id: 'block', type: BlockType.text, text: 'Before'),
    ], const BoardSettings());
    final styled = EditorDocumentSnapshot([
      ContentBlock(id: 'block', type: BlockType.text, text: 'After'),
    ], const BoardSettings());
    final board = EditorDocumentSnapshot([
      ContentBlock(id: 'block', type: BlockType.text, text: 'Before'),
    ], const BoardSettings(gridVisible: true));
    final inserted = EditorDocumentSnapshot([
      ContentBlock(id: 'block', type: BlockType.text, text: 'Before'),
      ContentBlock(id: 'new', type: BlockType.text),
    ], const BoardSettings());

    expect(
      EditorCommand.fromStates(
        label: 'Style',
        before: before,
        after: styled,
      ),
      isA<NodeEditorCommand>(),
    );
    expect(
      EditorCommand.fromStates(
        label: 'Grid',
        before: before,
        after: board,
      ),
      isA<BoardEditorCommand>(),
    );
    expect(
      EditorCommand.fromStates(
        label: 'Insert',
        before: before,
        after: inserted,
      ),
      isA<StructuralEditorCommand>(),
    );
  });

  test('transform commands apply nested node-local deltas', () {
    final beforeDocument = EntryDocument(
      id: 'history-nested',
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
    final afterDocument = beforeDocument.replaceLocalTransforms({
      'child': const Transform2D(x: 12, y: 12, width: 40, height: 20),
    });
    final before = EditorDocumentSnapshot.fromDocument(beforeDocument);
    final after = EditorDocumentSnapshot.fromDocument(afterDocument);
    final command = EditorCommand.fromStates(
      label: 'Move child',
      before: before,
      after: after,
    );

    expect(command, isA<TransformEditorCommand>());
    expect(
      command.revert(after).document.nodes.single.children.single.transform.x,
      8,
    );
    expect(
      command.apply(before).document.nodes.single.children.single.transform.x,
      12,
    );
  });
}
