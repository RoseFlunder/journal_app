import 'repositories.dart';

/// Coordinates editor flush hooks with repository persistence.
///
/// Editors may have an in-memory text transaction when the application loses
/// focus. The coordinator drains those hooks before asking the repository to
/// flush its data source, keeping lifecycle ordering outside the UI widgets.
class PersistenceCoordinator implements PersistenceRepository {
  PersistenceCoordinator({required this.repository});

  final PersistenceRepository repository;
  final Set<Future<void> Function()> _flushHooks =
      <Future<void> Function()>{};

  @override
  void addFlushHook(Future<void> Function() hook) => _flushHooks.add(hook);

  @override
  void removeFlushHook(Future<void> Function() hook) => _flushHooks.remove(hook);

  @override
  Future<void> flush() async {
    for (final hook in List<Future<void> Function()>.from(_flushHooks)) {
      await hook();
    }
    await repository.flush();
  }

  void dispose() => _flushHooks.clear();
}
