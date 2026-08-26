import '../services/audio_playback.dart';
import '../services/hive_repositories.dart';
import '../services/jamendo_music_catalog.dart';
import '../services/journal_store.dart';
import '../services/persistence_coordinator.dart';
import '../services/repositories.dart';

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
  }) {
    final persistence = PersistenceCoordinator(
      repository: repositories.persistence,
    );
    return AppDependencies._(
      persistence: persistence,
      repositories: repositories.withPersistence(persistence),
      musicCatalog: musicCatalog,
      audioPlaybackFactory: audioPlaybackFactory,
    );
  }

  AppDependencies._({
    required this.persistence,
    required this.repositories,
    required this.musicCatalog,
    required this.audioPlaybackFactory,
    this.storage,
  });

  factory AppDependencies.hive() {
    final source = JournalStore();
    final baseRepositories = HiveRepositorySet(source).repositories;
    final persistence = PersistenceCoordinator(
      repository: baseRepositories.persistence,
    );
    return AppDependencies._(
      persistence: persistence,
      repositories: baseRepositories.withPersistence(persistence),
      musicCatalog: JamendoMusicCatalogRepository(
        clientId: const String.fromEnvironment('JAMENDO_CLIENT_ID'),
      ),
      audioPlaybackFactory: JustAudioPlaybackService.new,
      storage: source,
    );
  }

  final PersistenceCoordinator persistence;
  final JournalRepositories repositories;
  final MusicCatalogRepository musicCatalog;
  final AudioPlaybackFactory audioPlaybackFactory;
  final JournalStore? storage;

  Future<void> init() => repositories.documentRepository.init();

  Future<void> flush() => persistence.flush();

  void dispose() {
    persistence.dispose();
    storage?.dispose();
    final catalog = musicCatalog;
    if (catalog is JamendoMusicCatalogRepository) catalog.dispose();
  }
}

AudioPlaybackService _disabledAudioFactory() =>
    const DisabledAudioPlaybackService();
