import 'dart:async';

import 'support/fake_journal_transfer.dart';

import 'package:journal_app/services/journal_archive.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:journal_app/models/document.dart';

import 'support/legacy_test_models.dart';

import 'package:journal_app/services/repositories.dart';
import 'package:journal_app/services/image_processing.dart';
import 'package:journal_app/services/journal_transfer_service.dart';
import 'package:journal_app/ui/features/editor/use_cases/archive_transfer_use_case.dart';
import 'package:journal_app/ui/features/editor/use_cases/image_insertion_use_case.dart';
import 'package:journal_app/ui/features/editor/view_models/entry_editor_view_model.dart';
import 'package:journal_app/ui/features/editor/view_models/editor_tool_state.dart';

void main() {
  test(
    'sharing commits pending text and preserves cancelled outcome',
    () async {
      final document = _document();
      final documents = _FakeDocumentRepository(document);
      final transfer = FakeJournalTransfer();
      final archives = _EditorArchives(documents);
      final editor = EntryEditorViewModel(
        document: document,
        documentRepository: documents,
        checkpointRepository: _FakeCheckpointRepository(),
        assetRepository: _NoopEditorCapabilities(),
        preferenceRepository: _NoopEditorCapabilities(),
        persistenceRepository: _SharePersistence(),
        archiveRepository: archives,
        musicCatalog: const DisabledMusicCatalogRepository(),
        imageInsertion: _noOpImageInsertion(),
        archiveTransfer: ArchiveTransferUseCase(
          archives: archives,
          transfer: transfer,
        ),
      );
      addTearDown(editor.dispose);
      addTearDown(transfer.events.close);
      editor.replaceText('text', 'Last keystroke');
      expect(await editor.sharePage(), JournalShareResult.dismissed);
      expect(
        transfer.shared.single.document.nodes.single.payload['text'],
        'Last keystroke',
      );
      expect(documents.savedDocuments.length, 1);
      expect(await editor.saveSharedPage(), isTrue);
      expect(transfer.saved.single, same(transfer.shared.single));
      documents.failSaves = true;
      editor.replaceText('text', 'Unsaved');
      await expectLater(editor.sharePage(), throwsStateError);
      expect(transfer.shared.length, 1);
    },
  );

  test('owns tool and selection presentation state', () {
    final document = _document();
    final editor = EntryEditorViewModel(
      document: document,
      documentRepository: _FakeDocumentRepository(document),
      checkpointRepository: _FakeCheckpointRepository(),
      assetRepository: _NoopEditorCapabilities(),
      preferenceRepository: _NoopEditorCapabilities(),
      persistenceRepository: _NoopEditorCapabilities(),
      archiveRepository: _NoopEditorCapabilities(),
      musicCatalog: const DisabledMusicCatalogRepository(),
      imageInsertion: _noOpImageInsertion(),
      archiveTransfer: _noOpArchiveTransfer(),
    );
    addTearDown(editor.dispose);

    editor.select('text');
    editor.editing = true;
    editor.selectMode = true;
    editor.drawMode = true;
    editor.textEditingId = 'text';

    expect(editor.selectedId, 'text');
    expect(editor.editing, isTrue);
    expect(editor.selectMode, isFalse);
    expect(editor.drawMode, isTrue);
    expect(editor.textEditingId, 'text');
  });

  test('owns immutable ink tool settings', () {
    final document = _document();
    final editor = EntryEditorViewModel(
      document: document,
      documentRepository: _FakeDocumentRepository(document),
      checkpointRepository: _FakeCheckpointRepository(),
      assetRepository: _NoopEditorCapabilities(),
      preferenceRepository: _NoopEditorCapabilities(),
      persistenceRepository: _NoopEditorCapabilities(),
      archiveRepository: _NoopEditorCapabilities(),
      musicCatalog: const DisabledMusicCatalogRepository(),
      imageInsertion: _noOpImageInsertion(),
      archiveTransfer: _noOpArchiveTransfer(),
    );
    addTearDown(editor.dispose);

    const updated = InkSettings(
      colorValue: 0xFF286A68,
      opacity: 0.6,
      width: 4.2,
      strokeType: InkStrokeType.marker,
    );
    editor.updateInkSettings(updated);

    expect(editor.inkSettings, updated);
    expect(editor.inkSettings.pickerValue, 0x99286A68);
    expect(editor.inkSettings.width, 4.2);
    expect(editor.inkSettings.strokeType, InkStrokeType.marker);
  });

  test('owns text and title formatting persistence', () async {
    final document = _document();
    final documents = _FakeDocumentRepository(document);
    final editor = EntryEditorViewModel(
      document: document,
      documentRepository: documents,
      checkpointRepository: _FakeCheckpointRepository(),
      assetRepository: _NoopEditorCapabilities(),
      preferenceRepository: _NoopEditorCapabilities(),
      persistenceRepository: _NoopEditorCapabilities(),
      archiveRepository: _NoopEditorCapabilities(),
      musicCatalog: const DisabledMusicCatalogRepository(),
      imageInsertion: _noOpImageInsertion(),
      archiveTransfer: _noOpArchiveTransfer(),
    );
    addTearDown(editor.dispose);

    await editor.updateTextFormatting(
      'text',
      fontFamily: JournalFonts.lora,
      fontSize: 32,
      bold: true,
      italic: true,
      textColorValue: 0xFF873F4D,
    );
    final node = editor.document.nodeById('text');
    expect(node?.fontFamily, JournalFonts.lora);
    expect(node?.fontSize, 32);
    expect(node?.bold, isTrue);
    expect(node?.italic, isTrue);
    expect(node?.textColorValue, 0xFF873F4D);

    await editor.updateTitleFormatting(
      fontFamily: JournalFonts.caveat,
      fontSize: 36,
      bold: false,
      italic: true,
      textColorValue: 0xFF286A68,
    );
    expect(editor.document.titleFontFamily, JournalFonts.caveat);
    expect(editor.document.titleFontSize, 36);
    expect(editor.document.titleBold, isFalse);
    expect(editor.document.titleItalic, isTrue);
    expect(editor.document.titleTextColorValue, 0xFF286A68);
    expect(documents.savedDocuments, hasLength(2));
  });

  test('sets photo preview as metadata without adding undo history', () async {
    final photo = CanvasNode(
      id: 'photo',
      type: BlockType.image,
      transform: const Transform2D(width: 30, height: 20),
      payload: const {'assetId': 'asset'},
    );
    final document = _document().copyWith(nodes: [..._document().nodes, photo]);
    final documents = _FakeDocumentRepository(document);
    final editor = EntryEditorViewModel(
      document: document,
      documentRepository: documents,
      checkpointRepository: _FakeCheckpointRepository(),
      assetRepository: _NoopEditorCapabilities(),
      preferenceRepository: _NoopEditorCapabilities(),
      persistenceRepository: _NoopEditorCapabilities(),
      archiveRepository: _NoopEditorCapabilities(),
      musicCatalog: const DisabledMusicCatalogRepository(),
      imageInsertion: _noOpImageInsertion(),
      archiveTransfer: _noOpArchiveTransfer(),
    );
    addTearDown(editor.dispose);

    expect(editor.canUndo, isFalse);
    await editor.setPreviewImage('photo');
    expect(editor.document.previewImageNodeId, 'photo');
    expect(documents.savedDocuments.single.previewImageNodeId, 'photo');
    expect(editor.canUndo, isFalse);

    await editor.setPreviewImage('text');
    expect(documents.savedDocuments, hasLength(1));
  });

  test('persists editor transactions through narrow repositories', () async {
    final document = _document();
    final documents = _FakeDocumentRepository(document);
    final checkpoints = _FakeCheckpointRepository();
    final editor = EntryEditorViewModel(
      document: document,
      documentRepository: documents,
      checkpointRepository: checkpoints,
      assetRepository: _NoopEditorCapabilities(),
      preferenceRepository: _NoopEditorCapabilities(),
      persistenceRepository: _NoopEditorCapabilities(),
      archiveRepository: _NoopEditorCapabilities(),
      musicCatalog: const DisabledMusicCatalogRepository(),
      imageInsertion: _noOpImageInsertion(),
      archiveTransfer: _noOpArchiveTransfer(),
    );
    addTearDown(editor.dispose);

    editor.select('text');
    editor.beginTransformTransaction('Move');
    editor.moveSelection(const Offset(5, -2));
    await editor.commitTransaction();

    final saved = documents.documents.single;
    expect(saved.nodes.single.transform.x, 15);
    expect(saved.nodes.single.transform.y, 8);
    expect(editor.document.nodes.single.transform.x, 15);
    expect(documents.savedDocuments, hasLength(1));
    expect(checkpoints.scheduledDocumentIds, <String>['entry']);
  });

  test('cancelling a transaction does not call the document repository', () {
    final document = _document();
    final documents = _FakeDocumentRepository(document);
    final editor = EntryEditorViewModel(
      document: document,
      documentRepository: documents,
      checkpointRepository: _FakeCheckpointRepository(),
      assetRepository: _NoopEditorCapabilities(),
      preferenceRepository: _NoopEditorCapabilities(),
      persistenceRepository: _NoopEditorCapabilities(),
      archiveRepository: _NoopEditorCapabilities(),
      musicCatalog: const DisabledMusicCatalogRepository(),
      imageInsertion: _noOpImageInsertion(),
      archiveTransfer: _noOpArchiveTransfer(),
    );
    addTearDown(editor.dispose);

    editor.select('text');
    editor.beginTransformTransaction('Move');
    editor.moveSelection(const Offset(5, -2));
    editor.cancelTransaction();

    expect(editor.document.nodes.single.transform.x, 10);
    expect(editor.document.nodes.single.transform.y, 10);
    expect(documents.savedDocuments, isEmpty);
  });

  test('owns metadata persistence and reports workflow failures', () async {
    final document = _document();
    final documents = _FakeDocumentRepository(document);
    final editor = EntryEditorViewModel(
      document: document,
      documentRepository: documents,
      checkpointRepository: _FakeCheckpointRepository(),
      assetRepository: _NoopEditorCapabilities(),
      preferenceRepository: _NoopEditorCapabilities(),
      persistenceRepository: _NoopEditorCapabilities(),
      archiveRepository: _NoopEditorCapabilities(),
      musicCatalog: const DisabledMusicCatalogRepository(),
      imageInsertion: _noOpImageInsertion(),
      archiveTransfer: _noOpArchiveTransfer(),
    );
    addTearDown(editor.dispose);

    await editor.updateMetadata(
      document.copyWith(title: 'Renamed', modifiedAt: DateTime.utc(2026, 2)),
    );
    expect(editor.document.title, 'Renamed');
    expect(documents.savedDocuments.single.title, 'Renamed');
    expect(editor.workflowError, isNull);

    documents.failSaves = true;
    await editor.updateMetadata(document.copyWith(title: 'Failed'));
    expect(editor.document.title, 'Failed');
    expect(editor.workflowError, contains('save failed'));
    documents.failSaves = false;
    await editor.retrySave();
    expect(editor.workflowError, isNull);
    expect(documents.savedDocuments.last.title, 'Failed');
    editor.clearWorkflowError();
    expect(editor.workflowError, isNull);
  });
}

