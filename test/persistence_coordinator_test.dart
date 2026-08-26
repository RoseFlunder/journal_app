import 'package:flutter_test/flutter_test.dart';

import 'package:journal_app/services/persistence_coordinator.dart';
import 'package:journal_app/services/repositories.dart';

void main() {
  test('flushes editor hooks before repository storage', () async {
    final events = <String>[];
    final repository = _FakePersistenceRepository(events);
    final coordinator = PersistenceCoordinator(repository: repository);
    Future<void> hook() async => events.add('hook');
    coordinator.addFlushHook(hook);

    await coordinator.flush();

    expect(events, <String>['hook', 'storage']);
  });

  test('removed hooks are not invoked', () async {
    final events = <String>[];
    final repository = _FakePersistenceRepository(events);
    final coordinator = PersistenceCoordinator(repository: repository);
    Future<void> hook() async => events.add('hook');
    coordinator
      ..addFlushHook(hook)
      ..removeFlushHook(hook);

    await coordinator.flush();

    expect(events, <String>['storage']);
  });
}

class _FakePersistenceRepository implements PersistenceRepository {
  _FakePersistenceRepository(this.events);

  final List<String> events;

  @override
  void addFlushHook(Future<void> Function() hook) {}

  @override
  void removeFlushHook(Future<void> Function() hook) {}

  @override
  Future<void> flush() async => events.add('storage');
}
