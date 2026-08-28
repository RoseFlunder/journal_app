import 'dart:async';

import 'package:flutter/foundation.dart';

export '../../../../services/cloud_sync_repository.dart'
    show CloudSyncPhase, CloudSyncRepository, CloudSyncState;
import '../../../../services/cloud_sync_repository.dart';

/// Presentation adapter for cloud synchronization. Drive and OAuth details
/// remain inside the service-layer coordinator.
class CloudSyncViewModel extends ChangeNotifier {
  CloudSyncViewModel({required CloudSyncRepository coordinator})
      : _coordinator = coordinator,
        _state = coordinator.state {
    _subscription = coordinator.states.listen((state) {
      _state = state;
      if (hasListeners) notifyListeners();
    });
  }

  final CloudSyncRepository _coordinator;
  late final StreamSubscription<CloudSyncState> _subscription;
  CloudSyncState _state;

  CloudSyncState get state => _state;

  Future<void> connect() => _coordinator.connect();

  Future<void> reconnect() => _coordinator.reauthorize();

  Future<void> syncNow() => _coordinator.syncNow();

  Future<void> signOut() => _coordinator.disconnect();

  Future<void> resetLocalData() => _coordinator.resetLocalData();

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
