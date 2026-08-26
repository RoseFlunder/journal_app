import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/document.dart';
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

  /// Returns a new snapshot with only node transforms changed.
  EditorDocumentSnapshot withTransforms(
    Iterable<NodeTransformChange> changes,
  ) {
    final next = blocks;
    final byId = <String, ContentBlock>{
      for (final block in next) block.id: block,
    };
    for (final change in changes) {
      final block = byId[change.id];
      if (block == null) continue;
      block
        ..x = change.after.x
        ..y = change.after.y
        ..w = change.after.width
        ..h = change.after.height
        ..rotation = change.after.rotation;
    }
    return EditorDocumentSnapshot(next, board);
  }

  Map<String, dynamic> toJson() => _copyMap(_data);
}

/// Immutable transform delta for one node in a typed transform command.
class NodeTransformChange {
  const NodeTransformChange({
    required this.id,
    required this.before,
    required this.after,
  });

  final String id;
  final Transform2D before;
  final Transform2D after;
}

/// Typed editor command contract used by undo and redo.
sealed class EditorCommand {
  EditorCommand({required this.label, required Set<String> affectedIds})
    : affectedIds = Set.unmodifiable(affectedIds);

  final String label;
  final Set<String> affectedIds;

  EditorDocumentSnapshot apply(EditorDocumentSnapshot state);

  EditorDocumentSnapshot revert(EditorDocumentSnapshot state);

  /// Selects the narrowest command representation available for two states.
  factory EditorCommand.fromStates({
    required String label,
    required EditorDocumentSnapshot before,
    required EditorDocumentSnapshot after,
  }) {
    final transform = TransformEditorCommand.tryCreate(
      label: label,
      before: before,
      after: after,
    );
    if (transform != null) return transform;
    final board = BoardEditorCommand.tryCreate(
      label: label,
      before: before,
      after: after,
    );
    if (board != null) return board;
    final nodes = NodeEditorCommand.tryCreate(
      label: label,
      before: before,
      after: after,
    );
    if (nodes != null) return nodes;
    final beforeIds = before.blocks.map((block) => block.id).toSet();
    final afterIds = after.blocks.map((block) => block.id).toSet();
    if (!setEquals(beforeIds, afterIds)) {
      return StructuralEditorCommand(
        label: label,
        before: before,
        after: after,
      );
    }
    return DocumentReplacementCommand(
      label: label,
      before: before,
      after: after,
    );
  }
}

/// Compact command for a gesture that changes only node transforms.
final class TransformEditorCommand extends EditorCommand {
  TransformEditorCommand({
    required super.label,
    required super.affectedIds,
    required this.changes,
  });

  final List<NodeTransformChange> changes;

  static TransformEditorCommand? tryCreate({
    required String label,
    required EditorDocumentSnapshot before,
    required EditorDocumentSnapshot after,
  }) {
    if (jsonEncode(before.board.toJson()) !=
        jsonEncode(after.board.toJson())) {
      return null;
    }
    final beforeById = {for (final block in before.blocks) block.id: block};
    final afterById = {for (final block in after.blocks) block.id: block};
    if (beforeById.length != afterById.length ||
        !beforeById.keys.toSet().containsAll(afterById.keys)) {
      return null;
    }

    final changes = <NodeTransformChange>[];
    for (final id in beforeById.keys) {
      final left = beforeById[id]!;
      final right = afterById[id]!;
      if (jsonEncode(_withoutTransform(left)) !=
          jsonEncode(_withoutTransform(right))) {
        return null;
      }
      final leftTransform = _transformOf(left);
      final rightTransform = _transformOf(right);
      if (jsonEncode(leftTransform.toJson()) !=
          jsonEncode(rightTransform.toJson())) {
        changes.add(
          NodeTransformChange(
            id: id,
            before: leftTransform,
            after: rightTransform,
          ),
        );
      }
    }
    if (changes.isEmpty) return null;
    return TransformEditorCommand(
      label: label,
      affectedIds: changes.map((change) => change.id).toSet(),
      changes: List.unmodifiable(changes),
    );
  }

  @override
  EditorDocumentSnapshot apply(EditorDocumentSnapshot state) =>
      state.withTransforms(changes);

  @override
  EditorDocumentSnapshot revert(EditorDocumentSnapshot state) =>
      state.withTransforms(
        changes.map(
          (change) => NodeTransformChange(
            id: change.id,
            before: change.after,
            after: change.before,
          ),
        ),
      );
}

