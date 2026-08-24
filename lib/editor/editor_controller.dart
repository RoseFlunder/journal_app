import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/entry.dart';

/// Local, transactional editing state for one entry. Pointer updates mutate
/// only this controller; persistence happens once when a transaction commits.
class EditorController extends ChangeNotifier {
  EditorController({
    required List<ContentBlock> blocks,
    required BoardSettings initialBoard,
    required Future<void> Function(List<ContentBlock>, BoardSettings)
    persistDocument,
    this.maxHistory = 100,
  }) : _blocks = _cloneBlocks(blocks),
       _board = initialBoard,
       _onSave = persistDocument;

  static const _uuid = Uuid();

  final Future<void> Function(List<ContentBlock>, BoardSettings) _onSave;
  final int maxHistory;
  final List<_EditorCommand> _undo = [];
  final List<_EditorCommand> _redo = [];
  final Set<String> _selection = <String>{};
  List<ContentBlock> _clipboard = <ContentBlock>[];
  List<ContentBlock> _blocks;
  BoardSettings _board;
  _EditorSnapshot? _transactionStart;
  String? _transactionLabel;
  Timer? _textTimer;
  EditorSaveState _saveState = EditorSaveState.saved;

  List<ContentBlock> get blocks => List.unmodifiable(_blocks);
  BoardSettings get board => _board;
  Set<String> get selection => Set.unmodifiable(_selection);
  bool get hasSelection => _selection.isNotEmpty;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get inTransaction => _transactionStart != null;
  bool get canPaste => _clipboard.isNotEmpty;
  bool get canGroup => _expandedSelectedBlocks.length > 1;
  bool get canUngroup =>
      _expandedSelectedBlocks.any((block) => block.groupId != null);
  EditorSaveState get saveState => _saveState;

  ContentBlock? get primarySelection {
    if (_selection.isEmpty) return null;
    final id = _selection.last;
    return _byId(id);
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
    final next = _blocks
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
    if (_transactionStart != null) return;
    _transactionStart = _snapshot();
    _transactionLabel = label;
  }

  Future<void> commitTransaction() async {
    _textTimer?.cancel();
    final before = _transactionStart;
    final label = _transactionLabel;
    _transactionStart = null;
    _transactionLabel = null;
    if (before == null || label == null) return;
    await _commit(before, label);
  }

  void cancelTransaction() {
    _textTimer?.cancel();
    final before = _transactionStart;
    _transactionStart = null;
    _transactionLabel = null;
    if (before == null) return;
    _restore(before);
    notifyListeners();
  }

  /// Updates only an unlocked block. Call [commitTransaction] after the last
  /// pointer event to produce one undo entry and one persistent write.
  void updateBlock(String id, void Function(ContentBlock block) mutate) {
    final block = _byId(id);
    if (block == null || block.locked) return;
    mutate(block);
    block.opacity = block.opacity.clamp(0.0, 1.0).toDouble();
    notifyListeners();
  }

  /// Applies a detached block snapshot at the command boundary.
  ///
  /// Widgets and overlays should use this method when they preview a
  /// transform. The controller owns the stored instance and clones the
  /// submitted value before it becomes part of the working document.
  void replaceBlockSnapshot(ContentBlock next, {String label = 'Edit block'}) {
    final index = _blocks.indexWhere((block) => block.id == next.id);
    if (index < 0 || _blocks[index].locked) return;
    if (_transactionStart == null) beginTransaction(label);
    _blocks[index] = next.clone();
    _blocks[index].opacity = _blocks[index].opacity.clamp(0.0, 1.0).toDouble();
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
    for (final id in _expandedSelectedBlocks.map((block) => block.id)) {
      updateBlock(id, (block) {
        block.x += delta.dx;
        block.y += delta.dy;
        if (snap && _board.snapToGrid) {
          block.x = _snap(block.x);
          block.y = _snap(block.y);
        }
      });
    }
  }

