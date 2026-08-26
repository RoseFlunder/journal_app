import 'dart:async';
import 'dart:typed_data';

import '../models/document.dart';
import '../models/template.dart';
import 'journal_archive.dart';
import 'journal_store.dart';

abstract interface class AssetRepository {
  Future<String> putAsset(
    String ownerId,
    AssetKind kind,
    String mime,
    List<int> bytes,
  );

  Uint8List? readAsset(String id);

  String? assetMime(String id);

  Future<void> collectUnreferencedAssets();
}

abstract interface class CheckpointRepository {
  List<EntryCheckpoint> checkpointsFor(String documentId);

  void scheduleCheckpoint(String documentId);

  Future<void> createCheckpoint(String documentId);

  Future<void> restoreCheckpoint(String checkpointId);
}

abstract interface class TemplateRepository {
  List<JournalTemplate> get templates;

  Future<void> saveTemplate(JournalTemplate template);

  Future<void> deleteTemplate(String id);
}

abstract interface class PreferencesRepository {
  List<int> get recentColorValues;

  Set<int> get favoriteColorValues;

  Future<void> updateColorPreferences({List<int>? recent, Set<int>? favorites});
}

/// Persistence hooks shared by the application lifecycle and active editors.
abstract interface class PersistenceRepository {
  void addFlushHook(Future<void> Function() hook);

  void removeFlushHook(Future<void> Function() hook);

  Future<void> flush();
}

/// Archive capability kept separate from document CRUD because it coordinates
/// documents, assets, and templates as one portable transfer.
abstract interface class ArchiveRepository {
  JournalArchive? archiveForDocument(String id);

  Future<EntryDocument> importArchive(JournalArchive archive);
}

/// Document-only capability used by the journal navigation shell.
abstract interface class DocumentRepository {
  Future<void> init();

  List<EntryDocument> get documents;

  Stream<void> get changes;

  Future<EntryDocument> createDocument({String title});

  Future<void> saveDocument(EntryDocument document);

  void previewDocument(EntryDocument document);

  Future<void> deleteDocument(String id);

}

/// Repository boundary used by the journal and editor views. It composes the
/// aggregate contracts needed by the current editor while the Hive adapter is
/// migrated behind smaller data services.
abstract interface class JournalRepository
    implements
        DocumentRepository,
        AssetRepository,
        CheckpointRepository,
        TemplateRepository,
        PreferencesRepository,
        PersistenceRepository,
        ArchiveRepository {}

/// Narrow repository capabilities passed to feature views and view models.
///
/// The current Hive adapter can still share one implementation internally,
/// but the UI no longer depends on an aggregate CRUD contract.
class JournalRepositories {
  const JournalRepositories({
    required this.documentRepository,
    required this.assetRepository,
    required this.checkpointRepository,
    required this.templateRepository,
    required this.preferenceRepository,
    required this.persistence,
    required this.archiveRepository,
  });

  factory JournalRepositories.from(
    JournalRepository repository, {
    PersistenceRepository? persistence,
  }) =>
      JournalRepositories(
        documentRepository: repository,
        assetRepository: repository,
        checkpointRepository: repository,
        templateRepository: repository,
        preferenceRepository: repository,
        persistence: persistence ?? repository,
        archiveRepository: repository,
      );

  final DocumentRepository documentRepository;
  final AssetRepository assetRepository;
  final CheckpointRepository checkpointRepository;
  final TemplateRepository templateRepository;
  final PreferencesRepository preferenceRepository;
  final PersistenceRepository persistence;
  final ArchiveRepository archiveRepository;

}

/// Hive-backed repository facade. [JournalStore] remains available to the
/// existing navigation shell, while new editor features can depend only on
/// these repository interfaces.
class HiveJournalRepository implements JournalRepository {
  HiveJournalRepository(this.store) {
    store.addListener(_handleStoreChanged);
  }

  final JournalStore store;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  void _handleStoreChanged() {
    if (!_changes.isClosed) _changes.add(null);
  }

  void dispose() {
    store.removeListener(_handleStoreChanged);
    _changes.close();
  }

  @override
  Future<void> init() => store.init();

  @override
  List<EntryDocument> get documents =>
      store.entries.map(EntryDocument.fromEntry).toList(growable: false);

  @override
  Stream<void> get changes => _changes.stream;

  @override
  List<int> get recentColorValues => store.recentColorValues;

  @override
  Set<int> get favoriteColorValues => store.favoriteColorValues;

  @override
  Future<void> updateColorPreferences({
    List<int>? recent,
    Set<int>? favorites,
  }) => store.updateColorPreferences(recent: recent, favorites: favorites);

  @override
  void addFlushHook(Future<void> Function() hook) => store.addFlushHook(hook);

  @override
  void removeFlushHook(Future<void> Function() hook) =>
      store.removeFlushHook(hook);

  @override
  Future<EntryDocument> createDocument({String title = ''}) async =>
      EntryDocument.fromEntry(await store.addEntry(title: title));

  @override
  Future<void> saveDocument(EntryDocument document) =>
      store.updateEntry(document.id, (entry) {
        final next = document.toEntry();
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

  @override
  void previewDocument(EntryDocument document) {
    final next = document.toEntry();
    store.previewEntry(document.id, (entry) {
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
  Future<void> deleteDocument(String id) => store.deleteEntry(id);

  @override
  Future<void> flush() => store.flush();

  @override
  JournalArchive? archiveForDocument(String id) => store.archiveForEntry(id);

  @override
  Future<EntryDocument> importArchive(JournalArchive archive) async =>
      EntryDocument.fromEntry(await store.importArchive(archive));

  @override
  Future<String> putAsset(
    String ownerId,
    AssetKind kind,
    String mime,
    List<int> bytes,
  ) => store.addAsset(ownerId, kind, mime, bytes);

  @override
  Uint8List? readAsset(String id) => store.getAsset(id);

  @override
  String? assetMime(String id) => store.getAssetMime(id);

  @override
  Future<void> collectUnreferencedAssets() => store.collectUnreferencedAssets();

  @override
  List<EntryCheckpoint> checkpointsFor(String documentId) =>
      store.checkpointsFor(documentId);

  @override
  Future<void> createCheckpoint(String documentId) =>
      store.createCheckpoint(documentId);

  @override
  Future<void> restoreCheckpoint(String checkpointId) =>
      store.restoreCheckpoint(checkpointId);

  @override
  void scheduleCheckpoint(String documentId) =>
      store.scheduleCheckpoint(documentId);

  @override
  List<JournalTemplate> get templates => store.templates;

  @override
  Future<void> saveTemplate(JournalTemplate template) =>
      store.saveTemplate(template);

  @override
  Future<void> deleteTemplate(String id) => store.deleteTemplate(id);
}
