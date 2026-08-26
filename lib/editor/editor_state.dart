import '../models/document.dart';

enum EditorSaveState { saved, saving, failed }

/// Immutable presentation state exposed by an editor view model.
class EditorState {
  EditorState({
    required this.document,
    required Iterable<String> selection,
    required this.canUndo,
    required this.canRedo,
    required this.inTransaction,
    required this.canPaste,
    required this.saveState,
  }) : selection = Set.unmodifiable(selection);

  /// The immutable document currently exposed to the editor view.
  final EntryDocument document;
  final Set<String> selection;
  final bool canUndo;
  final bool canRedo;
  final bool inTransaction;
  final bool canPaste;
  final EditorSaveState saveState;

  bool get hasSelection => selection.isNotEmpty;
}
