// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/document.dart';
import 'editor_state.dart';
import 'editor_history.dart';
import 'geometry_services.dart';

/// Local, transactional editing state for one entry. Pointer updates mutate
/// only this controller; persistence happens once when a transaction commits.
class EditorController extends ChangeNotifier {
  EditorController({
    required EntryDocument document,
    required Future<void> Function(EntryDocument) persistDocument,
    this.maxHistory = 100,
  }) : _document = document,
       _onSave = persistDocument;

  static const _uuid = Uuid();

  final Future<void> Function(EntryDocument) _onSave;
  EntryDocument _document;
  final int maxHistory;
  late final EditorHistory _history = EditorHistory(maxLength: maxHistory);
  final Set<String> _selection = <String>{};
  List<CanvasNode> _clipboard = <CanvasNode>[];
  Set<String> _clipboardSelection = <String>{};
  Timer? _textTimer;
  EditorSaveState _saveState = EditorSaveState.saved;

  /// Immutable leaf projection consumed by the modern canvas renderer.
  List<CanvasNode> get renderNodes => _document.renderNodes;
  List<CanvasNode> get nodes => document.nodes;
  /// Immutable structural projection used by layers and inspectors.
  List<CanvasNode> get allNodes => _allDocumentNodes;
  EntryDocument get document => _document;
  BoardSettings get board => _document.board;
  Set<String> get selection => Set.unmodifiable(_selection);
  bool get hasSelection => _selection.isNotEmpty;
  bool get canUndo => _history.canUndo;
  bool get canRedo => _history.canRedo;
  bool get inTransaction => _history.inTransaction;
  bool get canPaste => _clipboard.isNotEmpty;
  /// Asset IDs kept alive by clipboard and undo/redo snapshots.
  Set<String> get retainedAssetIds => Set.unmodifiable({
    ..._history.retainedAssetIds,
    ..._assetIdsInNodes(_clipboard),
  });
  bool get canGroup => _expandedSelectedNodes.length > 1;
  bool get canUngroup =>
      _expandedSelectedNodes.any((node) => node.groupId != null) ||
      _selectedNodes.any((node) => node.type == BlockType.group);
  EditorSaveState get saveState => _saveState;

  EditorState get state => EditorState(
    document: document,
    selection: _selection,
    canUndo: canUndo,
    canRedo: canRedo,
    inTransaction: inTransaction,
    canPaste: canPaste,
    saveState: saveState,
  );

  /// Immutable primary selection for feature views. Unlike
  /// [primarySelection], this never creates a mutable compatibility adapter.
  CanvasNode? get primaryNode =>
      _selection.isEmpty ? null : _document.nodeById(_selection.last);

  /// Immutable drawable selections, including descendants of selected groups.
  List<CanvasNode> get selectedDrawableNodes {
    return List<CanvasNode>.unmodifiable(
      _expandedSelectedNodes.where(
        (node) => node.type == BlockType.ink || node.type == BlockType.shape,
      ),
    );
  }

  /// Replaces one immutable node at the editor boundary.
  void replaceNode(CanvasNode node, {String label = 'Edit node'}) {
    final current = _document.nodeById(node.id);
    if (current == null || current.locked) return;
    if (!_history.inTransaction) {
      beginNodeTransaction(label);
    }
    _document = _document.replaceNode(node);
    notifyListeners();
  }

  /// Applies a canvas gesture's immutable world-space transform to one node.
  /// Parent-local coordinates are recalculated by [EntryDocument], so nested
  /// group children remain stable when a parent is moved.
  void replaceNodeWorldTransform(
    String id,
    Transform2D transform, {
    String label = 'Transform node',
  }) {
    final node = _document.nodeById(id);
    if (node == null || node.locked) return;
    if (!_history.inTransaction) {
      beginTransformTransaction(label);
    }
    _document = _document.replaceWorldTransforms({id: transform});
    notifyListeners();
  }

  /// Inserts a node through the immutable editor boundary.
  void addNode(CanvasNode node, {bool select = true}) {
    if (_document.nodeById(node.id) != null) return;
    beginInsertTransaction('Add ${node.type.name}');
    _document = _document.insertNodes([node]);
    if (select) {
      _selection
        ..clear()
        ..add(node.id);
    }
    notifyListeners();
    unawaited(commitTransaction());
  }

