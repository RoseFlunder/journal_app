import 'dart:typed_data';

import 'package:hive/hive.dart';
import 'package:journal_app/models/document.dart';
import 'legacy_test_models.dart';
import 'package:journal_app/services/hive_journal_data_source.dart';
import 'package:journal_app/services/hive_repositories.dart';
import 'package:journal_app/services/journal_archive.dart';
import 'package:journal_app/services/persistence_coordinator.dart';
import 'package:journal_app/services/repositories.dart';

/// Test-only Hive environment built from the production capability sources.
///
/// The mutable [Entry] projection is kept here solely for existing fixture
/// ergonomics. The application and all repository wiring use immutable
/// [EntryDocument] values from [repositories].
class TestHiveEnvironment {
  TestHiveEnvironment() {
    final repositorySet = HiveRepositorySet.fromDataSource(_storage);
    _repositorySet = repositorySet;
    _persistence = PersistenceCoordinator(
      repository: repositorySet.repositories.persistence,
    );
    repositories = repositorySet.repositories.withPersistence(_persistence);
  }

  final HiveJournalDataSource _storage = HiveJournalDataSource();
  late final HiveRepositorySet _repositorySet;
  late final PersistenceCoordinator _persistence;
  late final JournalRepositories repositories;
  bool _loaded = false;

  /// Creates a fresh environment after clearing the exact test boxes.
  static Future<TestHiveEnvironment> fresh() async {
    final environment = TestHiveEnvironment();
    await environment._storage.open();
    await Future.wait([
      Hive.box<dynamic>('cozyBloom.documents.v2').clear(),
      Hive.box<dynamic>('cozyBloom.assets.v2').clear(),
      Hive.box<dynamic>('cozyBloom.meta.v2').clear(),
      Hive.box<dynamic>('cozyBloom.checkpoints.v2').clear(),
      Hive.box<dynamic>('cozyBloom.syncHeads.v2').clear(),
      Hive.box<dynamic>('cozyBloom.quarantine.v2').clear(),
    ]);
    await environment._storage.writeSchemaMarker();
    await environment.init();
    return environment;
  }

  Future<void> init() async {
    await repositories.documentRepository.init();
    _loaded = true;
  }

  bool get isLoaded => _loaded;

  List<Entry> get entries => List<Entry>.unmodifiable(
    repositories.documentRepository.documents.map(EntryDocumentCodec.toEntry),
  );

  Stream<void> get changes => repositories.documentRepository.changes;

  int indexOfEntry(String id) => entries.indexWhere((entry) => entry.id == id);

  Future<Entry> addEntry({String title = ''}) async {
    final document = await repositories.documentRepository.createDocument(
      title: title,
    );
    return EntryDocumentCodec.toEntry(document);
  }

  Future<void> updateEntry(String id, void Function(Entry entry) mutate) async {
    final current = _entryById(id);
    if (current == null) return;
    mutate(current);
    await repositories.documentRepository.saveDocument(
      EntryDocumentCodec.fromEntry(current),
    );
  }

  void previewEntry(String id, void Function(Entry entry) mutate) {
    final current = _entryById(id);
    if (current == null) return;
    mutate(current);
    repositories.documentRepository.previewDocument(
      EntryDocumentCodec.fromEntry(current),
    );
  }

  Future<void> deleteEntry(String id) =>
      repositories.documentRepository.deleteDocument(id);

  Future<String> addAsset(
    String ownerId,
    AssetKind kind,
    String mime,
    List<int> bytes,
  ) =>
      repositories.assetRepository.putAsset(kind, mime, bytes).then((asset) => asset.id);

  Uint8List? getAsset(String id) {
    final blob = repositories.assetRepository.readAsset(id);
    return blob == null ? null : Uint8List.fromList(blob.bytes);
  }

  String? getAssetMime(String id) =>
      repositories.assetRepository.readAsset(id)?.descriptor.mime;

  List<CheckpointInfo> checkpointsFor(String documentId) =>
      repositories.checkpointRepository.checkpointsFor(documentId);

  void scheduleCheckpoint(String documentId) =>
      repositories.checkpointRepository.scheduleCheckpoint(documentId);

  Future<void> createCheckpoint(String documentId) =>
      repositories.checkpointRepository.createCheckpoint(documentId);

  Future<void> restoreCheckpoint(String checkpointId) =>
      repositories.checkpointRepository.restoreCheckpoint(checkpointId);

  List<int> get recentColorValues =>
      repositories.preferenceRepository.recentColorValues;

  Set<int> get favoriteColorValues =>
      repositories.preferenceRepository.favoriteColorValues;

  Future<void> updateColorPreferences({
    List<int>? recent,
    Set<int>? favorites,
  }) =>
      repositories.preferenceRepository.updateColorPreferences(
        recent: recent,
        favorites: favorites,
      );

  JournalArchive? archiveForEntry(String id) =>
      repositories.archiveRepository.archiveForDocument(id);

  Future<Entry> importArchive(JournalArchive archive) async {
    final document = await repositories.archiveRepository.importArchive(archive);
    return EntryDocumentCodec.toEntry(document);
  }

  void addFlushHook(Future<void> Function() hook) =>
      repositories.persistence.addFlushHook(hook);

  void removeFlushHook(Future<void> Function() hook) =>
      repositories.persistence.removeFlushHook(hook);

  Future<void> flush() => repositories.persistence.flush();

  Future<void> dispose() async {
    _persistence.dispose();
    await _repositorySet.dispose();
    await _storage.dispose();
  }

  Entry? _entryById(String id) {
    for (final entry in entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }
}