EntryDocument _document() => EntryDocumentCodec.fromEntry(
  Entry(
    id: 'entry',
    title: 'Test entry',
    createdAt: DateTime.utc(2026),
    blocks: [
      ContentBlock(
        id: 'text',
        type: BlockType.text,
        x: 10,
        y: 10,
        w: 40,
        h: 20,
        text: 'Hello',
      ),
    ],
  ),
);

class _FakeDocumentRepository implements DocumentRepository {
  _FakeDocumentRepository(EntryDocument document)
    : _documents = <EntryDocument>[document];

  final StreamController<void> _changes = StreamController<void>.broadcast();
  final List<EntryDocument> _documents;
  final List<EntryDocument> savedDocuments = <EntryDocument>[];
  bool failSaves = false;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  List<EntryDocument> get documents => List.unmodifiable(_documents);

  @override
  Future<void> init() async {}

  @override
  Future<EntryDocument> createDocument({String title = ''}) async =>
      _documents.first;

  @override
  Future<void> saveDocument(EntryDocument document) async {
    if (failSaves) throw StateError('save failed');
    savedDocuments.add(document);
    final index = _documents.indexWhere((item) => item.id == document.id);
    _documents[index] = document;
    _changes.add(null);
  }

  @override
  void previewDocument(EntryDocument document) {
    final index = _documents.indexWhere((item) => item.id == document.id);
    _documents[index] = document;
  }