  void select(String? id, {bool additive = false}) {
    if (id == null) {
      if (_selection.isEmpty) return;
      _selection.clear();
    } else if (additive) {
      if (!_selection.add(id)) _selection.remove(id);
    } else if (_selection.length != 1 || !_selection.contains(id)) {
      _selection
        ..clear()
        ..add(id);
    } else {
      return;
    }
    notifyListeners();
  }

  void selectAll() {
    final next = _allDocumentNodes
        .where((node) => node.type != BlockType.group && node.visible)
        .map((node) => node.id)
        .toSet();
    if (setEquals(next, _selection)) return;
    _selection
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  void selectMany(Iterable<String> ids) {
    final next = ids.toSet();
    if (setEquals(next, _selection)) return;
    _selection
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  void beginTransformTransaction(String label) =>
      _beginTransaction(label, EditorCommandKind.transform);

  void beginStyleTransaction(String label) =>
      _beginTransaction(label, EditorCommandKind.style);

  void beginNodeTransaction(String label) =>
      _beginTransaction(label, EditorCommandKind.node);

  void beginBoardTransaction(String label) =>
      _beginTransaction(label, EditorCommandKind.board);

  void beginInsertTransaction(String label) =>
      _beginTransaction(label, EditorCommandKind.insert);

  void beginDeleteTransaction(String label) =>
      _beginTransaction(label, EditorCommandKind.delete);

  void beginGroupTransaction(String label) =>
      _beginTransaction(label, EditorCommandKind.group);

  void beginReorderTransaction(String label) =>
      _beginTransaction(label, EditorCommandKind.reorder);

  void _beginTransaction(String label, EditorCommandKind kind) {
    _textTimer?.cancel();
    _history.begin(_snapshot(), label, kind: kind);
  }

  Future<void> commitTransaction() async {
    _textTimer?.cancel();
    final transaction = _history.takeTransaction();
    if (transaction == null) return;
    await _commit(transaction.before, transaction.label, transaction.kind);
  }

  void cancelTransaction() {
    _textTimer?.cancel();
    final before = _history.cancelTransaction();
    if (before == null) return;
    _restore(before);
    notifyListeners();
  }

  /// Updates the stroke presentation of every selected, unlocked drawable.
  ///
  /// The caller owns the surrounding transaction so a continuous color
  /// picker interaction can be undone as one edit.
  void updateSelectedDrawableStroke({
    required int colorValue,
    required double opacity,
  }) {
    final ids = _expandedSelectedNodes
        .where(
          (node) =>
              node.type == BlockType.ink || node.type == BlockType.shape,
        )
        .map((node) => node.id)
        .toSet();
    if (ids.isEmpty) return;
    beginStyleTransaction('Stroke');
    for (final id in ids) {
      final node = _nodeById(id);
      if (node == null || node.locked) continue;
      final payload = Map<String, dynamic>.from(node.payload)
        ..['strokeColorValue'] = colorValue;
      _document = _document.replaceNode(
        node.copyWith(payload: payload, opacity: opacity),
      );
    }
    notifyListeners();
  }

  void moveSelection(Offset delta, {bool snap = false}) {
    final transforms = <String, Transform2D>{};
    for (final node in _expandedSelectedNodes) {
      final block = _worldNode(node);
      if (node.locked) continue;
      var x = block.x + delta.dx;
      var y = block.y + delta.dy;
      if (snap && board.snapToGrid) {
        x = _snap(x);
        y = _snap(y);
      }
      transforms[node.id] = Transform2D(
        x: x,
        y: y,
        width: block.w,
        height: block.h,
        rotation: block.rotation,
      );
    }
    if (transforms.isEmpty) return;
    _document = _document.replaceWorldTransforms(transforms);
    notifyListeners();
  }

  /// Rotates every selected, unlocked rendered block around its own center.
  /// The caller owns the surrounding transaction so a continuous gesture is
  /// committed as one undoable command.
  void rotateSelection(double delta) {
    final transforms = <String, Transform2D>{};
    for (final node in _expandedSelectedNodes) {
      final block = _worldNode(node);
      if (node.locked) continue;
      transforms[node.id] = Transform2D(
        x: block.x,
        y: block.y,
        width: block.w,
        height: block.h,
        rotation: block.rotation + delta,
      );
    }
    if (transforms.isEmpty) return;
    _document = _document.replaceWorldTransforms(transforms);
    notifyListeners();
  }

  /// Rotates [blockIds] as a rigid selection around [pivot]. Group members are
  /// expanded in the same way as other selection transforms.
  ///
  /// The pivot is expressed in page-local model coordinates and remains fixed
  /// for the lifetime of the gesture. The caller owns the surrounding
  /// transaction so all pointer updates become one undoable command.
  void rotateBlocksAround(
    Iterable<String> blockIds,
    Offset pivot,
    double delta,
  ) {
    final cosine = math.cos(delta);
    final sine = math.sin(delta);
    final requestedIds = blockIds.toSet();
    final currentNodes = _allDocumentNodes;
    final targetIds = <String>{...requestedIds};
    for (final node in currentNodes.where(
      (node) => requestedIds.contains(node.id),
    )) {
      if (node.type == BlockType.group) {
        targetIds.addAll(_descendantIds(node));
      } else {
        final parentId = _parentById[node.id];
        final parent = parentId == null ? null : _nodeById(parentId);
        if (parent?.type == BlockType.group) {
          targetIds.addAll(_descendantIds(parent!));
        }
      }
    }
    final transforms = <String, Transform2D>{};
    for (final id in targetIds) {
      final node = _nodeById(id);
      if (node == null || node.locked || !node.visible) continue;
      final block = _worldNode(node);
      final center = Offset(block.x + block.w / 2, block.y + block.h / 2);
      final relative = center - pivot;
      final rotatedCenter =
          pivot +
          Offset(
            relative.dx * cosine - relative.dy * sine,
            relative.dx * sine + relative.dy * cosine,
          );
      transforms[id] = Transform2D(
        x: rotatedCenter.dx - block.w / 2,
        y: rotatedCenter.dy - block.h / 2,
        width: block.w,
        height: block.h,
        rotation: block.rotation + delta,
      );
    }
    if (transforms.isEmpty) return;
    _document = _document.replaceWorldTransforms(transforms);
    notifyListeners();
  }

  /// Snaps the current selection once at the end of a gesture. Keeping raw
  /// pointer deltas during the gesture prevents small movements from being
  /// rounded away on every pointer event.
  void snapSelection() {
    if (!board.snapToGrid || _selection.isEmpty) return;
    final transforms = <String, Transform2D>{};
    for (final node in _expandedSelectedNodes) {
      final block = _worldNode(node);
      if (node.locked) continue;
      transforms[node.id] = Transform2D(
        x: _snap(block.x),
        y: _snap(block.y),
        width: block.w,
        height: block.h,
        rotation: block.rotation,
      );
    }
    _document = _document.replaceWorldTransforms(transforms);
    notifyListeners();
  }

  void nudge(Offset delta) {
    beginTransformTransaction('Nudge');
    moveSelection(delta, snap: false);
    unawaited(commitTransaction());
  }

  void updateBoard(BoardSettings next) {
    beginBoardTransaction('Board settings');
    _document = _document.copyWith(board: next);
    notifyListeners();
    unawaited(commitTransaction());
  }

  /// Updates document metadata without creating an editor command. Metadata
  /// edits are persisted by the feature view model; node edits remain
  /// transactional and undoable.
  @protected
  void updateDocumentMetadata(EntryDocument next) {
    if (next.id != _document.id) return;
    _document = next;
    notifyListeners();
  }

  /// Inserts a complete node graph as one command, remapping every node
  /// and group reference so the source remains reusable.
  void insertNodeGraph(
    Iterable<CanvasNode> sources, {
    Offset offset = Offset.zero,
    String label = 'Insert composition',
  }) {
    final sourceList = List<CanvasNode>.unmodifiable(sources);
    if (sourceList.isEmpty) return;
    beginInsertTransaction(label);
    final idMap = <String, String>{};
    void collect(CanvasNode node) {
      idMap[node.id] = _uuid.v4();
      for (final child in node.children) {
        collect(child);
      }
    }

    for (final node in sourceList) {
      collect(node);
    }
    final inserted = sourceList
        .map(
          (node) => _remapClipboardNode(
            node,
            idMap,
            offset: offset,
          ),
        )
        .toList(growable: false);
    _document = _document.insertNodes(inserted);
    _selection
      ..clear()
      ..addAll(
        _flattenNodeIds(inserted).where(
          (id) => _document.nodeById(id)?.type != BlockType.group,
        ),
      );
    notifyListeners();
    unawaited(commitTransaction());
  }

  void deleteSelection() {
    if (_selection.isEmpty) return;
    beginDeleteTransaction('Delete');
    final expanded = _expandedSelectedNodes;
    final selected = expanded
        .where((node) => !node.locked)
        .map((node) => node.id)
        .toSet();
    final remaining = _allDocumentNodes.where((node) => !selected.contains(node.id));
    final liveGroupIds = remaining
        .where((node) => node.groupId != null)
        .map((node) => node.groupId!)
        .toSet();
    final emptyGroups = _allDocumentNodes
        .where(
          (node) =>
              node.type == BlockType.group && !liveGroupIds.contains(node.id),
        )
        .map((node) => node.id);
    _document = _document.removeNodes({...selected, ...emptyGroups});
    _selection.removeWhere((id) => _nodeById(id) == null);
    notifyListeners();
    unawaited(commitTransaction());
  }

  void duplicateSelection() {
    final selected = _selectedGraphNodes;
    if (selected.isEmpty) return;
    beginInsertTransaction('Duplicate');
    final selectedIds = Set<String>.from(_selection);
    final idMap = <String, String>{
      for (final id in _collectNodeIds(selected)) id: _uuid.v4(),
    };
    final copies = selected
        .map(
          (node) => _remapClipboardNode(
            node,
            idMap,
            offset: const Offset(4, 4),
            rename: true,
          ),
        )
        .toList(growable: false);
    _document = _document.insertNodes(copies);
    _selection
      ..clear()
      ..addAll(
        selectedIds
            .map((id) => idMap[id])
            .whereType<String>()
            .followedBy(
              _selection.isEmpty
                  ? copies.map((node) => node.id)
                  : const <String>[],
            ),
      );
    if (_selection.isEmpty) {
      _selection.addAll(copies.map((node) => node.id));
    }
    notifyListeners();
    unawaited(commitTransaction());
  }

  void copySelection() {
    _clipboard = _selectedGraphNodes;
    _clipboardSelection = Set<String>.from(_selection);
    notifyListeners();
  }

  void cutSelection() {
    if (_selection.isEmpty) return;
    copySelection();
    deleteSelection();
  }

  void paste({Offset offset = const Offset(4, 4)}) {
    if (_clipboard.isEmpty) return;
    beginInsertTransaction('Paste');
    final idMap = <String, String>{};
    void collect(CanvasNode node) {
      idMap[node.id] = _uuid.v4();
      for (final child in node.children) {
        collect(child);
      }
    }

    for (final source in _clipboard) {
      collect(source);
    }
    final pasted = _clipboard
        .map(
          (source) => _remapClipboardNode(
            source,
            idMap,
            offset: offset,
          ),
        )
        .toList(growable: false);
    _document = _document.insertNodes(pasted);
    _selection
      ..clear()
      ..addAll(_clipboardSelection.map((id) => idMap[id]).whereType<String>());
    if (_selection.isEmpty) {
      _selection.addAll(pasted.map((node) => node.id));
    }
    notifyListeners();
    unawaited(commitTransaction());
  }

  void setLocked(bool locked) => _updateSelectedNodes(
    locked ? 'Lock' : 'Unlock',
    (node) => node.copyWith(locked: locked),
  );

  void setHidden(bool hidden) => _updateSelectedNodes(
    hidden ? 'Hide' : 'Show',
    (node) => node.copyWith(visible: !hidden),
  );

  void bringToFront() {
    if (_selection.isEmpty) return;
    beginReorderTransaction('Bring to front');
    final ids = _expandedSelectedNodes.map((node) => node.id).toSet();
    _document = _document.reorderNodes(ids, toEnd: true);
    notifyListeners();
    unawaited(commitTransaction());
  }

  void sendToBack() {
    if (_selection.isEmpty) return;
    beginReorderTransaction('Send to back');
    final ids = _expandedSelectedNodes.map((node) => node.id).toSet();
    _document = _document.reorderNodes(ids, toEnd: false);
    notifyListeners();
    unawaited(commitTransaction());
  }

  void moveLayerForward() {
    final node = primaryNode;
    if (node == null) return;
    final index = _siblingIndex(node.id);
    if (index < 0 || index >= _siblingCount(node.id) - 1) return;
    reorderLayer(node.id, index + 1);
  }

  void moveLayerBackward() {
    final node = primaryNode;
    if (node == null) return;
    final index = _siblingIndex(node.id);
    if (index <= 0) return;
    reorderLayer(node.id, index - 1);
  }

  void reorderLayer(String blockId, int targetIndex) {
    final source = _nodeById(blockId);
    if (source == null) return;
    beginReorderTransaction('Reorder layer');
    _document = _document.reorderNode(blockId, targetIndex);
    notifyListeners();
    unawaited(commitTransaction());
  }

  void renameSelection(String name) {
    if (_selection.isEmpty) return;
    final normalized = name.trim();
    if (normalized.isEmpty) return;
    _updateSelectedNodes(
      'Rename',
      (node) => node.copyWith(accessibilityLabel: normalized),
    );
  }

  void renameLayer(String blockId, String name) {
    final normalized = name.trim();
    final node = _document.nodeById(blockId);
    if (node == null || normalized.isEmpty) return;
    beginNodeTransaction('Rename layer');
    _document = _document.replaceNode(
      node.copyWith(accessibilityLabel: normalized),
    );
    notifyListeners();
    unawaited(commitTransaction());
  }

  void align(Alignment alignment) {
    final selected = _expandedSelectedNodes
        .where((node) => node.type != BlockType.group)
        .map(_worldNode)
        .toList(growable: false);
    if (selected.length < 2) return;
    beginTransformTransaction('Align');
    final bounds = _boundsFor(selected);
    final transforms = <String, Transform2D>{};
    for (final block in selected) {
      if (block.locked) continue;
      var x = block.x;
      var y = block.y;
      switch (alignment) {
        case Alignment.topLeft:
          x = bounds.left;
          y = bounds.top;
        case Alignment.topCenter:
          x = bounds.center.dx - block.w / 2;
          y = bounds.top;
        case Alignment.topRight:
          x = bounds.right - block.w;
          y = bounds.top;
        case Alignment.centerLeft:
          x = bounds.left;
          y = bounds.center.dy - block.h / 2;
        case Alignment.center:
          x = bounds.center.dx - block.w / 2;
          y = bounds.center.dy - block.h / 2;
        case Alignment.centerRight:
          x = bounds.right - block.w;
          y = bounds.center.dy - block.h / 2;
        case Alignment.bottomLeft:
          x = bounds.left;
          y = bounds.bottom - block.h;
        case Alignment.bottomCenter:
          x = bounds.center.dx - block.w / 2;
          y = bounds.bottom - block.h;
        case Alignment.bottomRight:
          x = bounds.right - block.w;
          y = bounds.bottom - block.h;
      }
      transforms[block.id] = Transform2D(
        x: x,
        y: y,
        width: block.w,
        height: block.h,
        rotation: block.rotation,
      );
    }
    _document = _document.replaceWorldTransforms(transforms);
    notifyListeners();
    unawaited(commitTransaction());
  }

  void groupSelection() {
    final children = _expandedSelectedNodes
        .where((node) => node.type != BlockType.group)
        .toList();
    if (children.length < 2) return;
    beginGroupTransaction('Group');
    final groupId = _uuid.v4();
    _document = _document.groupNodes(
      children.map((node) => node.id),
      groupId: groupId,
    );
    _selection
      ..clear()
      ..addAll(children.map((node) => node.id));
    notifyListeners();
    unawaited(commitTransaction());
  }

  void ungroupSelection() {
    final parents = _parentById;
    final groupIds = _expandedSelectedNodes
        .where((node) => node.type == BlockType.group || parents[node.id] != null)
        .map((node) => node.type == BlockType.group ? node.id : parents[node.id])
        .whereType<String>()
        .toSet();
    if (groupIds.isEmpty) return;
    beginGroupTransaction('Ungroup');
    _document = _document.ungroupNodes(groupIds);
    notifyListeners();
    unawaited(commitTransaction());
  }

  /// Starts/extends a coalesced text transaction. Call [flushText] when a
  /// text field loses focus so typing never writes once per keystroke.
  void replaceText(String id, String text, {List<dynamic>? delta}) {
    final node = _document.nodeById(id);
    if (node == null || node.locked) return;
    if (!_history.inTransaction) {
      beginNodeTransaction('Edit text');
    }
    final payload = Map<String, dynamic>.from(node.payload)
      ..['text'] = text
      ..['richTextDelta'] = delta == null
          ? <dynamic>[
              {'insert': text},
              {'insert': '\n'},
            ]
          : List<dynamic>.from(delta);
    replaceNode(
      node.copyWith(payload: payload),
      label: 'Edit text',
    );
    _textTimer?.cancel();
    _textTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(commitTransaction());
    });
  }

