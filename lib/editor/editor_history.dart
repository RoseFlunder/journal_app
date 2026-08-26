import 'package:flutter/foundation.dart';

import '../models/entry.dart';

/// A detached document state used by one editor history command.
class EditorDocumentSnapshot {
  EditorDocumentSnapshot(Iterable<ContentBlock> blocks, this.board)
    : blocks = List.unmodifiable(blocks.map((block) => block.clone()));

  final List<ContentBlock> blocks;
  final BoardSettings board;

  Map<String, dynamic> toJson() => {
    'blocks': blocks.map((block) => block.toJson()).toList(),
    'board': board.toJson(),
  };
}

/// One labeled editor transaction with its before and after states.
class EditorCommand {
  const EditorCommand({
    required this.label,
    required this.before,
    required this.after,
  });

  final String label;
  final EditorDocumentSnapshot before;
  final EditorDocumentSnapshot after;
}

/// Undo/redo and open-transaction state for an editor session.
class EditorHistory {
  EditorHistory({this.maxLength = 100});

  final int maxLength;
  final List<EditorCommand> _undo = <EditorCommand>[];
  final List<EditorCommand> _redo = <EditorCommand>[];
  EditorDocumentSnapshot? _transactionStart;
  String? _transactionLabel;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get inTransaction => _transactionStart != null;

  void begin(EditorDocumentSnapshot snapshot, String label) {
    if (inTransaction) return;
    _transactionStart = snapshot;
    _transactionLabel = label;
  }

  ({EditorDocumentSnapshot before, String label})? takeTransaction() {
    final before = _transactionStart;
    final label = _transactionLabel;
    _transactionStart = null;
    _transactionLabel = null;
    if (before == null || label == null) return null;
    return (before: before, label: label);
  }

  EditorDocumentSnapshot? cancelTransaction() {
    final before = _transactionStart;
    _transactionStart = null;
    _transactionLabel = null;
    return before;
  }

  void record(EditorCommand command) {
    _undo.add(command);
    if (_undo.length > maxLength) _undo.removeAt(0);
    _redo.clear();
  }

  EditorCommand? takeUndo() {
    if (_undo.isEmpty) return null;
    final command = _undo.removeLast();
    _redo.add(command);
    return command;
  }

  EditorCommand? takeRedo() {
    if (_redo.isEmpty) return null;
    final command = _redo.removeLast();
    _undo.add(command);
    return command;
  }

  void reset() {
    _transactionStart = null;
    _transactionLabel = null;
    _undo.clear();
    _redo.clear();
  }

  @visibleForTesting
  int get undoLength => _undo.length;

  @visibleForTesting
  int get redoLength => _redo.length;
}