  @override
  Future<void> deleteDocument(String id) async {
    _documents.removeWhere((document) => document.id == id);
    _changes.add(null);
  }
}

class _FakeCheckpointRepository implements CheckpointRepository {
  final List<String> scheduledDocumentIds = <String>[];

  @override
  List<CheckpointInfo> checkpointsFor(String documentId) =>
      const <CheckpointInfo>[];

  @override
  void scheduleCheckpoint(String documentId) {
    scheduledDocumentIds.add(documentId);
  }

  @override
  Future<void> createCheckpoint(String documentId) async {}

  @override
  Future<void> restoreCheckpoint(String checkpointId) async {}
}

ImageInsertionUseCase _noOpImageInsertion() => ImageInsertionUseCase(
  assets: _NoopEditorCapabilities(),
  processor: const ImageProcessor(),
);

ArchiveTransferUseCase _noOpArchiveTransfer() => ArchiveTransferUseCase(
  archives: _NoopEditorCapabilities(),
  transfer: const JournalTransferService(),
);

/// The focused VM tests exercise core editor behavior; uncalled workflow
/// capabilities are represented by one explicit no-op test double rather than
/// making production dependencies nullable.
class _NoopEditorCapabilities
    implements
        AssetRepository,
        PreferencesRepository,
        PersistenceRepository,
        ArchiveRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _EditorArchives implements ArchiveRepository {
  _EditorArchives(this.documents);
  final _FakeDocumentRepository documents;
  @override
  JournalArchive? archiveForDocument(String id) =>
      JournalArchive(document: documents.documents.single);
  @override
  Future<EntryDocument> importArchive(JournalArchive archive) =>
      throw UnimplementedError();
}

class _SharePersistence implements PersistenceRepository {
  @override
  void addFlushHook(Future<void> Function() hook) {}
  @override
  void removeFlushHook(Future<void> Function() hook) {}
  @override
  Future<void> flush() async {}
}