  Future<void> flushText() => commitTransaction();

  Future<void> retrySave() => _persist();

  Future<void> undo() async {
    await commitTransaction();
    final command = _history.takeUndo();
    if (command == null) return;
    _restore(command.revert(_snapshot()));
    notifyListeners();
    await _persist();
  }

  Future<void> redo() async {
    await commitTransaction();
    final command = _history.takeRedo();
    if (command == null) return;
    _restore(command.apply(_snapshot()));
    notifyListeners();
    await _persist();
  }

  /// Returns the selected structural graph as immutable nodes for feature
  /// workflows such as clipboard persistence and insertion.
  List<CanvasNode> selectedNodeGraphSnapshot() =>
      _selectedGraphNodes;

  /// Replaces the working document after a checkpoint restore or archive
  /// import. History intentionally starts fresh at the restored version.
  /// Replaces the immutable working document after recovery or import.
  void replaceDocumentModel(EntryDocument next) {
    _textTimer?.cancel();
    _document = next;
    _selection.clear();
    _history.reset();
    _saveState = EditorSaveState.saved;
    notifyListeners();
  }

  @override
  void dispose() {
    _textTimer?.cancel();
    super.dispose();
  }

  Future<void> _commit(
    EditorDocumentSnapshot before,
    String label,
    EditorCommandKind kind,
  ) async {
    final after = _snapshot();
    if (_same(before, after)) return;
    _history.record(
      EditorCommand.fromStates(
        label: label,
        kind: kind,
        before: before,
        after: after,
      ),
    );
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    _saveState = EditorSaveState.saving;
    notifyListeners();
    try {
      await _onSave(document);
      _saveState = EditorSaveState.saved;
    } catch (_) {
      _saveState = EditorSaveState.failed;
    }
    notifyListeners();
  }

