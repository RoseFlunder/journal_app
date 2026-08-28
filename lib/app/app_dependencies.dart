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
import '../services/persistence_coordinator.dart';
import '../services/repositories.dart';
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
    return AppDependencies._(
      persistence: persistence,
      repositories: wiredRepositories,
      musicCatalog: musicCatalog,
      audioPlaybackFactory: audioPlaybackFactory,
      imageSource: imageSource ?? PlatformImageSource(),
      imageProcessor: imageProcessor,
      archiveTransfer: archiveTransfer,
      editorViewModelFactory: resolvedFactory,
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
    final persistence = PersistenceCoordinator(
      repository: baseRepositories.persistence,
    );
    return AppDependencies._(
      persistence: persistence,
      repositories: baseRepositories.withPersistence(persistence),
      musicCatalog: musicCatalog,
      audioPlaybackFactory: audioPlaybackFactory,
      imageSource: imageSource,
      imageProcessor: imageProcessor,
      archiveTransfer: archiveTransfer,
      editorViewModelFactory: createEditorViewModelFactory(
        repositories: baseRepositories.withPersistence(persistence),
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
  final HiveJournalDataSource? _storage;
  final HiveRepositorySet? _hiveRepositorySet;

  Future<void> init() => repositories.documentRepository.init();

  Future<void> flush() => persistence.flush();

  /// Flushes pending writes and closes every concrete dependency owned by the
  /// composition root. Callers should await this before tearing down Hive.
  Future<void> dispose() async {
    try {
      await flush();
    } finally {
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
      templateRepository: repositories.templateRepository,
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
