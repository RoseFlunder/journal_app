import 'dart:typed_data';

import '../models/document.dart';
import '../models/asset_kind.dart';
import '../models/checkpoint.dart';
import '../models/page_music.dart';
import '../models/template.dart';
import 'journal_archive.dart';

// Capability-owned value type; storage record classes remain private to the
// Hive adapters while repositories may still describe asset kind in a method
// contract.
export '../models/asset_kind.dart' show AssetKind;
export '../models/checkpoint.dart' show CheckpointInfo;

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
  List<CheckpointInfo> checkpointsFor(String documentId);

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

/// Search and resolution capability for externally hosted page music.
abstract interface class MusicCatalogRepository {
  bool get isConfigured;

  Future<List<PageMusicTrack>> searchTracks({
    String query = '',
    int offset = 0,
    int limit = 20,
  });

  Future<PageMusicTrack> resolveTrack(String trackId);
}

class DisabledMusicCatalogRepository implements MusicCatalogRepository {
  const DisabledMusicCatalogRepository();

  @override
  bool get isConfigured => false;

  @override
  Future<PageMusicTrack> resolveTrack(String trackId) =>
      Future.error(StateError('The music catalog is not configured.'));

  @override
  Future<List<PageMusicTrack>> searchTracks({
    String query = '',
    int offset = 0,
    int limit = 20,
  }) => Future.error(StateError('The music catalog is not configured.'));
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

/// Narrow repository capabilities passed to feature views and view models.
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

  final DocumentRepository documentRepository;
  final AssetRepository assetRepository;
  final CheckpointRepository checkpointRepository;
  final TemplateRepository templateRepository;
  final PreferencesRepository preferenceRepository;
  final PersistenceRepository persistence;
  final ArchiveRepository archiveRepository;

  /// Returns the same capability set with a lifecycle-aware persistence
  /// coordinator. Composition roots use this to ensure editor flush hooks and
  /// application lifecycle flushes share one owner.
  JournalRepositories withPersistence(PersistenceRepository next) =>
      JournalRepositories(
        documentRepository: documentRepository,
        assetRepository: assetRepository,
        checkpointRepository: checkpointRepository,
        templateRepository: templateRepository,
        preferenceRepository: preferenceRepository,
        persistence: next,
        archiveRepository: archiveRepository,
      );
}