  void _updateSelectedNodes(
    String label,
    CanvasNode Function(CanvasNode node) update,
  ) {
    if (_selection.isEmpty) return;
    beginNodeTransaction(label);
    for (final id in _expandedSelectedNodes.map((node) => node.id).toSet()) {
      final node = _document.nodeById(id);
      if (node == null) continue;
      _document = _document.replaceNode(update(node));
    }
    notifyListeners();
    unawaited(commitTransaction());
  }

  List<CanvasNode> get _allDocumentNodes {
    final result = <CanvasNode>[];
    void visit(Iterable<CanvasNode> candidates) {
      for (final node in candidates) {
        result.add(node);
        if (node.children.isNotEmpty) visit(node.children);
      }
    }

    visit(_document.nodes);
    return List<CanvasNode>.unmodifiable(result);
  }

  List<CanvasNode> get _selectedNodes => List<CanvasNode>.unmodifiable(
    _allDocumentNodes.where((node) => _selection.contains(node.id)),
  );

  Map<String, String?> get _parentById {
    final parents = <String, String?>{};
    void visit(Iterable<CanvasNode> candidates, String? parentId) {
      for (final node in candidates) {
        parents[node.id] = parentId;
        visit(node.children, node.id);
      }
    }

    visit(_document.nodes, null);
    return parents;
  }

