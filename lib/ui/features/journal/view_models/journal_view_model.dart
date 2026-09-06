import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../models/document.dart';
import '../../../../models/document_order.dart';
import '../../../../models/page_music.dart';
import '../../../../services/repositories.dart';

/// Presentation state and commands for the journal page shell.
class JournalViewModel extends ChangeNotifier {
  JournalViewModel({
    required DocumentRepository repository,
    this._assetRepository,
  }) : _repository = repository,
       _documents = chronologicalDocuments(repository.documents) {
    _changesSubscription = repository.changes.listen((_) => _refresh());
  }

  final DocumentRepository _repository;
  final AssetRepository? _assetRepository;
  late final StreamSubscription<void> _changesSubscription;
  List<EntryDocument> _documents;

  List<EntryDocument> get documents => _documents;

  /// Reads an immutable asset for a contents preview without exposing the
  /// repository to the view.
  Uint8List? readAsset(String id) {
    final blob = _assetRepository?.readAsset(id);
    return blob == null ? null : Uint8List.fromList(blob.bytes);
  }

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

  Future<void> renamePage(String id, String title) async {
    final document = documentById(id);
    final trimmed = title.trim();
    if (document == null || trimmed.isEmpty || trimmed == document.title) return;
    await saveDocument(
      document.copyWith(title: trimmed, modifiedAt: DateTime.now()),
    );
  }

  /// Persists a catalog-resolved track without exposing the document
  /// repository to the music controller or its views.
  Future<void> persistResolvedTrack(String pageId, PageMusicTrack track) async {
    final document = documentById(pageId);
    if (document == null) return;
    await saveDocument(
      document.copyWith(music: track, modifiedAt: DateTime.now()),
    );
  }

  /// Publishes a responsive editor preview through the document capability.
  void previewDocument(EntryDocument document) =>
      _repository.previewDocument(document);

  Future<void> deletePage(String id) async {
    await _repository.deleteDocument(id);
    _refresh();
  }

  void _refresh() {
    _documents = chronologicalDocuments(_repository.documents);
    if (hasListeners) notifyListeners();
  }

  @override
  void dispose() {
    _changesSubscription.cancel();
    super.dispose();
  }
}
