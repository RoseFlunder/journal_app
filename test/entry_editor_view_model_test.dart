import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/models/document.dart';
import 'package:journal_app/models/entry.dart';
import 'package:journal_app/services/journal_store.dart';
import 'package:journal_app/services/repositories.dart';
import 'package:journal_app/ui/features/editor/view_models/entry_editor_view_model.dart';

void main() {
  test('persists editor transactions through narrow repositories', () async {
    final document = _document();
    final documents = _FakeDocumentRepository(document);
    final checkpoints = _FakeCheckpointRepository();
    final editor = EntryEditorViewModel(
      document: document,
      documentRepository: documents,
      checkpointRepository: checkpoints,
    );
    addTearDown(editor.dispose);

    editor.select('text');
    editor.beginTransaction('Move');
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
    );
    addTearDown(editor.dispose);

    editor.select('text');
    editor.beginTransaction('Move');
    editor.moveSelection(const Offset(5, -2));
    editor.cancelTransaction();

    expect(editor.document.nodes.single.transform.x, 10);
    expect(editor.document.nodes.single.transform.y, 10);
    expect(documents.savedDocuments, isEmpty);
  });
}

EntryDocument _document() => EntryDocument.fromEntry(
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
  List<EntryCheckpoint> checkpointsFor(String documentId) =>
      const <EntryCheckpoint>[];

  @override
  void scheduleCheckpoint(String documentId) {
    scheduledDocumentIds.add(documentId);
  }

  @override
  Future<void> createCheckpoint(String documentId) async {}

  @override
  Future<void> restoreCheckpoint(String checkpointId) async {}
}