  Set<String> _descendantIds(CanvasNode node) {
    final ids = <String>{};
    void visit(Iterable<CanvasNode> children) {
      for (final child in children) {
        ids.add(child.id);
        visit(child.children);
      }
    }

    visit(node.children);
    return ids;
  }

  /// Expands a selection to the drawable siblings controlled by a selected
  /// group, without converting immutable nodes through legacy blocks.
  List<CanvasNode> get _expandedSelectedNodes {
    final ids = <String>{..._selection};
    final parents = _parentById;
    for (final selected in _selectedNodes) {
      if (selected.type == BlockType.group) {
        ids.addAll(_descendantIds(selected));
        continue;
      }
      final parentId = parents[selected.id];
      if (parentId == null) continue;
      final parent = _nodeById(parentId);
      if (parent != null) ids.addAll(_descendantIds(parent));
    }
    return List<CanvasNode>.unmodifiable(
      _allDocumentNodes.where((node) => ids.contains(node.id)),
    );
  }

  /// Returns complete immutable roots for clipboard and duplicate operations
  /// actions, including the parent group when a child is selected.
  List<CanvasNode> get _selectedGraphNodes {
    final ids = _expandedSelectedNodes.map((node) => node.id).toSet();
    final parents = _parentById;
    for (final id in _selection) {
      var parentId = parents[id];
      while (parentId != null) {
        ids.add(parentId);
        parentId = parents[parentId];
      }
    }

    List<CanvasNode> copyRoots(Iterable<CanvasNode> candidates) => candidates
        .map(
          (node) {
            if (!ids.contains(node.id)) return null;
            final children = copyRoots(node.children);
            return node.copyWith(children: children);
          },
        )
        .whereType<CanvasNode>()
        .toList(growable: false);

    return List<CanvasNode>.unmodifiable(copyRoots(_document.nodes));
  }

