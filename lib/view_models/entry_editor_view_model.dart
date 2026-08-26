import '../models/document.dart';
import '../models/entry.dart';
import '../services/repositories.dart';
import '../editor/editor_controller.dart';

/// Editor feature view model backed by the document repository.
///
/// [EditorController] remains the transactional editing engine for now. This
/// feature-facing type supplies the repository boundary and resolves the
/// latest document before each save, so metadata changed by another editor
/// surface is not overwritten by a stale initialization snapshot.
class EntryEditorViewModel extends EditorController {
  EntryEditorViewModel({
    required EntryDocument document,
    required JournalRepository repository,
    super.maxHistory,
  }) : _documentId = document.id,
       _repository = repository,
       super(
         blocks: document.toEntry().blocks,
         initialBoard: document.board,
         persistDocument: (blocks, board) =>
             _persistCurrentDocument(repository, document, blocks, board),
       );

  final String _documentId;
  final JournalRepository _repository;

  String get documentId => _documentId;

  JournalRepository get repository => _repository;

  EntryDocument get document {
    final current = _repository.documents.firstWhere(
      (document) => document.id == _documentId,
      orElse: () => EntryDocument.fromEntry(
        Entry(id: _documentId, createdAt: DateTime.now()),
      ),
    );
    final entry = current.toEntry()
      ..blocks = snapshotBlocks()
      ..board = board;
    return EntryDocument.fromEntry(entry);
  }
}

Future<void> _persistCurrentDocument(
  JournalRepository repository,
  EntryDocument initial,
  List<ContentBlock> blocks,
  BoardSettings board,
) async {
  final current = repository.documents.firstWhere(
    (document) => document.id == initial.id,
    orElse: () => initial,
  );
  final entry = current.toEntry()
    ..blocks = blocks
    ..board = board;
  await repository.saveDocument(EntryDocument.fromEntry(entry));
  repository.scheduleCheckpoint(initial.id);
}
