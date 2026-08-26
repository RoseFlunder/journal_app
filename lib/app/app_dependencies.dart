import '../services/journal_store.dart';
import '../services/hive_repositories.dart';
import '../services/persistence_coordinator.dart';
import '../services/repositories.dart';

/// Composition root for the application’s long-lived data dependencies.
///
/// Production boot creates this once and passes repository contracts down to
/// the UI. Tests can provide an in-memory or fake [JournalRepository].
class AppDependencies {
  factory AppDependencies({required JournalRepository journalRepository}) {
    final persistence = PersistenceCoordinator(repository: journalRepository);
    return AppDependencies._(
      journalRepository: journalRepository,
      persistence: persistence,
      repositories: JournalRepositories.from(
        journalRepository,
        persistence: persistence,
      ),
    );
  }

  AppDependencies._({
    required this.journalRepository,
    required this.persistence,
    required this.repositories,
  });

  factory AppDependencies.hive() {
    final source = HiveJournalRepository(JournalStore());
    final persistence = PersistenceCoordinator(
      repository: HivePersistenceRepository(source),
    );
    return AppDependencies._(
      journalRepository: source,
      persistence: persistence,
      repositories: HiveRepositorySet(
        source,
        persistence: persistence,
      ).repositories,
    );
  }

  final JournalRepository journalRepository;
  final PersistenceCoordinator persistence;
  final JournalRepositories repositories;

  Future<void> init() => repositories.documentRepository.init();

  Future<void> flush() => persistence.flush();

  void dispose() {
    persistence.dispose();
    final repository = journalRepository;
    if (repository is HiveJournalRepository) repository.dispose();
  }
}
