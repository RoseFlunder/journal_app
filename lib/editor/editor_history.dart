import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/document.dart';
import '../models/entry.dart';

/// A detached, deeply immutable document state used by one editor command.
class EditorDocumentSnapshot {
  EditorDocumentSnapshot(Iterable<ContentBlock> blocks, BoardSettings board)
    : _document = EntryDocument.fromEntry(
        Entry.newPage()
          ..blocks = blocks.map((block) => block.clone()).toList()
          ..board = board,
      );

  /// Creates a snapshot without converting through mutable storage records.
  EditorDocumentSnapshot.fromDocument(this._document);

  final EntryDocument _document;

  /// The immutable document represented by this snapshot.
  EntryDocument get document => _document;

  /// Rehydrates detached mutable adapters only at the controller boundary.
  @Deprecated('Use document.nodes instead.')
  List<ContentBlock> get blocks => _document.blocks;

  BoardSettings get board => _document.board;

  /// Returns a new snapshot with only node transforms changed.
  EditorDocumentSnapshot withTransforms(
    Iterable<NodeTransformChange> changes,
  ) => EditorDocumentSnapshot.fromDocument(
    _document.replaceLocalTransforms({
      for (final change in changes) change.id: change.after,
    }),
  );

  /// Returns the compact editor-state representation used to compare command
  /// deltas. Document metadata is persisted by the repository and is not part
  /// of an editor gesture command.
  Map<String, dynamic> toJson() => {
    'blocks': blocks.map((block) => block.toJson()).toList(growable: false),
    'board': board.toJson(),
  };
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

  /// Immutable documents whose assets must remain available while this
  /// command is reachable through undo/redo.
  Iterable<EntryDocument> get retainedDocuments => const <EntryDocument>[];

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
    final beforeIds = _nodeMap(before.document).keys.toSet();
    final afterIds = _nodeMap(after.document).keys.toSet();
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
    final beforeById = _nodeMap(before.document);
    final afterById = _nodeMap(after.document);
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
      final leftTransform = left.transform;
      final rightTransform = right.transform;
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
    if (jsonEncode(_nodeJson(before.document)) !=
        jsonEncode(_nodeJson(after.document))) {
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

  @override
  Iterable<EntryDocument> get retainedDocuments => [before.document, after.document];

  static NodeEditorCommand? tryCreate({
    required String label,
    required EditorDocumentSnapshot before,
    required EditorDocumentSnapshot after,
  }) {
    final beforeById = _nodeMap(before.document);
    final afterById = _nodeMap(after.document);
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
          jsonEncode(left.transform.toJson()) ==
              jsonEncode(right.transform.toJson())) {
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
           ..._nodeMap(before.document).keys,
           ..._nodeMap(after.document).keys,
         },
       );

  final EditorDocumentSnapshot before;
  final EditorDocumentSnapshot after;

  @override
  Iterable<EntryDocument> get retainedDocuments => [before.document, after.document];

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
  Iterable<EntryDocument> get retainedDocuments => [before.document, after.document];

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

  /// Asset IDs referenced by all reachable command snapshots and the active
  /// transaction's starting document.
  Set<String> get retainedAssetIds {
    final ids = <String>{};
    void collect(EntryDocument document) {
      void visit(Iterable<CanvasNode> nodes) {
        for (final node in nodes) {
          if (node.assetId != null) ids.add(node.assetId!);
          if (node.children.isNotEmpty) visit(node.children);
        }
      }

      visit(document.nodes);
    }

    final start = _transactionStart;
    if (start != null) collect(start.document);
    for (final command in [..._undo, ..._redo]) {
      for (final document in command.retainedDocuments) {
        collect(document);
      }
    }
    return Set.unmodifiable(ids);
  }

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

Map<String, CanvasNode> _nodeMap(EntryDocument document) {
  final result = <String, CanvasNode>{};
  void visit(Iterable<CanvasNode> nodes) {
    for (final node in nodes) {
      result[node.id] = node;
      visit(node.children);
    }
  }

  visit(document.nodes);
  return result;
}

List<Map<String, dynamic>> _nodeJson(EntryDocument document) => document.nodes
    .map((node) => node.toJson())
    .toList(growable: false);

Map<String, dynamic> _withoutTransform(CanvasNode node) {
  final json = Map<String, dynamic>.from(node.toJson());
  json.remove('transform');
  final payload = json['payload'];
  if (payload is Map) {
    final cleanPayload = Map<String, dynamic>.from(payload);
    for (final key in const <String>['x', 'y', 'w', 'h', 'rotation']) {
      cleanPayload.remove(key);
    }
    json['payload'] = cleanPayload;
  }
  // A nested transform is serialized as part of every group's child list.
  // Normalize the full subtree so moving one descendant is still classified
  // as a transform command rather than as a parent node payload edit.
  json['children'] = node.children
      .map(_withoutTransform)
      .toList(growable: false);
  return json;
}
