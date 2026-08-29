// The private storage handles are intentionally assigned explicitly so the
// public composition API cannot expose mutable Hive state.
// ignore_for_file: prefer_initializing_formals

import '../services/audio_playback.dart';
import '../services/hive_repositories.dart';
import '../services/hive_journal_data_source.dart';
import '../services/image_source.dart';
import '../services/image_processing.dart';
import '../services/jamendo_music_catalog.dart';
import '../services/journal_transfer_service.dart';
import '../services/cloud_gateway.dart';
import '../services/cloud_sync_coordinator.dart';
import '../services/platform_cloud_account_gateway.dart';
import '../services/persistence_coordinator.dart';
import '../services/repositories.dart';
import '../services/sync_local_store.dart';
import '../ui/features/editor/view_models/entry_editor_view_model.dart';
import '../ui/features/editor/use_cases/archive_transfer_use_case.dart';
import '../ui/features/editor/use_cases/image_insertion_use_case.dart';

/// Composition root for the application’s long-lived data dependencies.
///
/// Production boot creates this once and passes repository contracts down to
/// the UI. Tests can provide an in-memory or fake [JournalRepositories].
class AppDependencies {
  factory AppDependencies({
    required JournalRepositories repositories,
    MusicCatalogRepository musicCatalog =
        const DisabledMusicCatalogRepository(),
    AudioPlaybackFactory audioPlaybackFactory = _disabledAudioFactory,
    ImageSourceService? imageSource,
    ImageProcessingService imageProcessor = const ImageProcessor(),
    JournalTransferGateway archiveTransfer = const JournalTransferService(),
    EntryEditorViewModelFactory? editorViewModelFactory,
    SyncLocalStore? syncLocalStore,
    CloudAccountGateway? cloudAccount,
    DriveSyncGateway? drive,
    bool cloudSyncEnabled = false,
  }) {
    final persistence = PersistenceCoordinator(
      repository: repositories.persistence,
    );
    final wiredRepositories = repositories.withPersistence(persistence);
    final resolvedFactory = editorViewModelFactory ??
        createEditorViewModelFactory(
          repositories: wiredRepositories,
          musicCatalog: musicCatalog,
          audioPlaybackFactory: audioPlaybackFactory,
          imageProcessor: imageProcessor,
          archiveTransfer: archiveTransfer,
        );
    final localSync = syncLocalStore ?? MemorySyncLocalStore();
    final accountGateway = cloudAccount ?? DisabledCloudAccountGateway();
    final driveGateway = drive ?? const DisabledDriveSyncGateway();
    final syncCoordinator = CloudSyncCoordinator(
      documents: wiredRepositories.documentRepository,
      local: localSync,
      account: accountGateway,
      drive: driveGateway,
      persistence: wiredRepositories.persistence,
      enabled: cloudSyncEnabled,
    );
    return AppDependencies._(
      persistence: persistence,
      repositories: wiredRepositories,
      musicCatalog: musicCatalog,
      audioPlaybackFactory: audioPlaybackFactory,
      imageSource: imageSource ?? PlatformImageSource(),
      imageProcessor: imageProcessor,
      archiveTransfer: archiveTransfer,
      editorViewModelFactory: resolvedFactory,
      syncLocalStore: localSync,
      cloudAccount: accountGateway,
      drive: driveGateway,
      cloudSync: syncCoordinator,
    );
  }

  AppDependencies._({
    required this.persistence,
    required this.repositories,
    required this.musicCatalog,
    required this.audioPlaybackFactory,
    required this.imageSource,
    required this.imageProcessor,
    required this.archiveTransfer,
    required this.editorViewModelFactory,
    required this.syncLocalStore,
    required this.cloudAccount,
    required this.drive,
    required this.cloudSync,
    HiveJournalDataSource? storage,
    HiveRepositorySet? hiveRepositorySet,
  }) : _storage = storage,
       _hiveRepositorySet = hiveRepositorySet;

