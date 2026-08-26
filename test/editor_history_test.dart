import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/editor/editor_history.dart';
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
}
