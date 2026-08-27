import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/document.dart';
import '../models/entry.dart';
import 'editor_state.dart';
import 'editor_history.dart';
import 'geometry_services.dart';

/// Local, transactional editing state for one entry. Pointer updates mutate
/// only this controller; persistence happens once when a transaction commits.
class EditorController extends ChangeNotifier {
  EditorController({
    EntryDocument? document,
    List<ContentBlock>? blocks,
    BoardSettings? initialBoard,
    required Future<void> Function(EntryDocument) persistDocument,
    this.maxHistory = 100,
  }) : assert(
         document != null || (blocks != null && initialBoard != null),
         'Provide either document or the legacy blocks/initialBoard pair.',
       ),
       _document = document ?? _legacyDocument(blocks!, initialBoard!),
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

  /// Detached legacy block adapters for the current canvas implementation.
  /// New feature code should consume [document] and [nodes].
  @Deprecated('Use document.nodes or nodes instead.')
  List<ContentBlock> get blocks => _document.blocks;
  List<CanvasNode> get nodes => document.nodes;
  EntryDocument get document => _document;
  BoardSettings get board => _document.board;
  Set<String> get selection => Set.unmodifiable(_selection);
  List<ContentBlock> get selectedDrawableBlocks => _expandedSelectedBlocks
      .where(
        (block) => block.type == BlockType.ink || block.type == BlockType.shape,
      )
      .map((block) => block.clone())
      .toList(growable: false);
  bool get hasSelection => _selection.isNotEmpty;
  bool get canUndo => _history.canUndo;
  bool get canRedo => _history.canRedo;
  bool get inTransaction => _history.inTransaction;
  bool get canPaste => _clipboard.isNotEmpty;
  bool get canGroup => _expandedSelectedBlocks.length > 1;
  bool get canUngroup =>
      _expandedSelectedBlocks.any((block) => block.groupId != null);
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

  ContentBlock? get primarySelection {
    if (_selection.isEmpty) return null;
    final id = _selection.last;
    final block = _byId(id);
    return block?.clone();
  }

  /// Replaces one immutable node at the editor boundary.
  void replaceNode(CanvasNode node, {String label = 'Edit node'}) {
    final current = _document.nodeById(node.id);
    if (current == null || current.locked) return;
    if (!_history.inTransaction) beginTransaction(label);
    _document = _document.replaceNode(node);
    notifyListeners();
  }

  /// Applies an immutable update to one node without exposing the mutable
  /// compatibility adapter to callers.
  void updateNode(
    String id,
    CanvasNode Function(CanvasNode node) update, {
    String label = 'Edit node',
  }) {
    final node = _document.nodeById(id);
    if (node == null || node.locked) return;
    replaceNode(update(node), label: label);
  }