  CanvasNode? _nodeById(String id) => _document.nodeById(id);

  CanvasNode _worldNode(CanvasNode node) => node.copyWith(
    transform: _document.worldTransformFor(node.id) ?? node.transform,
    children: const <CanvasNode>[],
  );

  int _siblingIndex(String id) {
    final parentId = _parentById[id];
    final siblings = parentId == null
        ? _document.nodes
        : _nodeById(parentId)?.children ?? const <CanvasNode>[];
    return siblings.toList(growable: false).indexWhere((node) => node.id == id);
  }

  int _siblingCount(String id) {
    final parentId = _parentById[id];
    return parentId == null
        ? _document.nodes.length
        : _nodeById(parentId)?.children.length ?? 0;
  }

  double _snap(double value) {
    return SnappingService.snapValue(value, board.gridSize);
  }

  EditorDocumentSnapshot _snapshot() =>
      EditorDocumentSnapshot.fromDocument(_document);

  void _restore(EditorDocumentSnapshot snapshot) {
    _document = snapshot.document;
    _selection.removeWhere((id) => _nodeById(id) == null);
  }

  CanvasNode _remapClipboardNode(
    CanvasNode node,
    Map<String, String> idMap, {
    Offset offset = Offset.zero,
    bool rename = false,
  }) {
    final payload = Map<String, dynamic>.from(node.payload);
    final groupId = payload['groupId'];
    if (groupId is String) payload['groupId'] = idMap[groupId] ?? groupId;
    final childIds = payload['childIds'];
    if (childIds is List) {
      payload['childIds'] = childIds
          .map((id) => id is String ? (idMap[id] ?? id) : id)
          .toList(growable: false);
    }
    final transform = node.transform.copyWith(
      x: node.transform.x + offset.dx,
      y: node.transform.y + offset.dy,
    );
    return node.copyWith(
      id: idMap[node.id] ?? node.id,
      transform: transform,
      payload: payload,
      accessibilityLabel: rename && node.accessibilityLabel != null
          ? '${node.accessibilityLabel} copy'
          : node.accessibilityLabel,
      children: node.children.map(
        (child) => _remapClipboardNode(child, idMap, rename: rename),
      ),
    );
  }

