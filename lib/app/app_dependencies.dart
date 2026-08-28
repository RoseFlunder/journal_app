// The private storage handles are intentionally assigned explicitly so the
// public composition API cannot expose mutable Hive state.
// ignore_for_file: prefer_initializing_formals

import '../services/audio_playback.dart';
import '../services/hive_repositories.dart';
import '../services/hive_journal_data_source.dart';
import '../services/jamendo_music_catalog.dart';
import '../services/persistence_coordinator.dart';
import '../services/repositories.dart';
import '../ui/features/editor/view_models/entry_editor_view_model.dart';

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
    EntryEditorViewModelFactory? editorViewModelFactory,
  }) {
    final resolvedFactory = editorViewModelFactory ??
        _defaultEditorViewModelFactory(
          repositories: repositories,
          musicCatalog: musicCatalog,
          audioPlaybackFactory: audioPlaybackFactory,
        );
    final persistence = PersistenceCoordinator(
      repository: repositories.persistence,
    );
    return AppDependencies._(
      persistence: persistence,
      repositories: repositories.withPersistence(persistence),
      musicCatalog: musicCatalog,
      audioPlaybackFactory: audioPlaybackFactory,
      editorViewModelFactory: resolvedFactory,
    );
  }

  AppDependencies._({
    required this.persistence,
    required this.repositories,
    required this.musicCatalog,
    required this.audioPlaybackFactory,
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
    final persistence = PersistenceCoordinator(
      repository: baseRepositories.persistence,
    );
    return AppDependencies._(
      persistence: persistence,
      repositories: baseRepositories.withPersistence(persistence),
      musicCatalog: musicCatalog,
      audioPlaybackFactory: audioPlaybackFactory,
      editorViewModelFactory: _defaultEditorViewModelFactory(
        repositories: baseRepositories.withPersistence(persistence),
        musicCatalog: musicCatalog,
        audioPlaybackFactory: audioPlaybackFactory,
      ),
      storage: source,
      hiveRepositorySet: repositorySet,
    );
  }

  final PersistenceCoordinator persistence;
  final JournalRepositories repositories;
  final MusicCatalogRepository musicCatalog;
  final AudioPlaybackFactory audioPlaybackFactory;
  final EntryEditorViewModelFactory editorViewModelFactory;
  final HiveJournalDataSource? _storage;
  final HiveRepositorySet? _hiveRepositorySet;

  Future<void> init() => repositories.documentRepository.init();

  Future<void> flush() => persistence.flush();

  void dispose() {
    persistence.dispose();
    _hiveRepositorySet?.dispose();
    _storage?.dispose();
    final catalog = musicCatalog;
    if (catalog is JamendoMusicCatalogRepository) catalog.dispose();
  }
}

AudioPlaybackService _disabledAudioFactory() =>
    const DisabledAudioPlaybackService();

EntryEditorViewModelFactory _defaultEditorViewModelFactory({
  required JournalRepositories repositories,
  required MusicCatalogRepository musicCatalog,
  required AudioPlaybackFactory audioPlaybackFactory,
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
    );
