import 'dart:typed_data';

import '../models/document.dart';
import '../models/template.dart';
import 'hive_capability_sources.dart';
import 'hive_journal_data_source.dart';
import 'journal_archive.dart';
import 'repositories.dart';

/// Document capability adapter backed by the internal Hive document source.
class HiveDocumentRepository implements DocumentRepository {
  HiveDocumentRepository.fromDataSource(
    this._source, {
    this._collectUnreferencedAssets,
  });

  final HiveDocumentDataSource _source;
  final Future<void> Function()? _collectUnreferencedAssets;

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
  Future<void> deleteDocument(String id) async {
    await _source.deleteDocument(id);
    await _collectUnreferencedAssets?.call();
  }
}

/// Asset capability adapter backed by the internal Hive asset source.
class HiveAssetRepository implements AssetRepository {
  HiveAssetRepository.fromDataSource(this._source);

  final HiveAssetDataSource _source;

  @override
  Future<String> putAsset(
    String ownerId,
    AssetKind kind,
    String mime,
    List<int> bytes,
  ) =>
      _source.putAsset(ownerId, kind, mime, bytes);

  @override
  Uint8List? readAsset(String id) => _source.readAsset(id);

  @override
  String? assetMime(String id) => _source.assetMime(id);

  @override
  Future<void> collectUnreferencedAssets({
    Iterable<String> retainedAssetIds = const <String>[],
  }) =>
      _source.collectUnreferencedAssets(retainedAssetIds: retainedAssetIds);
}

/// Checkpoint capability adapter backed by the internal Hive checkpoint source.
class HiveCheckpointRepository implements CheckpointRepository {
  HiveCheckpointRepository.fromDataSource(this._source);

  final HiveCheckpointDataSource _source;

  @override
  List<CheckpointInfo> checkpointsFor(String documentId) =>
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

/// Template capability adapter backed by the internal Hive template source.
class HiveTemplateRepository implements TemplateRepository {
  HiveTemplateRepository.fromDataSource(this._source);

  final HiveTemplateDataSource _source;

  @override
  List<JournalTemplate> get templates => _source.templates;

  @override
  Future<void> saveTemplate(JournalTemplate template) =>
      _source.saveTemplate(template);

  @override
  Future<void> deleteTemplate(String id) => _source.deleteTemplate(id);
}

/// Preferences capability adapter backed by the internal Hive meta source.
class HivePreferencesRepository implements PreferencesRepository {
  HivePreferencesRepository.fromDataSource(this._source);

  final HivePreferencesDataSource _source;

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

/// Archive capability adapter backed by focused internal data sources.
class HiveArchiveRepository implements ArchiveRepository {
  HiveArchiveRepository.fromDataSource(this._source);

  final HiveArchiveDataSource _source;

  @override
  JournalArchive? archiveForDocument(String id) =>
      _source.archiveForDocument(id);

  @override
  Future<EntryDocument> importArchive(JournalArchive archive) =>
      _source.importArchive(archive);
}

/// Persistence capability adapter backed by the raw Hive data source.
class HivePersistenceRepository implements PersistenceRepository {
  HivePersistenceRepository.fromDataSource(this._source);

  final HiveJournalDataSource _source;

  @override
  void addFlushHook(Future<void> Function() hook) {
    // Application-level ordering is owned by PersistenceCoordinator. The raw
    // repository intentionally exposes only storage flushing.
  }

  @override
  void removeFlushHook(Future<void> Function() hook) {}

  @override
  Future<void> flush() => _source.flush();
}

/// Builds the capability bundle from focused Hive data sources.
class HiveRepositorySet {
  HiveRepositorySet.fromDataSource(
    HiveJournalDataSource source, {
    PersistenceRepository? persistence,
  }) {
    final documents = HiveDocumentDataSource(source);
    final assets = HiveAssetDataSource(
      source,
      documents: () => documents.documents,
    );
    final checkpoints = HiveCheckpointDataSource(source, documents: documents);
    final templates = HiveTemplateDataSource(source);
    final preferences = HivePreferencesDataSource(source);
    final archive = HiveArchiveDataSource(
      source,
      documents: documents,
      assets: assets,
      templates: templates,
    );
    repositories = JournalRepositories(
      documentRepository: HiveDocumentRepository.fromDataSource(
        documents,
        collectUnreferencedAssets: assets.collectUnreferencedAssets,
      ),
      assetRepository: HiveAssetRepository.fromDataSource(assets),
      checkpointRepository: HiveCheckpointRepository.fromDataSource(
        checkpoints,
      ),
      templateRepository: HiveTemplateRepository.fromDataSource(templates),
      preferenceRepository: HivePreferencesRepository.fromDataSource(
        preferences,
      ),
      persistence:
          persistence ?? HivePersistenceRepository.fromDataSource(source),
      archiveRepository: HiveArchiveRepository.fromDataSource(archive),
    );
    _documentSource = documents;
    _checkpointSource = checkpoints;
  }

  late final JournalRepositories repositories;
  HiveDocumentDataSource? _documentSource;
  HiveCheckpointDataSource? _checkpointSource;

  void dispose() {
    _checkpointSource?.dispose();
    _documentSource?.dispose();
  }
}

