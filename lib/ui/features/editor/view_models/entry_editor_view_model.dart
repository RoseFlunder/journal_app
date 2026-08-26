import '../../../../editor/editor_controller.dart';
import '../../../../models/document.dart';
import '../../../../models/entry.dart';
import '../../../../services/repositories.dart';

/// Editor feature view model backed by the document repository.
class EntryEditorViewModel extends EditorController {
  EntryEditorViewModel({
    required EntryDocument document,
    required DocumentRepository documentRepository,
    required CheckpointRepository checkpointRepository,
    super.maxHistory,
  }) : _documentId = document.id,
       _documentRepository = documentRepository,
       super(
         blocks: document.toEntry().blocks,
         initialBoard: document.board,
         persistDocument: (blocks, board) =>
             _persistCurrentDocument(
               documentRepository,
               checkpointRepository,
               document,
               blocks,
               board,
             ),
       );

  final String _documentId;
  final DocumentRepository _documentRepository;

  String get documentId => _documentId;

  EntryDocument get document {
    final current = _documentRepository.documents.firstWhere(
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
  DocumentRepository documentRepository,
  CheckpointRepository checkpointRepository,
  EntryDocument initial,
  List<ContentBlock> blocks,
  BoardSettings board,
) async {
  final current = documentRepository.documents.firstWhere(
    (document) => document.id == initial.id,
    orElse: () => initial,
  );
  final entry = current.toEntry()
    ..blocks = blocks
    ..board = board;
  await documentRepository.saveDocument(EntryDocument.fromEntry(entry));
  checkpointRepository.scheduleCheckpoint(initial.id);
}
