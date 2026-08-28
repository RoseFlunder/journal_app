import 'dart:typed_data';

import '../models/document.dart';
import '../models/template.dart';
import 'entry_document_codec.dart';
import 'hive_capability_sources.dart';
import 'hive_journal_data_source.dart';
import 'journal_archive.dart';
import 'journal_store.dart';
import 'repositories.dart';

/// Document capability adapter backed by the internal Hive document source.
class HiveDocumentRepository implements DocumentRepository {
  /// Compatibility constructor for storage-focused tests that still own the
  /// mutable store. Production uses [HiveDocumentRepository.fromDataSource].
  factory HiveDocumentRepository(JournalStore source) =>
      HiveDocumentRepository._legacy(source);

  HiveDocumentRepository._legacy(this._legacySource)
      : _source = null,
        _collectUnreferencedAssets = null;

  HiveDocumentRepository.fromDataSource(
    this._source, {
    this._collectUnreferencedAssets,
  }) : _legacySource = null;

  final HiveDocumentDataSource? _source;
  final Future<void> Function()? _collectUnreferencedAssets;
  final JournalStore? _legacySource;

  @override
  Future<void> init() => _source?.init() ?? _legacySource!.init();

  @override
  List<EntryDocument> get documents =>
      _source?.documents ??
      _legacySource!.entries.map(EntryDocumentCodec.fromEntry).toList(
        growable: false,
      );

  @override
  Stream<void> get changes => _source?.changes ?? _legacySource!.changes;

  @override
  Future<EntryDocument> createDocument({String title = ''}) =>
      _source?.createDocument(title: title) ??
      _legacySource!.addEntry(title: title).then(EntryDocumentCodec.fromEntry);

