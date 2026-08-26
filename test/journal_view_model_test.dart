import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:journal_app/models/document.dart';
import 'package:journal_app/models/template.dart';
import 'package:journal_app/services/journal_archive.dart';
import 'package:journal_app/services/journal_store.dart';
import 'package:journal_app/services/repositories.dart';
import 'package:journal_app/view_models/journal_view_model.dart';

void main() {
  test('publishes immutable document changes from the repository', () async {
    final repository = _FakeJournalRepository();
    final viewModel = JournalViewModel(repository: repository);
    addTearDown(viewModel.dispose);
    final document = _document('first');

    await viewModel.saveDocument(document);
    expect(viewModel.documents.single.id, 'first');
    expect(viewModel.documentById('first')?.title, 'First page');

    final replacement = document.copyWith(title: 'Updated page');
    await viewModel.saveDocument(replacement);
    expect(viewModel.documents.single.title, 'Updated page');
  });

  test('creates and deletes pages through repository commands', () async {
    final repository = _FakeJournalRepository();
    final viewModel = JournalViewModel(repository: repository);
    addTearDown(viewModel.dispose);

    final created = await viewModel.createPage(title: 'New page');
    expect(viewModel.indexOf(created.id), 0);

    await viewModel.deletePage(created.id);
    expect(viewModel.documents, isEmpty);
  });
}

EntryDocument _document(String id) => EntryDocument(
  id: id,
  title: 'First page',
  createdAt: DateTime.utc(2026),
  modifiedAt: DateTime.utc(2026),
);

class _FakeJournalRepository implements JournalRepository {
  final StreamController<void> _changes = StreamController<void>.broadcast();
  final List<EntryDocument> _documents = <EntryDocument>[];
  int _nextId = 0;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  List<EntryDocument> get documents => List.unmodifiable(_documents);

  @override
  Future<void> init() async {}

  @override
  Future<EntryDocument> createDocument({String title = ''}) async {
    final id = 'created-${_nextId++}';
    final document = EntryDocument(
      id: id,
      title: title,
      createdAt: DateTime.utc(2026),
      modifiedAt: DateTime.utc(2026),
    );
    _documents.add(document);
    _changes.add(null);
    return document;
  }

  @override
  Future<void> saveDocument(EntryDocument document) async {
    final index = _documents.indexWhere((item) => item.id == document.id);
    if (index < 0) {
      _documents.add(document);
    } else {
      _documents[index] = document;
    }
    _changes.add(null);
  }

  @override
  void previewDocument(EntryDocument document) {
    final index = _documents.indexWhere((item) => item.id == document.id);
    if (index >= 0) _documents[index] = document;
  }

  @override
  Future<void> deleteDocument(String id) async {
    _documents.removeWhere((document) => document.id == id);
    _changes.add(null);
  }

  @override
  Future<void> flush() async {}

  @override
  JournalArchive? archiveForDocument(String id) => null;

  @override
  Future<EntryDocument> importArchive(JournalArchive archive) async =>
      archive.document;

  @override
  void addFlushHook(Future<void> Function() hook) {}

  @override
  void removeFlushHook(Future<void> Function() hook) {}

  @override
  List<int> get recentColorValues => const <int>[];

  @override
  Set<int> get favoriteColorValues => const <int>{};

  @override
  Future<void> updateColorPreferences({
    List<int>? recent,
    Set<int>? favorites,
  }) async {}

  @override
  Future<String> putAsset(
    String ownerId,
    AssetKind kind,
    String mime,
    List<int> bytes,
  ) async => 'asset';

  @override
  Uint8List? readAsset(String id) => null;

  @override
  String? assetMime(String id) => null;

  @override
  Future<void> collectUnreferencedAssets() async {}

  @override
  List<EntryCheckpoint> checkpointsFor(String documentId) =>
      const <EntryCheckpoint>[];

  @override
  void scheduleCheckpoint(String documentId) {}

  @override
  Future<void> createCheckpoint(String documentId) async {}

  @override
  Future<void> restoreCheckpoint(String checkpointId) async {}

  @override
  List<JournalTemplate> get templates => const <JournalTemplate>[];

  @override
  Future<void> saveTemplate(JournalTemplate template) async {}

  @override
  Future<void> deleteTemplate(String id) async {}
}