  factory AppDependencies.hive() {
    final source = HiveJournalDataSource();
    final repositorySet = HiveRepositorySet.fromDataSource(source);
    final baseRepositories = repositorySet.repositories;
    final musicCatalog = JamendoMusicCatalogRepository(
      clientId: const String.fromEnvironment('JAMENDO_CLIENT_ID'),
    );
    final audioPlaybackFactory = JustAudioPlaybackService.new;
    final imageSource = PlatformImageSource();
    const imageProcessor = ImageProcessor();
    const archiveTransfer = JournalTransferService();
    const cloudEnabled = bool.fromEnvironment(
      'COZY_BLOOM_CLOUD_SYNC',
      defaultValue: false,
    );
    final cloudAccount = cloudEnabled
        ? PlatformCloudAccountGateway(
            config: GoogleCloudConfig.fromEnvironment(),
          )
        : DisabledCloudAccountGateway();
    final drive = cloudEnabled
        ? HttpDriveSyncGateway(accessToken: cloudAccount.accessToken)
        : const DisabledDriveSyncGateway();
    final persistence = PersistenceCoordinator(
      repository: baseRepositories.persistence,
    );
    final wiredRepositories = baseRepositories.withPersistence(persistence);
    final syncLocalStore = repositorySet.syncLocalStore;
    final syncCoordinator = CloudSyncCoordinator(
      documents: wiredRepositories.documentRepository,
      local: syncLocalStore,
      account: cloudAccount,
      drive: drive,
      persistence: wiredRepositories.persistence,
      enabled: cloudEnabled,
    );
    return AppDependencies._(
      persistence: persistence,
      repositories: wiredRepositories,
      musicCatalog: musicCatalog,
      audioPlaybackFactory: audioPlaybackFactory,
      imageSource: imageSource,
      imageProcessor: imageProcessor,
      archiveTransfer: archiveTransfer,
      syncLocalStore: syncLocalStore,
      cloudAccount: cloudAccount,
      drive: drive,
      cloudSync: syncCoordinator,
      editorViewModelFactory: createEditorViewModelFactory(
        repositories: wiredRepositories,
        musicCatalog: musicCatalog,
        audioPlaybackFactory: audioPlaybackFactory,
        imageProcessor: imageProcessor,
        archiveTransfer: archiveTransfer,
      ),
      storage: source,
      hiveRepositorySet: repositorySet,
    );
  }

  final PersistenceCoordinator persistence;
  final JournalRepositories repositories;
  final MusicCatalogRepository musicCatalog;
  final AudioPlaybackFactory audioPlaybackFactory;
  final ImageSourceService imageSource;
  final ImageProcessingService imageProcessor;
  final JournalTransferGateway archiveTransfer;
  final EntryEditorViewModelFactory editorViewModelFactory;
  final SyncLocalStore syncLocalStore;
  final CloudAccountGateway cloudAccount;
  final DriveSyncGateway drive;
  final CloudSyncCoordinator cloudSync;
  final HiveJournalDataSource? _storage;
  final HiveRepositorySet? _hiveRepositorySet;

  Future<void> init() async {
    await repositories.documentRepository.init();
    await cloudSync.init();
  }

  Future<void> flush() => persistence.flush();

  /// Flushes pending writes and closes every concrete dependency owned by the
  /// composition root. Callers should await this before tearing down Hive.
  Future<void> dispose() async {
    try {
      await flush();
    } finally {
      await cloudSync.close();
      persistence.dispose();
      await _hiveRepositorySet?.dispose();
      await _storage?.dispose();
      final catalog = musicCatalog;
      if (catalog is JamendoMusicCatalogRepository) catalog.dispose();
    }
  }
}

AudioPlaybackService _disabledAudioFactory() =>
    const DisabledAudioPlaybackService();

/// Builds the feature editor factory from the complete capability set. Both
/// production dependencies and repository-backed test shells use this single
/// composition policy.
EntryEditorViewModelFactory createEditorViewModelFactory({
  required JournalRepositories repositories,
  required MusicCatalogRepository musicCatalog,
  required AudioPlaybackFactory audioPlaybackFactory,
  required ImageProcessingService imageProcessor,
  required JournalTransferGateway archiveTransfer,
}) =>
    (document) => EntryEditorViewModel(
      document: document,
      documentRepository: repositories.documentRepository,
      checkpointRepository: repositories.checkpointRepository,
      assetRepository: repositories.assetRepository,
      preferenceRepository: repositories.preferenceRepository,
      persistenceRepository: repositories.persistence,
      archiveRepository: repositories.archiveRepository,
      musicCatalog: musicCatalog,
      audioPlaybackFactory: audioPlaybackFactory,
      imageInsertion: ImageInsertionUseCase(
        assets: repositories.assetRepository,
        processor: imageProcessor,
      ),
      archiveTransfer: ArchiveTransferUseCase(
        archives: repositories.archiveRepository,
        transfer: archiveTransfer,
      ),
    );
