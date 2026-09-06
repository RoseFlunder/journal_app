import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:journal_app/models/document.dart';
import 'package:journal_app/services/repositories.dart';
import 'package:journal_app/ui/features/journal/view_models/journal_view_model.dart';

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

  test('renames pages through the document repository', () async {
    final repository = _FakeJournalRepository();
    final viewModel = JournalViewModel(repository: repository);
    addTearDown(viewModel.dispose);

    final created = await viewModel.createPage(title: 'First title');
    await viewModel.renamePage(created.id, '  New title  ');

    expect(viewModel.documents.single.title, 'New title');
    expect(
      viewModel.documents.single.modifiedAt.isAfter(created.modifiedAt),
      isTrue,
    );
  });
}

EntryDocument _document(String id) => EntryDocument(
  id: id,
  title: 'First page',
  createdAt: DateTime.utc(2026),
  modifiedAt: DateTime.utc(2026),
);

class _FakeJournalRepository implements DocumentRepository {
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

}
