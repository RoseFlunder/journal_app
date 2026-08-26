import '../services/journal_store.dart';
import '../services/repositories.dart';

/// Composition root for the application’s long-lived data dependencies.
///
/// Production boot creates this once and passes repository contracts down to
/// the UI. Tests can provide an in-memory or fake [JournalRepository].
class AppDependencies {
  AppDependencies({required this.journalRepository});

  factory AppDependencies.hive() =>
      AppDependencies(journalRepository: HiveJournalRepository(JournalStore()));

  final JournalRepository journalRepository;

  Future<void> init() => journalRepository.init();

  Future<void> flush() => journalRepository.flush();

  void dispose() {
    final repository = journalRepository;
    if (repository is HiveJournalRepository) repository.dispose();
  }
}
