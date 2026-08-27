import 'dart:ui';
import 'dart:typed_data';

import '../../../../editor/editor_controller.dart';
import '../../../../models/document.dart';
import '../../../../models/template.dart';
import '../../../../services/image_source.dart';
import '../../../../services/journal_transfer_service.dart';
import '../../../../services/repositories.dart';
import '../use_cases/archive_transfer_use_case.dart';
import '../use_cases/checkpoint_recovery_use_case.dart';
import '../use_cases/image_insertion_use_case.dart';
import '../use_cases/template_workflow.dart';

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

  bool _editing = false;
  bool _selectMode = false;
  bool _drawMode = false;
  String? _textEditingId;

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
  Uint8List? readAsset(String id) => assetRepository.readAsset(id);

  /// Presentation/tool state that must stay consistent with the document
  /// selection. Flutter-only focus, dialogs, and animations remain in views.
  bool get editing => _editing;
  set editing(bool value) {
    if (_editing == value) return;
    _editing = value;
    notifyListeners();
  }

  bool get selectMode => _selectMode;
  set selectMode(bool value) {
    if (_selectMode == value && (!value || !_drawMode)) return;
    _selectMode = value;
    if (value) _drawMode = false;
    notifyListeners();
  }

  bool get drawMode => _drawMode;
  set drawMode(bool value) {
    if (_drawMode == value && (!value || !_selectMode)) return;
    _drawMode = value;
    if (value) _selectMode = false;
    notifyListeners();
  }

  String? get textEditingId => _textEditingId;
  set textEditingId(String? value) {
    if (_textEditingId == value) return;
    _textEditingId = value;
    notifyListeners();
  }

  String? get selectedId => selection.isEmpty ? null : selection.last;

  late final TemplateWorkflow _templateWorkflow = TemplateWorkflow(
    templates: templateRepository,
  );
  late final CheckpointRecoveryUseCase _checkpointRecovery =
      CheckpointRecoveryUseCase(
        checkpoints: checkpointRepository,
        documents: documentRepository,
      );

  Future<({ProcessedImage image, String assetId})> insertImageAsset({
    required String ownerId,
    required PickedImage picked,
    required ImageProcessor processor,
  }) =>
      ImageInsertionUseCase(
        assets: assetRepository,
        processor: processor,
      ).processAndStore(ownerId: ownerId, picked: picked);

  List<JournalTemplate> get templates => _templateWorkflow.available;

  Future<void> saveTemplateSelection({
    required String name,
    required EntryDocument source,
    required Iterable<CanvasNode> nodes,
    required DateTime createdAt,
  }) =>
      _templateWorkflow.saveSelection(
        name: name,
        source: source,
        nodes: nodes,
        createdAt: createdAt,
      );

  void insertTemplate({
    required Iterable<CanvasNode> nodes,
    required Offset offset,
  }) =>
      _templateWorkflow.insert(
        TemplateInsertion(nodes: List<CanvasNode>.unmodifiable(nodes), offset: offset),
        this,
      );

  List<CheckpointInfo> checkpointsFor(String id) =>
      _checkpointRecovery.forDocument(id);

  Future<void> createCheckpoint(String id) => _checkpointRecovery.create(id);

  Future<EntryDocument?> restoreCheckpoint({
    required String checkpointId,
    required String documentId,
  }) =>
      _checkpointRecovery.restore(
        checkpointId: checkpointId,
        documentId: documentId,
      );

  Future<bool> exportArchive({
    required String documentId,
    required String fileName,
    required JournalTransferService transfer,
  }) =>
      ArchiveTransferUseCase(
        archives: archiveRepository,
        transfer: transfer,
      ).exportDocument(documentId: documentId, fileName: fileName);

  Future<EntryDocument?> importArchive(JournalTransferService transfer) =>
      ArchiveTransferUseCase(
        archives: archiveRepository,
        transfer: transfer,
      ).importDocument();

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
