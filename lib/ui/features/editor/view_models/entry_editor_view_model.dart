import '../../../../editor/editor_controller.dart';
import '../../../../models/document.dart';
import '../../../../services/repositories.dart';

typedef EntryEditorViewModelFactory = EntryEditorViewModel Function(
  EntryDocument document,
);

/// Editor feature view model backed by the document repository.
class EntryEditorViewModel extends EditorController {
  EntryEditorViewModel({
    required EntryDocument document,
    required DocumentRepository documentRepository,
    required CheckpointRepository checkpointRepository,
    AssetRepository? assetRepository,
    TemplateRepository? templateRepository,
    PreferencesRepository? preferenceRepository,
    PersistenceRepository? persistenceRepository,
    ArchiveRepository? archiveRepository,
    super.maxHistory,
  }) : _documentId = document.id,
       _documentRepository = documentRepository,
       _checkpointRepository = checkpointRepository,
       _assets = assetRepository,
       _templates = templateRepository,
       _preferences = preferenceRepository,
       _persistence = persistenceRepository,
       _archives = archiveRepository,
       super(
         document: document,
         persistDocument: (EntryDocument next) =>
             _persistCurrentDocument(
               documentRepository,
               checkpointRepository,
               document,
               next,
             ),
       );

  final String _documentId;
  final DocumentRepository _documentRepository;
  final CheckpointRepository _checkpointRepository;
  final AssetRepository? _assets;
  final TemplateRepository? _templates;
  final PreferencesRepository? _preferences;
  final PersistenceRepository? _persistence;
  final ArchiveRepository? _archives;

  String get documentId => _documentId;
  DocumentRepository get documentRepository => _documentRepository;
  CheckpointRepository get checkpointRepository => _checkpointRepository;

  /// Repository capabilities owned by this feature view model. The nullable
  /// backing fields keep the core editor usable in focused unit tests; the
  /// production editor factory supplies all capabilities.
  AssetRepository get assetRepository => _assets!;
  TemplateRepository get templateRepository => _templates!;
  PreferencesRepository get preferenceRepository => _preferences!;
  PersistenceRepository get persistence => _persistence!;
  ArchiveRepository get archiveRepository => _archives!;

  @override
  EntryDocument get document {
    final current = _documentRepository.documents.firstWhere(
      (document) => document.id == _documentId,
      orElse: () => super.document,
    );
    return current.copyWith(nodes: super.document.nodes, board: super.document.board);
  }
}

Future<void> _persistCurrentDocument(
  DocumentRepository documentRepository,
  CheckpointRepository checkpointRepository,
  EntryDocument initial,
  EntryDocument next,
) async {
  final current = documentRepository.documents.firstWhere(
    (document) => document.id == initial.id,
    orElse: () => initial,
  );
  await documentRepository.saveDocument(
    current.copyWith(
      nodes: next.nodes,
      board: next.board,
      modifiedAt: DateTime.now(),
    ),
  );
  checkpointRepository.scheduleCheckpoint(initial.id);
}