  static Set<String> _collectNodeIds(Iterable<CanvasNode> nodes) {
    final ids = <String>{};
    final pending = List<CanvasNode>.from(nodes);
    while (pending.isNotEmpty) {
      final node = pending.removeLast();
      if (!ids.add(node.id)) continue;
      pending.addAll(node.children);
    }
    return ids;
  }

  static Iterable<String> _flattenNodeIds(Iterable<CanvasNode> nodes) sync* {
    for (final node in nodes) {
      yield node.id;
      yield* _flattenNodeIds(node.children);
    }
  }

  static Rect _boundsFor(List<CanvasNode> blocks) {
    var bounds = Rect.fromLTWH(
      blocks.first.x,
      blocks.first.y,
      blocks.first.w,
      blocks.first.h,
    );
    for (final block in blocks.skip(1)) {
      bounds = bounds.expandToInclude(
        Rect.fromLTWH(block.x, block.y, block.w, block.h),
      );
    }
    return bounds;
  }

  static bool _same(
    EditorDocumentSnapshot left,
    EditorDocumentSnapshot right,
  ) => jsonEncode(left.toJson()) == jsonEncode(right.toJson());

  static Set<String> _assetIdsInNodes(Iterable<CanvasNode> nodes) {
    final ids = <String>{};
    void visit(Iterable<CanvasNode> candidates) {
      for (final node in candidates) {
        if (node.assetId != null) ids.add(node.assetId!);
        if (node.children.isNotEmpty) visit(node.children);
      }
    }

    visit(nodes);
    return ids;
  }
}
