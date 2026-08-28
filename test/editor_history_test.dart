import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/editor/editor_history.dart';
import 'package:journal_app/models/document.dart';

void main() {
  test('records one transaction and moves it between undo and redo', () {
    final history = EditorHistory();
    final before = _snapshot([_text()]);
    final after = _snapshot([_text(text: 'Updated')]);

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
      history.takeUndo()?.revert(after).document.nodes.single.text,
      isEmpty,
    );
    expect(history.canRedo, isTrue);
    expect(
      history.takeRedo()?.apply(before).document.nodes.single.text,
      'Updated',
    );
  });

  test('cancelling a transaction returns its original state', () {
    final history = EditorHistory();
    final snapshot = _snapshot(const <CanvasNode>[]);

    history.begin(snapshot, 'Transform');
    expect(history.cancelTransaction(), same(snapshot));
    expect(history.inTransaction, isFalse);
    expect(history.canUndo, isFalse);
  });

  test('uses a compact typed command for transform-only edits', () {
    final before = _snapshot([_text(x: 4, y: 8)]);
    final after = _snapshot([_text(x: 12, y: 20)]);

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
    final before = _snapshot([_text(text: 'Before')]);
    final styled = _snapshot([_text(text: 'After')]);
    final board = _snapshot(
      [_text(text: 'Before')],
      board: const BoardSettings(gridVisible: true),
    );
    final inserted = _snapshot([
      _text(text: 'Before'),
      _text(id: 'new'),
    ]);

    expect(
      EditorCommand.fromStates(
        label: 'Style',
        before: before,
        after: styled,
      ),
      isA<StyleEditorCommand>(),
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
      isA<InsertEditorCommand>(),
    );
    expect(
      EditorCommand.fromStates(
        label: 'Delete',
        before: inserted,
        after: before,
      ),
      isA<DeleteEditorCommand>(),
    );
  });

  test('classifies group and reorder operations by intent', () {
    final first = _text(id: 'first');
    final second = _text(id: 'second');
    final before = _snapshot([first, second]);
    final reordered = _snapshot([second, first]);
    final grouped = _snapshot([
      CanvasNode(
        id: 'group',
        type: BlockType.group,
        transform: const Transform2D(width: 40, height: 20),
        children: [first, second],
      ),
    ]);

    expect(
      EditorCommand.fromStates(
        label: 'Reorder layer',
        before: before,
        after: reordered,
      ),
      isA<ReorderEditorCommand>(),
    );
    expect(
      EditorCommand.fromStates(
        label: 'Group',
        before: before,
        after: grouped,
      ),
      isA<GroupEditorCommand>(),
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

EditorDocumentSnapshot _snapshot(
  Iterable<CanvasNode> nodes, {
  BoardSettings board = const BoardSettings(),
}) => EditorDocumentSnapshot(
  EntryDocument(
    id: 'history',
    title: 'History',
    createdAt: DateTime.utc(2026),
    modifiedAt: DateTime.utc(2026),
    nodes: nodes,
    board: board,
  ),
);

CanvasNode _text({
  String id = 'block',
  String text = '',
  double x = 0,
  double y = 0,
}) => CanvasNode(
  id: id,
  type: BlockType.text,
  transform: Transform2D(x: x, y: y, width: 30, height: 12),
  payload: {'text': text},
);