  @override
  Future<void> saveDocument(EntryDocument document) {
    final source = _source;
    if (source != null) return source.saveDocument(document);
    final next = EntryDocumentCodec.toEntry(document);
    return _legacySource!.updateEntry(document.id, (entry) {
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
    final source = _source;
    if (source != null) {
      source.previewDocument(document);
      return;
    }
    final next = EntryDocumentCodec.toEntry(document);
    _legacySource!.previewEntry(document.id, (entry) {
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
  Future<void> deleteDocument(String id) async {
    final source = _source;
    if (source != null) {
      await source.deleteDocument(id);
      await _collectUnreferencedAssets?.call();
      return;
    }
    await _legacySource!.deleteEntry(id);
  }
}

/// Asset capability adapter backed by the internal Hive asset source.
class HiveAssetRepository implements AssetRepository {
  factory HiveAssetRepository(JournalStore source) =>
      HiveAssetRepository._legacy(source);

  HiveAssetRepository._legacy(this._legacySource) : _source = null;
  HiveAssetRepository.fromDataSource(this._source) : _legacySource = null;

  final HiveAssetDataSource? _source;
  final JournalStore? _legacySource;

  @override
  Future<String> putAsset(
    String ownerId,
    AssetKind kind,
    String mime,
    List<int> bytes,
  ) =>
      _source?.putAsset(ownerId, kind, mime, bytes) ??
      _legacySource!.addAsset(ownerId, kind, mime, bytes);

  @override
  Uint8List? readAsset(String id) {
    final source = _source;
    return source != null ? source.readAsset(id) : _legacySource!.getAsset(id);
  }

  @override
  String? assetMime(String id) {
    final source = _source;
    return source != null ? source.assetMime(id) : _legacySource!.getAssetMime(id);
  }

  @override
  Future<void> collectUnreferencedAssets({
    Iterable<String> retainedAssetIds = const <String>[],
  }) =>
      _source?.collectUnreferencedAssets(retainedAssetIds: retainedAssetIds) ??
      _legacySource!.collectUnreferencedAssets(
        retainedAssetIds: retainedAssetIds,
      );
}

/// Checkpoint capability adapter backed by the internal Hive checkpoint source.
class HiveCheckpointRepository implements CheckpointRepository {
  factory HiveCheckpointRepository(JournalStore source) =>
      HiveCheckpointRepository._legacy(source);

  HiveCheckpointRepository._legacy(this._legacySource) : _source = null;
  HiveCheckpointRepository.fromDataSource(this._source) : _legacySource = null;

  final HiveCheckpointDataSource? _source;
  final JournalStore? _legacySource;

  @override
  List<CheckpointInfo> checkpointsFor(String documentId) {
    final source = _source;
    if (source != null) return source.checkpointsFor(documentId);
    return _legacySource!
        .checkpointsFor(documentId)
        .map(
          (checkpoint) => CheckpointInfo(
            id: checkpoint.id,
            documentId: checkpoint.entryId,
            createdAt: checkpoint.createdAt,
          ),
        )
        .toList(growable: false);
  }

  @override
  void scheduleCheckpoint(String documentId) {
    final source = _source;
    if (source != null) {
      source.scheduleCheckpoint(documentId);
    } else {
      _legacySource!.scheduleCheckpoint(documentId);
    }
  }

  @override
  Future<void> createCheckpoint(String documentId) =>
      _source?.createCheckpoint(documentId) ??
      _legacySource!.createCheckpoint(documentId);

  @override
  Future<void> restoreCheckpoint(String checkpointId) =>
      _source?.restoreCheckpoint(checkpointId) ??
      _legacySource!.restoreCheckpoint(checkpointId);
}

/// Template capability adapter backed by the internal Hive template source.
class HiveTemplateRepository implements TemplateRepository {
  factory HiveTemplateRepository(JournalStore source) =>
      HiveTemplateRepository._legacy(source);

  HiveTemplateRepository._legacy(this._legacySource) : _source = null;
  HiveTemplateRepository.fromDataSource(this._source) : _legacySource = null;

  final HiveTemplateDataSource? _source;
  final JournalStore? _legacySource;

  @override
  List<JournalTemplate> get templates =>
      _source?.templates ?? _legacySource!.templates;

  @override
  Future<void> saveTemplate(JournalTemplate template) =>
      _source?.saveTemplate(template) ?? _legacySource!.saveTemplate(template);

  @override
  Future<void> deleteTemplate(String id) =>
      _source?.deleteTemplate(id) ?? _legacySource!.deleteTemplate(id);
}

/// Preferences capability adapter backed by the internal Hive meta source.
class HivePreferencesRepository implements PreferencesRepository {
  factory HivePreferencesRepository(JournalStore source) =>
      HivePreferencesRepository._legacy(source);

  HivePreferencesRepository._legacy(this._legacySource) : _source = null;
  HivePreferencesRepository.fromDataSource(this._source) : _legacySource = null;

  final HivePreferencesDataSource? _source;
  final JournalStore? _legacySource;

  @override
  List<int> get recentColorValues =>
      _source?.recentColorValues ?? _legacySource!.recentColorValues;

  @override
  Set<int> get favoriteColorValues =>
      _source?.favoriteColorValues ?? _legacySource!.favoriteColorValues;

  @override
  Future<void> updateColorPreferences({
    List<int>? recent,
    Set<int>? favorites,
  }) =>
      _source?.updateColorPreferences(recent: recent, favorites: favorites) ??
      _legacySource!.updateColorPreferences(
        recent: recent,
        favorites: favorites,
      );
}

/// Archive capability adapter backed by focused internal data sources.
class HiveArchiveRepository implements ArchiveRepository {
  factory HiveArchiveRepository(JournalStore source) =>
      HiveArchiveRepository._legacy(source);

  HiveArchiveRepository._legacy(this._legacySource) : _source = null;
  HiveArchiveRepository.fromDataSource(this._source) : _legacySource = null;

  final HiveArchiveDataSource? _source;
  final JournalStore? _legacySource;

  @override
  JournalArchive? archiveForDocument(String id) {
    final source = _source;
    return source != null
        ? source.archiveForDocument(id)
        : _legacySource!.archiveForEntry(id);
  }

  @override
  Future<EntryDocument> importArchive(JournalArchive archive) =>
      _source?.importArchive(archive) ??
      _legacySource!.importArchive(archive).then(EntryDocumentCodec.fromEntry);
}

/// Persistence capability adapter backed by the raw Hive data source.
class HivePersistenceRepository implements PersistenceRepository {
  factory HivePersistenceRepository(JournalStore source) =>
      HivePersistenceRepository._legacy(source);

  HivePersistenceRepository._legacy(this._legacySource) : _source = null;
  HivePersistenceRepository.fromDataSource(this._source) : _legacySource = null;

  final HiveJournalDataSource? _source;
  final JournalStore? _legacySource;

  @override
  void addFlushHook(Future<void> Function() hook) =>
      _legacySource?.addFlushHook(hook);

  @override
  void removeFlushHook(Future<void> Function() hook) =>
      _legacySource?.removeFlushHook(hook);

  @override
  Future<void> flush() => _source?.flush() ?? _legacySource!.flush();
}

/// Builds a capability bundle from focused Hive data sources.
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
