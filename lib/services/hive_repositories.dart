import 'dart:async';
import 'dart:typed_data';

import '../models/document.dart';
import '../models/storage_records.dart';
import '../models/template.dart';
import 'journal_archive.dart';
import 'repositories.dart';

/// Explicit capability repositories for the current Hive-backed store.
///
/// These adapters intentionally share one source while persistence is being
/// migrated. Keeping the capabilities as separate objects prevents UI code
/// from depending on the aggregate and makes each adapter independently
/// replaceable with a data-source-backed implementation.
class HiveDocumentRepository implements DocumentRepository {
  const HiveDocumentRepository(this._source);

  final JournalRepository _source;

  @override
  Future<void> init() => _source.init();

  @override
  List<EntryDocument> get documents => _source.documents;

  @override
  Stream<void> get changes => _source.changes;

  @override
  Future<EntryDocument> createDocument({String title = ''}) =>
      _source.createDocument(title: title);

  @override
  Future<void> saveDocument(EntryDocument document) =>
      _source.saveDocument(document);

  @override
  void previewDocument(EntryDocument document) =>
      _source.previewDocument(document);

  @override
  Future<void> deleteDocument(String id) => _source.deleteDocument(id);
}

class HiveAssetRepository implements AssetRepository {
  const HiveAssetRepository(this._source);

  final JournalRepository _source;

  @override
  Future<String> putAsset(
    String ownerId,
    AssetKind kind,
    String mime,
    List<int> bytes,
  ) => _source.putAsset(ownerId, kind, mime, bytes);

  @override
  Uint8List? readAsset(String id) => _source.readAsset(id);

  @override
  String? assetMime(String id) => _source.assetMime(id);

  @override
  Future<void> collectUnreferencedAssets() =>
      _source.collectUnreferencedAssets();
}

class HiveCheckpointRepository implements CheckpointRepository {
  const HiveCheckpointRepository(this._source);

  final JournalRepository _source;

  @override
  List<EntryCheckpoint> checkpointsFor(String documentId) =>
      _source.checkpointsFor(documentId);

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
  const HiveTemplateRepository(this._source);

  final JournalRepository _source;

  @override
  List<JournalTemplate> get templates => _source.templates;

  @override
  Future<void> saveTemplate(JournalTemplate template) =>
      _source.saveTemplate(template);

  @override
  Future<void> deleteTemplate(String id) => _source.deleteTemplate(id);
}

class HivePreferencesRepository implements PreferencesRepository {
  const HivePreferencesRepository(this._source);

  final JournalRepository _source;

  @override
  List<int> get recentColorValues => _source.recentColorValues;

  @override
  Set<int> get favoriteColorValues => _source.favoriteColorValues;

  @override
  Future<void> updateColorPreferences({
    List<int>? recent,
    Set<int>? favorites,
  }) => _source.updateColorPreferences(recent: recent, favorites: favorites);
}

class HiveArchiveRepository implements ArchiveRepository {
  const HiveArchiveRepository(this._source);

  final JournalRepository _source;

  @override
  JournalArchive? archiveForDocument(String id) =>
      _source.archiveForDocument(id);

  @override
  Future<EntryDocument> importArchive(JournalArchive archive) =>
      _source.importArchive(archive);
}

class HivePersistenceRepository implements PersistenceRepository {
  const HivePersistenceRepository(this._source);

  final JournalRepository _source;

  @override
  void addFlushHook(Future<void> Function() hook) =>
      _source.addFlushHook(hook);

  @override
  void removeFlushHook(Future<void> Function() hook) =>
      _source.removeFlushHook(hook);

  @override
  Future<void> flush() => _source.flush();
}

/// Builds the capability set used by production while retaining the source
/// for application-level lifecycle disposal.
class HiveRepositorySet {
  HiveRepositorySet(
    JournalRepository source, {
    PersistenceRepository? persistence,
  }) {
    final persistenceRepository =
        persistence ?? HivePersistenceRepository(source);
    repositories = JournalRepositories(
      documentRepository: HiveDocumentRepository(source),
      assetRepository: HiveAssetRepository(source),
      checkpointRepository: HiveCheckpointRepository(source),
      templateRepository: HiveTemplateRepository(source),
      preferenceRepository: HivePreferencesRepository(source),
      persistence: persistenceRepository,
      archiveRepository: HiveArchiveRepository(source),
    );
  }

  late final JournalRepositories repositories;
}