  /// Snaps the current selection once at the end of a gesture. Keeping raw
  /// pointer deltas during the gesture prevents small movements from being
  /// rounded away on every pointer event.
  void snapSelection() {
    if (!_board.snapToGrid || _selection.isEmpty) return;
    for (final block in _expandedSelectedBlocks) {
      if (block.locked) continue;
      block.x = _snap(block.x);
      block.y = _snap(block.y);
    }
    notifyListeners();
  }

  void nudge(Offset delta) {
    beginTransaction('Nudge');
    moveSelection(delta, snap: false);
    unawaited(commitTransaction());
  }

  void updateBoard(BoardSettings next) {
    beginTransaction('Board settings');
    _board = next;
    notifyListeners();
    unawaited(commitTransaction());
  }

  void add(ContentBlock block, {bool select = true}) {
    beginTransaction('Add ${block.type.name}');
    _blocks.add(block.clone());
    if (select) {
      _selection
        ..clear()
        ..add(block.id);
    }
    notifyListeners();
    unawaited(commitTransaction());
  }

  void deleteSelection() {
    if (_selection.isEmpty) return;
    beginTransaction('Delete');
    final selected = _expandedSelectedBlocks.map((block) => block.id).toSet();
    _blocks.removeWhere(
      (block) => selected.contains(block.id) && !block.locked,
    );
    final childGroupIds = _blocks
        .where((block) => block.groupId != null)
        .map((block) => block.groupId!)
        .toSet();
    _blocks.removeWhere(
      (block) =>
          block.type == BlockType.group && !childGroupIds.contains(block.id),
    );
    _selection.removeWhere((id) => _byId(id) == null);
    notifyListeners();
    unawaited(commitTransaction());
  }

  void duplicateSelection() {
    final selected = _expandedSelectedBlocks;
    if (selected.isEmpty) return;
    beginTransaction('Duplicate');
    final copies = <ContentBlock>[];
    for (final source in selected) {
      final copyJson = source.toJson()..['id'] = _uuid.v4();
      final copy = ContentBlock.fromJson(copyJson)
        ..x += 4
        ..y += 4
        ..groupId = null
        ..name = source.name == null ? null : '${source.name} copy';
      copies.add(copy);
    }
    _blocks.addAll(copies);
    _selection
      ..clear()
      ..addAll(copies.map((block) => block.id));
    notifyListeners();
    unawaited(commitTransaction());
  }

  void copySelection() {
    _clipboard = _selectedBlocks.map((block) => block.clone()).toList();
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
    final pasted = <ContentBlock>[];
    for (final source in _clipboard) {
      final json = source.toJson()..['id'] = _uuid.v4();
      final copy = ContentBlock.fromJson(json)
        ..x += offset.dx
        ..y += offset.dy;
      pasted.add(copy);
    }
    _blocks.addAll(pasted);
    _selection
      ..clear()
      ..addAll(pasted.map((block) => block.id));
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
    final selected = _blocks.where((block) => ids.contains(block.id)).toList();
    _blocks.removeWhere((block) => ids.contains(block.id));
    _blocks.addAll(selected);
    notifyListeners();
    unawaited(commitTransaction());
  }

  void sendToBack() {
    if (_selection.isEmpty) return;
    beginTransaction('Send to back');
    final ids = _expandedSelectedBlocks.map((block) => block.id).toSet();
    final selected = _blocks.where((block) => ids.contains(block.id)).toList();
    _blocks.removeWhere((block) => ids.contains(block.id));
    _blocks.insertAll(0, selected);
    notifyListeners();
    unawaited(commitTransaction());
  }

