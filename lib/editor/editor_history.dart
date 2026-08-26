import 'package:flutter/foundation.dart';

import '../models/entry.dart';

/// A detached, deeply immutable document state used by one editor command.
class EditorDocumentSnapshot {
  EditorDocumentSnapshot(Iterable<ContentBlock> blocks, BoardSettings board)
    : _data = _freeze(<String, dynamic>{
        'blocks': blocks.map((block) => block.toJson()).toList(growable: false),
        'board': board.toJson(),
      });

  final Map<String, dynamic> _data;

  /// Rehydrates detached mutable adapters only at the controller boundary.
  List<ContentBlock> get blocks => _blocksFrom(_data['blocks']);

  BoardSettings get board => BoardSettings.fromJson(
    Map<String, dynamic>.from(_data['board'] as Map<Object?, Object?>),
  );

  Map<String, dynamic> toJson() => _copyMap(_data);
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

List<ContentBlock> _blocksFrom(Object? raw) {
  if (raw is! List<Object?>) return <ContentBlock>[];
  return raw
      .whereType<Map<Object?, Object?>>()
      .map((block) => ContentBlock.fromJson(_copyMap(block)))
      .toList(growable: false);
}

Map<String, dynamic> _copyMap(Map<Object?, Object?> source) => <String, dynamic>{
  for (final entry in source.entries)
    entry.key.toString(): _copyValue(entry.value),
};

Object? _copyValue(Object? value) => switch (value) {
  Map<Object?, Object?> map => _copyMap(map),
  List<Object?> list => list.map(_copyValue).toList(growable: false),
  _ => value,
};

Map<String, dynamic> _freeze(Map<String, dynamic> source) =>
    Map<String, dynamic>.unmodifiable(
      source.map((key, value) => MapEntry(key, _freezeValue(value))),
    );

Object? _freezeValue(Object? value) => switch (value) {
  Map<Object?, Object?> map => _freeze(_copyMap(map)),
  List<Object?> list => List<Object?>.unmodifiable(
    list.map(_freezeValue).toList(growable: false),
  ),
  _ => value,
};