/// Typed command for a board-only change such as grid visibility or snapping.
final class BoardEditorCommand extends EditorCommand {
  BoardEditorCommand({
    required super.label,
    required this.before,
    required this.after,
  }) : super(affectedIds: const <String>{});

  final EditorDocumentSnapshot before;
  final EditorDocumentSnapshot after;

  static BoardEditorCommand? tryCreate({
    required String label,
    required EditorDocumentSnapshot before,
    required EditorDocumentSnapshot after,
  }) {
    if (jsonEncode(before.blocks.map((block) => block.toJson()).toList()) !=
        jsonEncode(after.blocks.map((block) => block.toJson()).toList())) {
      return null;
    }
    if (jsonEncode(before.board.toJson()) == jsonEncode(after.board.toJson())) {
      return null;
    }
    return BoardEditorCommand(label: label, before: before, after: after);
  }

  @override
  EditorDocumentSnapshot apply(EditorDocumentSnapshot state) => after;

  @override
  EditorDocumentSnapshot revert(EditorDocumentSnapshot state) => before;
}

/// Typed command for a style, content, visibility, or other node payload edit.
final class NodeEditorCommand extends EditorCommand {
  NodeEditorCommand({
    required super.label,
    required super.affectedIds,
    required this.before,
    required this.after,
  });

  final EditorDocumentSnapshot before;
  final EditorDocumentSnapshot after;

  static NodeEditorCommand? tryCreate({
    required String label,
    required EditorDocumentSnapshot before,
    required EditorDocumentSnapshot after,
  }) {
    final beforeById = {for (final block in before.blocks) block.id: block};
    final afterById = {for (final block in after.blocks) block.id: block};
    if (beforeById.length != afterById.length ||
        !beforeById.keys.toSet().containsAll(afterById.keys) ||
        jsonEncode(before.board.toJson()) != jsonEncode(after.board.toJson())) {
      return null;
    }
    final changed = <String>{};
    for (final id in beforeById.keys) {
      final left = beforeById[id]!;
      final right = afterById[id]!;
      if (jsonEncode(_withoutTransform(left)) !=
              jsonEncode(_withoutTransform(right)) &&
          jsonEncode(_transformOf(left).toJson()) ==
              jsonEncode(_transformOf(right).toJson())) {
        changed.add(id);
      }
    }
    if (changed.isEmpty) return null;
    return NodeEditorCommand(
      label: label,
      affectedIds: changed,
      before: before,
      after: after,
    );
  }

  @override
  EditorDocumentSnapshot apply(EditorDocumentSnapshot state) => after;

  @override
  EditorDocumentSnapshot revert(EditorDocumentSnapshot state) => before;
}

/// Typed command for insertion, deletion, grouping, and layer reordering.
final class StructuralEditorCommand extends EditorCommand {
  StructuralEditorCommand({
    required super.label,
    required this.before,
    required this.after,
  }) : super(
         affectedIds: {
           ...before.blocks.map((block) => block.id),
           ...after.blocks.map((block) => block.id),
         },
       );

  final EditorDocumentSnapshot before;
  final EditorDocumentSnapshot after;

  @override
  EditorDocumentSnapshot apply(EditorDocumentSnapshot state) => after;

  @override
  EditorDocumentSnapshot revert(EditorDocumentSnapshot state) => before;
}

/// Transitional command for insertions, deletions, styles, and board edits.
/// It keeps the command API typed while those operations gain specialized
/// deltas in later editor slices.
final class DocumentReplacementCommand extends EditorCommand {
  DocumentReplacementCommand({
    required super.label,
    required this.before,
    required this.after,
  }) : super(affectedIds: const <String>{});

  final EditorDocumentSnapshot before;
  final EditorDocumentSnapshot after;

  @override
  EditorDocumentSnapshot apply(EditorDocumentSnapshot state) => after;

  @override
  EditorDocumentSnapshot revert(EditorDocumentSnapshot state) => before;
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

Transform2D _transformOf(ContentBlock block) => Transform2D(
  x: block.x,
  y: block.y,
  width: block.w,
  height: block.h,
  rotation: block.rotation,
);

Map<String, dynamic> _withoutTransform(ContentBlock block) {
  final json = Map<String, dynamic>.from(block.toJson());
  for (final key in const <String>['x', 'y', 'w', 'h', 'rotation']) {
    json.remove(key);
  }
  return json;
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
