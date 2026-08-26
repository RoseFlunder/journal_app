import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/document.dart';
import '../services/repositories.dart';

/// Presentation state and commands for the journal page shell.
///
/// The view model deliberately exposes immutable documents. Storage remains
/// behind [JournalRepository], which lets the shell use an in-memory fake in
/// tests and keeps Hive-specific details out of the views.
class JournalViewModel extends ChangeNotifier {
  JournalViewModel({required DocumentRepository repository})
    : _repository = repository,
      _documents = List.unmodifiable(repository.documents) {
    _changesSubscription = repository.changes.listen((_) => _refresh());
  }

  final DocumentRepository _repository;
  late final StreamSubscription<void> _changesSubscription;
  List<EntryDocument> _documents;

  List<EntryDocument> get documents => _documents;

  EntryDocument? documentById(String id) {
    for (final document in _documents) {
      if (document.id == id) return document;
    }
    return null;
  }

  int indexOf(String id) =>
      _documents.indexWhere((document) => document.id == id);

  Future<EntryDocument> createPage({String title = ''}) async {
    final document = await _repository.createDocument(title: title);
    _refresh();
    return document;
  }

  Future<void> saveDocument(EntryDocument document) async {
    await _repository.saveDocument(document);
    _refresh();
  }

  Future<void> deletePage(String id) async {
    await _repository.deleteDocument(id);
    _refresh();
  }

  void _refresh() {
    _documents = List.unmodifiable(_repository.documents);
    if (hasListeners) notifyListeners();
  }

  @override
  void dispose() {
    _changesSubscription.cancel();
    super.dispose();
  }
}