  void align(Alignment alignment) {
    final blocks = _expandedSelectedBlocks;
    if (blocks.length < 2) return;
    beginTransaction('Align');
    final bounds = _boundsFor(blocks);
    for (final block in blocks) {
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
    for (final child in children) {
      child.groupId = group.id;
    }
    _blocks.add(group);
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
    for (final child in _blocks.where(
      (block) => groupIds.contains(block.groupId),
    )) {
      child.groupId = null;
    }
    _blocks.removeWhere((block) => groupIds.contains(block.id));
    notifyListeners();
    unawaited(commitTransaction());
  }

  /// Starts/extends a coalesced text transaction. Call [flushText] when a
  /// text field loses focus so typing never writes once per keystroke.
  void replaceText(String id, String text, {List<dynamic>? delta}) {
    if (_transactionStart == null) beginTransaction('Edit text');
    updateBlock(id, (block) {
      block.text = text;
      if (delta != null) block.richTextDelta = List<dynamic>.from(delta);
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
    if (_undo.isEmpty) return;
    final command = _undo.removeLast();
    _redo.add(command);
    _restore(command.before);
    notifyListeners();
    await _persist();
  }

  Future<void> redo() async {
    await commitTransaction();
    if (_redo.isEmpty) return;
    final command = _redo.removeLast();
    _undo.add(command);
    _restore(command.after);
    notifyListeners();
    await _persist();
  }

  List<ContentBlock> snapshotBlocks() => _cloneBlocks(_blocks);

  /// Replaces the working document after a checkpoint restore or archive
  /// import. History intentionally starts fresh at the restored version.
  void replaceDocument(List<ContentBlock> blocks, BoardSettings board) {
    _textTimer?.cancel();
    _transactionStart = null;
    _transactionLabel = null;
    _blocks = _cloneBlocks(blocks);
    _board = board;
    _selection.clear();
    _undo.clear();
    _redo.clear();
    _saveState = EditorSaveState.saved;
    notifyListeners();
  }

  @override
  void dispose() {
    _textTimer?.cancel();
    super.dispose();
  }

  Future<void> _commit(_EditorSnapshot before, String label) async {
    final after = _snapshot();
    if (_same(before, after)) return;
    _undo.add(_EditorCommand(label, before, after));
    if (_undo.length > maxHistory) {
      _undo.removeAt(0);
    }
    _redo.clear();
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    _saveState = EditorSaveState.saving;
    notifyListeners();
    try {
      await _onSave(snapshotBlocks(), _board);
      _saveState = EditorSaveState.saved;
    } catch (_) {
      _saveState = EditorSaveState.failed;
    }
    notifyListeners();
  }

  void _setSelectionProperty(String label, void Function(ContentBlock) change) {
    if (_selection.isEmpty) return;
    beginTransaction(label);
    for (final block in _expandedSelectedBlocks) {
      change(block);
    }
    notifyListeners();
    unawaited(commitTransaction());
  }

  List<ContentBlock> get _selectedBlocks =>
      _blocks.where((block) => _selection.contains(block.id)).toList();

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
    return _blocks
        .where(
          (block) =>
              _selection.contains(block.id) ||
              (block.type != BlockType.group &&
                  groupIds.contains(block.groupId)),
        )
        .toList();
  }

  ContentBlock? _byId(String id) {
    for (final block in _blocks) {
      if (block.id == id) return block;
    }
    return null;
  }

  double _snap(double value) {
    final size = math.max(1, _board.gridSize);
    return (value / size).roundToDouble() * size;
  }

  _EditorSnapshot _snapshot() => _EditorSnapshot(_cloneBlocks(_blocks), _board);

  void _restore(_EditorSnapshot snapshot) {
    _blocks = _cloneBlocks(snapshot.blocks);
    _board = snapshot.board;
    _selection.removeWhere((id) => _byId(id) == null);
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

  static bool _same(_EditorSnapshot left, _EditorSnapshot right) =>
      jsonEncode(left.toJson()) == jsonEncode(right.toJson());

  static List<ContentBlock> _cloneBlocks(List<ContentBlock> blocks) =>
      blocks.map((block) => block.clone()).toList();
}

enum EditorSaveState { saved, saving, failed }

class _EditorCommand {
  const _EditorCommand(this.label, this.before, this.after);

  final String label;
  final _EditorSnapshot before;
  final _EditorSnapshot after;
}

class _EditorSnapshot {
  const _EditorSnapshot(this.blocks, this.board);

  final List<ContentBlock> blocks;
  final BoardSettings board;

  Map<String, dynamic> toJson() => {
    'blocks': blocks.map((block) => block.toJson()).toList(),
    'board': board.toJson(),
  };
}
