import 'dart:typed_data';

import 'package:journal_app/models/document.dart';
import 'package:journal_app/models/template.dart';
import 'package:journal_app/services/entry_document_codec.dart';
import 'package:journal_app/services/journal_archive.dart';
import 'package:journal_app/services/journal_store.dart';
import 'package:journal_app/services/repositories.dart';

/// Test-only bridge for legacy storage tests that exercise [JournalStore]
/// itself. Production code must use the direct capability adapters.
class HiveDocumentRepository implements DocumentRepository {
  HiveDocumentRepository(this._source);
  final JournalStore _source;

  @override
  Future<void> init() => _source.init();

  @override
  List<EntryDocument> get documents =>
      _source.entries.map(EntryDocumentCodec.fromEntry).toList(growable: false);

  @override
  Stream<void> get changes => _source.changes;

  @override
  Future<EntryDocument> createDocument({String title = ''}) =>
      _source.addEntry(title: title).then(EntryDocumentCodec.fromEntry);

  @override
  Future<void> saveDocument(EntryDocument document) {
    final next = EntryDocumentCodec.toEntry(document);
    return _source.updateEntry(document.id, (entry) {
      entry
        ..title = next.title
        ..blocks = next.blocks
        ..board = next.board
        ..view = next.view
        ..music = next.music
        ..titleFontSize = next.titleFontSize
        ..titleFontFamily = next.titleFontFamily
        ..titleTextColorValue = next.titleTextColorValue
        ..titleBold = next.titleBold
        ..titleItalic = next.titleItalic
        ..revision = next.revision
        ..schemaVersion = next.schemaVersion;
    });
  }

  @override
  void previewDocument(EntryDocument document) {
    final next = EntryDocumentCodec.toEntry(document);
    _source.previewEntry(document.id, (entry) {
      entry
        ..title = next.title
        ..blocks = next.blocks
        ..board = next.board
        ..view = next.view
        ..music = next.music
        ..titleFontSize = next.titleFontSize
        ..titleFontFamily = next.titleFontFamily
        ..titleTextColorValue = next.titleTextColorValue
        ..titleBold = next.titleBold
        ..titleItalic = next.titleItalic;
    });
  }

  @override
  Future<void> deleteDocument(String id) => _source.deleteEntry(id);
}

class HiveAssetRepository implements AssetRepository {
  HiveAssetRepository(this._source);
  final JournalStore _source;

  @override
  Future<String> putAsset(
    String ownerId,
    AssetKind kind,
    String mime,
    List<int> bytes,
  ) =>
      _source.addAsset(ownerId, kind, mime, bytes);

  @override
  Uint8List? readAsset(String id) => _source.getAsset(id);

  @override
  String? assetMime(String id) => _source.getAssetMime(id);

  @override
  Future<void> collectUnreferencedAssets({
    Iterable<String> retainedAssetIds = const <String>[],
  }) =>
      _source.collectUnreferencedAssets(retainedAssetIds: retainedAssetIds);
}

class HiveCheckpointRepository implements CheckpointRepository {
  HiveCheckpointRepository(this._source);
  final JournalStore _source;

  @override
  List<CheckpointInfo> checkpointsFor(String documentId) => _source
      .checkpointsFor(documentId)
      .map(
        (checkpoint) => CheckpointInfo(
          id: checkpoint.id,
          documentId: checkpoint.entryId,
          createdAt: checkpoint.createdAt,
        ),
      )
      .toList(growable: false);

  @override
  void scheduleCheckpoint(String documentId) =>
      _source.scheduleCheckpoint(documentId);

  @override
  Future<void> createCheckpoint(String documentId) =>
      _source.createCheckpoint(documentId);

  @override
  Future<void> restoreCheckpoint(String checkpointId) =>
      _source.restoreCheckpoint(checkpointId);
}

class HiveTemplateRepository implements TemplateRepository {
  HiveTemplateRepository(this._source);
  final JournalStore _source;

  @override
  List<JournalTemplate> get templates => _source.templates;

  @override
  Future<void> saveTemplate(JournalTemplate template) =>
      _source.saveTemplate(template);

  @override
  Future<void> deleteTemplate(String id) => _source.deleteTemplate(id);
}

class HivePreferencesRepository implements PreferencesRepository {
  HivePreferencesRepository(this._source);
  final JournalStore _source;

  @override
  List<int> get recentColorValues => _source.recentColorValues;

  @override
  Set<int> get favoriteColorValues => _source.favoriteColorValues;

  @override
  Future<void> updateColorPreferences({
    List<int>? recent,
    Set<int>? favorites,
  }) =>
      _source.updateColorPreferences(recent: recent, favorites: favorites);
}

class HiveArchiveRepository implements ArchiveRepository {
  HiveArchiveRepository(this._source);
  final JournalStore _source;

  @override
  JournalArchive? archiveForDocument(String id) =>
      _source.archiveForEntry(id);

  @override
  Future<EntryDocument> importArchive(JournalArchive archive) =>
      _source.importArchive(archive).then(EntryDocumentCodec.fromEntry);
}

class HivePersistenceRepository implements PersistenceRepository {
  HivePersistenceRepository(this._source);
  final JournalStore _source;

  @override
  void addFlushHook(Future<void> Function() hook) => _source.addFlushHook(hook);

  @override
  void removeFlushHook(Future<void> Function() hook) =>
      _source.removeFlushHook(hook);

  @override
  Future<void> flush() => _source.flush();
}

class HiveRepositorySet {
  HiveRepositorySet(
    JournalStore source, {
    PersistenceRepository? persistence,
  }) {
    repositories = JournalRepositories(
      documentRepository: HiveDocumentRepository(source),
      assetRepository: HiveAssetRepository(source),
      checkpointRepository: HiveCheckpointRepository(source),
      templateRepository: HiveTemplateRepository(source),
      preferenceRepository: HivePreferencesRepository(source),
      persistence: persistence ?? HivePersistenceRepository(source),
      archiveRepository: HiveArchiveRepository(source),
    );
  }

  late final JournalRepositories repositories;
}