  /// Inserts a node through the immutable editor boundary.
  void addNode(CanvasNode node, {bool select = true}) {
    if (_document.nodeById(node.id) != null) return;
    beginTransaction('Add ${node.type.name}');
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
    final next = blocks
        .where((block) => !block.hidden)
        .map((b) => b.id)
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

  void beginTransaction(String label) {
    _textTimer?.cancel();
    _history.begin(_snapshot(), label);
  }

  Future<void> commitTransaction() async {
    _textTimer?.cancel();
    final transaction = _history.takeTransaction();
    if (transaction == null) return;
    await _commit(transaction.before, transaction.label);
  }

  void cancelTransaction() {
    _textTimer?.cancel();
    final before = _history.cancelTransaction();
    if (before == null) return;
    _restore(before);
    notifyListeners();
  }

  /// Updates only an unlocked block. Call [commitTransaction] after the last
  /// pointer event to produce one undo entry and one persistent write.
  void updateBlock(String id, void Function(ContentBlock block) mutate) {
    final block = _byId(id);
    if (block == null || block.locked) return;
    final next = block.clone();
    mutate(next);
    next.opacity = next.opacity.clamp(0.0, 1.0).toDouble();
    _document = _document.replaceLegacyBlock(next);
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
    for (final block in selectedDrawableBlocks) {
      updateBlock(block.id, (target) {
        target
          ..strokeColorValue = colorValue
          ..opacity = opacity;
      });
    }
  }

  /// Applies a detached block snapshot at the command boundary.
  ///
  /// Widgets and overlays should use this method when they preview a
  /// transform. The controller owns the stored instance and clones the
  /// submitted value before it becomes part of the working document.
  void replaceBlockSnapshot(ContentBlock next, {String label = 'Edit block'}) {
    final current = _byId(next.id);
    if (current == null || current.locked) return;
    if (!_history.inTransaction) beginTransaction(label);
    final replacement = next.clone()
      ..opacity = next.opacity.clamp(0.0, 1.0).toDouble();
    _document = _document.replaceLegacyBlock(replacement);
    notifyListeners();
  }

  /// Replaces a block and commits it as one command for non-gesture edits.
  Future<void> replaceBlockAndCommit(
    ContentBlock next, {
    String label = 'Edit block',
  }) async {
    replaceBlockSnapshot(next, label: label);
    await commitTransaction();
  }

  /// Records a visual update made by a legacy canvas callback during an active
  /// transaction. New tools should prefer [updateBlock].
  void markChanged() => notifyListeners();

  void moveSelection(Offset delta, {bool snap = false}) {
    final transforms = <String, Transform2D>{};
    for (final block in _expandedSelectedBlocks) {
      if (block.locked) continue;
      var x = block.x + delta.dx;
      var y = block.y + delta.dy;
      if (snap && board.snapToGrid) {
        x = _snap(x);
        y = _snap(y);
      }
      transforms[block.id] = Transform2D(
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
    for (final block in _expandedSelectedBlocks) {
      if (block.locked) continue;
      transforms[block.id] = Transform2D(
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
    final currentBlocks = blocks;
    final groupIds = currentBlocks
        .where((block) => requestedIds.contains(block.id))
        .expand(
          (block) => [
            block.groupId,
            if (block.type == BlockType.group) block.id,
          ],
        )
        .whereType<String>()
        .toSet();
    final targetIds = currentBlocks
        .where(
          (block) =>
              requestedIds.contains(block.id) ||
              (block.type != BlockType.group &&
                  groupIds.contains(block.groupId)),
        )
        .map((block) => block.id);
    final transforms = <String, Transform2D>{};
    for (final id in targetIds) {
      final block = _byId(id);
      if (block == null || block.locked || block.hidden) continue;
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
    for (final block in _expandedSelectedBlocks) {
      if (block.locked) continue;
      transforms[block.id] = Transform2D(
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
    beginTransaction('Nudge');
    moveSelection(delta, snap: false);
    unawaited(commitTransaction());
  }

  void updateBoard(BoardSettings next) {
    beginTransaction('Board settings');
    _document = _document.copyWith(board: next);
    notifyListeners();
    unawaited(commitTransaction());
  }

  void add(ContentBlock block, {bool select = true}) {
    beginTransaction('Add ${block.type.name}');
    final next = _cloneBlocks(blocks)..add(block.clone());
    _replaceLegacyBlocks(next);
    if (select) {
      _selection
        ..clear()
        ..add(block.id);
    }
    notifyListeners();
    unawaited(commitTransaction());
  }

  /// Inserts a complete template graph as one command, remapping every node
  /// and group reference so the source remains reusable.
  void insertBlocks(
    Iterable<ContentBlock> sources, {
    Offset offset = Offset.zero,
    String label = 'Insert template',
  }) {
    final sourceList = sources.map((block) => block.clone()).toList();
    if (sourceList.isEmpty) return;
    beginTransaction(label);
    final idMap = <String, String>{
      for (final source in sourceList) source.id: _uuid.v4(),
    };
    final inserted = <ContentBlock>[];
    for (final source in sourceList) {
      final json = source.toJson()
        ..['id'] = idMap[source.id]
        ..['x'] = source.x + offset.dx
        ..['y'] = source.y + offset.dy
        ..['groupId'] = source.groupId == null ? null : idMap[source.groupId];
      if (source.childIds != null) {
        json['childIds'] = source.childIds
            ?.map((id) => idMap[id] ?? id)
            .toList();
      }
      inserted.add(ContentBlock.fromJson(json));
    }
    final next = _cloneBlocks(blocks)..addAll(inserted);
    _replaceLegacyBlocks(next);
    _selection
      ..clear()
      ..addAll(
        inserted
            .where((block) => block.type != BlockType.group)
            .map((block) => block.id),
      );
    notifyListeners();
    unawaited(commitTransaction());
  }

  void deleteSelection() {
    if (_selection.isEmpty) return;
    beginTransaction('Delete');
    final selected = _expandedSelectedBlocks.map((block) => block.id).toSet();
    final next = _cloneBlocks(blocks);
    next.removeWhere(
      (block) => selected.contains(block.id) && !block.locked,
    );
    final childGroupIds = next
        .where((block) => block.groupId != null)
        .map((block) => block.groupId!)
        .toSet();
    next.removeWhere(
      (block) =>
          block.type == BlockType.group && !childGroupIds.contains(block.id),
    );
    _replaceLegacyBlocks(next);
    _selection.removeWhere((id) => _byId(id) == null);
    notifyListeners();
    unawaited(commitTransaction());
  }

  void duplicateSelection() {
    final selected = _selectedGraphBlocks;
    if (selected.isEmpty) return;
    beginTransaction('Duplicate');
    final selectedIds = Set<String>.from(_selection);
    final idMap = <String, String>{
      for (final source in selected) source.id: _uuid.v4(),
    };
    final copies = <ContentBlock>[];
    for (final source in selected) {
      final copyJson = source.toJson()
        ..['id'] = idMap[source.id]
        ..['groupId'] = source.groupId == null ? null : idMap[source.groupId];
      if (source.childIds != null) {
        copyJson['childIds'] = source.childIds
            ?.map((id) => idMap[id] ?? id)
            .toList();
      }
      final copy = ContentBlock.fromJson(copyJson)
        ..x += 4
        ..y += 4
        ..name = source.name == null ? null : '${source.name} copy';
      copies.add(copy);
    }
    final next = _cloneBlocks(blocks)..addAll(copies);
    _replaceLegacyBlocks(next);
    _selection
      ..clear()
      ..addAll(
        selectedIds
            .map((id) => idMap[id])
            .whereType<String>()
            .followedBy(
              _selection.isEmpty
                  ? copies.map((block) => block.id)
                  : const <String>[],
            ),
      );
    if (_selection.isEmpty) {
      _selection.addAll(copies.map((block) => block.id));
    }
    notifyListeners();
    unawaited(commitTransaction());
  }

  void copySelection() {
    _clipboard = _nodesFromLegacyGraph(_selectedGraphBlocks);
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
    beginTransaction('Paste');
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

  void setLocked(bool locked) => _setSelectionProperty(
    locked ? 'Lock' : 'Unlock',
    (block) => block.locked = locked,
  );

  void setHidden(bool hidden) => _setSelectionProperty(
    hidden ? 'Hide' : 'Show',
    (block) => block.hidden = hidden,
  );

  void bringToFront() {
    if (_selection.isEmpty) return;
    beginTransaction('Bring to front');
    final ids = _expandedSelectedBlocks.map((block) => block.id).toSet();
    final next = _cloneBlocks(blocks);
    final selected = next.where((block) => ids.contains(block.id)).toList();
    next.removeWhere((block) => ids.contains(block.id));
    next.addAll(selected);
    _replaceLegacyBlocks(next);
    notifyListeners();
    unawaited(commitTransaction());
  }

  void sendToBack() {
    if (_selection.isEmpty) return;
    beginTransaction('Send to back');
    final ids = _expandedSelectedBlocks.map((block) => block.id).toSet();
    final next = _cloneBlocks(blocks);
    final selected = next.where((block) => ids.contains(block.id)).toList();
    next.removeWhere((block) => ids.contains(block.id));
    next.insertAll(0, selected);
    _replaceLegacyBlocks(next);
    notifyListeners();
    unawaited(commitTransaction());
  }

  void moveLayerForward() {
    final block = primarySelection;
    if (block == null) return;
    final index = blocks.indexWhere((item) => item.id == block.id);
    if (index < 0 || index >= blocks.length - 1) return;
    reorderLayer(block.id, index + 1);
  }

  void moveLayerBackward() {
    final block = primarySelection;
    if (block == null) return;
    final index = blocks.indexWhere((item) => item.id == block.id);
    if (index <= 0) return;
    reorderLayer(block.id, index - 1);
  }

  void reorderLayer(String blockId, int targetIndex) {
    final source = _byId(blockId);
    if (source == null) return;
    beginTransaction('Reorder layer');
    final unitIds = _layerUnitIds(source);
    final next = _cloneBlocks(blocks);
    final moving = next
        .where((block) => unitIds.contains(block.id))
        .toList();
    next.removeWhere((block) => unitIds.contains(block.id));
    final index = targetIndex.clamp(0, next.length).toInt();
    next.insertAll(index, moving);
    _replaceLegacyBlocks(next);
    notifyListeners();
    unawaited(commitTransaction());
  }

  void renameSelection(String name) {
    if (_selection.isEmpty) return;
    final normalized = name.trim();
    if (normalized.isEmpty) return;
    _setSelectionProperty('Rename', (block) => block.name = normalized);
  }

  void renameLayer(String blockId, String name) {
    final normalized = name.trim();
    final block = _byId(blockId);
    if (block == null || normalized.isEmpty) return;
    beginTransaction('Rename layer');
    final next = block.clone()..name = normalized;
    _document = _document.replaceLegacyBlock(next);
    notifyListeners();
    unawaited(commitTransaction());
  }

  void align(Alignment alignment) {
    final selected = _expandedSelectedBlocks;
    if (selected.length < 2) return;
    beginTransaction('Align');
    final bounds = _boundsFor(selected);
    final next = _cloneBlocks(blocks);
    final byId = {for (final block in next) block.id: block};
    for (final selectedBlock in selected) {
      final block = byId[selectedBlock.id];
      if (block == null || block.locked) continue;
      switch (alignment) {
        case Alignment.topLeft:
          block.x = bounds.left;
          block.y = bounds.top;
        case Alignment.topCenter:
          block.x = bounds.center.dx - block.w / 2;
          block.y = bounds.top;
        case Alignment.topRight:
          block.x = bounds.right - block.w;
          block.y = bounds.top;
        case Alignment.centerLeft:
          block.x = bounds.left;
          block.y = bounds.center.dy - block.h / 2;
        case Alignment.center:
          block.x = bounds.center.dx - block.w / 2;
          block.y = bounds.center.dy - block.h / 2;
        case Alignment.centerRight:
          block.x = bounds.right - block.w;
          block.y = bounds.center.dy - block.h / 2;
        case Alignment.bottomLeft:
          block.x = bounds.left;
          block.y = bounds.bottom - block.h;
        case Alignment.bottomCenter:
          block.x = bounds.center.dx - block.w / 2;
          block.y = bounds.bottom - block.h;
        case Alignment.bottomRight:
          block.x = bounds.right - block.w;
          block.y = bounds.bottom - block.h;
      }
    }
    _replaceLegacyBlocks(next);
    notifyListeners();
    unawaited(commitTransaction());
  }

  void groupSelection() {
    final children = _expandedSelectedBlocks
        .where((block) => block.type != BlockType.group)
        .toList();
    if (children.length < 2) return;
    beginTransaction('Group');
    final bounds = _boundsFor(children);
    final group = ContentBlock(
      id: _uuid.v4(),
      type: BlockType.group,
      name: 'Group',
      x: bounds.left,
      y: bounds.top,
      w: bounds.width,
      h: bounds.height,
      childIds: children.map((block) => block.id).toList(),
      // The group is a structural parent; its children remain the rendered
      // objects and inherit group transforms through [_expandedSelectedBlocks].
      hidden: true,
    );
    final next = _cloneBlocks(blocks);
    for (final child in next.where(
      (block) => children.any((selected) => selected.id == block.id),
    )) {
      child.groupId = group.id;
    }
    next.add(group);
    _replaceLegacyBlocks(next);
    _selection
      ..clear()
      ..addAll(children.map((block) => block.id));
    notifyListeners();
    unawaited(commitTransaction());
  }

  void ungroupSelection() {
    final groupIds = _expandedSelectedBlocks
        .map((block) => block.groupId)
        .whereType<String>()
        .toSet();
    if (groupIds.isEmpty) return;
    beginTransaction('Ungroup');
    final next = _cloneBlocks(blocks);
    for (final child in next.where(
      (block) => groupIds.contains(block.groupId),
    )) {
      child.groupId = null;
    }
    next.removeWhere((block) => groupIds.contains(block.id));
    _replaceLegacyBlocks(next);
    notifyListeners();
    unawaited(commitTransaction());
  }

  /// Starts/extends a coalesced text transaction. Call [flushText] when a
  /// text field loses focus so typing never writes once per keystroke.
  void replaceText(String id, String text, {List<dynamic>? delta}) {
    if (!_history.inTransaction) beginTransaction('Edit text');
    updateBlock(id, (block) {
      block.text = text;
      block.richTextDelta = delta == null
          ? <dynamic>[
              {'insert': text},
              {'insert': '\n'},
            ]
          : List<dynamic>.from(delta);
    });
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

  List<ContentBlock> snapshotBlocks() => _document.blocks;

  /// Returns the selected structural graph as detached snapshots for local
  /// templates and clipboard consumers.
  List<ContentBlock> selectedGraphSnapshot() => _selectedGraphBlocks
      .map((block) => block.clone())
      .toList(growable: false);

  /// Replaces the working document after a checkpoint restore or archive
  /// import. History intentionally starts fresh at the restored version.
  void replaceDocument(List<ContentBlock> blocks, BoardSettings board) {
    _textTimer?.cancel();
    _document = _document.copyWith(
      nodes: EntryDocument.fromEntry(
        _document.toEntry()..blocks = _cloneBlocks(blocks),
      ).nodes,
      board: board,
    );
    _selection.clear();
    _history.reset();
    _saveState = EditorSaveState.saved;
    notifyListeners();
  }

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

  Future<void> _commit(EditorDocumentSnapshot before, String label) async {
    final after = _snapshot();
    if (_same(before, after)) return;
    _history.record(
      EditorCommand.fromStates(label: label, before: before, after: after),
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

  void _setSelectionProperty(String label, void Function(ContentBlock) change) {
    if (_selection.isEmpty) return;
    beginTransaction(label);
    final next = _cloneBlocks(blocks);
    final byId = {for (final block in next) block.id: block};
    for (final selected in _expandedSelectedBlocks) {
      final block = byId[selected.id];
      if (block == null) continue;
      change(block);
    }
    _replaceLegacyBlocks(next);
    notifyListeners();
    unawaited(commitTransaction());
  }

  List<ContentBlock> get _selectedBlocks =>
      blocks.where((block) => _selection.contains(block.id)).toList();

  /// Returns the complete structural graph for clipboard/duplicate actions,
  /// including hidden group parents that are not rendered as selectable
  /// blocks. Transform operations continue to use [_expandedSelectedBlocks]
  /// so a group move changes its children exactly once.
  List<ContentBlock> get _selectedGraphBlocks {
    final groupIds = _selectedBlocks
        .expand(
          (block) => [
            block.groupId,
            if (block.type == BlockType.group) block.id,
          ],
        )
        .whereType<String>()
        .toSet();
    final ids = _expandedSelectedBlocks.map((block) => block.id).toSet()
      ..addAll(groupIds);
    return blocks.where((block) => ids.contains(block.id)).toList();
  }

  Set<String> _layerUnitIds(ContentBlock block) {
    final groupId = block.type == BlockType.group ? block.id : block.groupId;
    if (groupId == null) return {block.id};
    return blocks
        .where(
          (item) =>
              item.id == groupId ||
              item.groupId == groupId ||
              (item.type == BlockType.group && item.id == groupId),
        )
        .map((item) => item.id)
        .toSet();
  }

  List<ContentBlock> get _expandedSelectedBlocks {
    final groupIds = _selectedBlocks
        .expand(
          (block) => [
            block.groupId,
            if (block.type == BlockType.group) block.id,
          ],
        )
        .whereType<String>()
        .toSet();
    return blocks
        .where(
          (block) =>
              _selection.contains(block.id) ||
              (block.type != BlockType.group &&
                  groupIds.contains(block.groupId)),
        )
        .toList();
  }

  ContentBlock? _byId(String id) {
    for (final block in blocks) {
      if (block.id == id) return block;
    }
    return null;
  }

  double _snap(double value) {
    return SnappingService.snapValue(value, board.gridSize);
  }

  EditorDocumentSnapshot _snapshot() =>
      EditorDocumentSnapshot.fromDocument(_document);

  void _restore(EditorDocumentSnapshot snapshot) {
    _document = snapshot.document;
    _selection.removeWhere((id) => _byId(id) == null);
  }

  void _replaceLegacyBlocks(List<ContentBlock> next) {
    final entry = _document.toEntry()..blocks = _cloneBlocks(next);
    _document = EntryDocument.fromEntry(entry);
  }

  List<CanvasNode> _nodesFromLegacyGraph(Iterable<ContentBlock> graph) {
    final entry = _document.toEntry()..blocks = _cloneBlocks(graph.toList());
    return EntryDocument.fromEntry(entry).nodes;
  }

  CanvasNode _remapClipboardNode(
    CanvasNode node,
    Map<String, String> idMap, {
    Offset offset = Offset.zero,
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
      children: node.children.map(
        (child) => _remapClipboardNode(child, idMap),
      ),
    );
  }

  static Rect _boundsFor(List<ContentBlock> blocks) {
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

  static List<ContentBlock> _cloneBlocks(List<ContentBlock> blocks) =>
      blocks.map((block) => block.clone()).toList();
}

EntryDocument _legacyDocument(
  List<ContentBlock> blocks,
  BoardSettings board,
) {
  final entry = Entry.newPage()
    ..blocks = EditorController._cloneBlocks(blocks)
    ..board = board;
  return EntryDocument.fromEntry(entry);
}
