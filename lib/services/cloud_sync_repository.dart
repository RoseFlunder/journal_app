import 'cloud_gateway.dart';

/// UI-facing phases for the optional cloud account and synchronization flow.
enum CloudSyncPhase {
  disabled,
  signedOut,
  signingIn,
  initialSync,
  syncing,
  synced,
  offline,
  authorizationRequired,
  failed,
}

/// Immutable state exposed by the synchronization capability.
class CloudSyncState {
  const CloudSyncState({
    required this.phase,
    this.account,
    this.lastSyncedAt,
    this.error,
    this.completed = 0,
    this.total = 0,
  });

  const CloudSyncState.disabled() : this(phase: CloudSyncPhase.disabled);

  const CloudSyncState.signedOut() : this(phase: CloudSyncPhase.signedOut);

  final CloudSyncPhase phase;
  final CloudAccount? account;
  final DateTime? lastSyncedAt;
  final Object? error;
  final int completed;
  final int total;

  CloudSyncState copyWith({
    CloudSyncPhase? phase,
    Object? account = _unset,
    Object? lastSyncedAt = _unset,
    Object? error = _unset,
    int? completed,
    int? total,
  }) =>
      CloudSyncState(
        phase: phase ?? this.phase,
        account: identical(account, _unset) ? this.account : account as CloudAccount?,
        lastSyncedAt: identical(lastSyncedAt, _unset)
            ? this.lastSyncedAt
            : lastSyncedAt as DateTime?,
        error: identical(error, _unset) ? this.error : error,
        completed: completed ?? this.completed,
        total: total ?? this.total,
      );
}

/// Narrow synchronization capability consumed by feature view models.
abstract interface class CloudSyncRepository {
  CloudSyncState get state;

  Stream<CloudSyncState> get states;

  Future<void> connect();

  Future<void> reauthorize();

  Future<void> disconnect();

  Future<void> resetLocalData();

  Future<void> syncNow({bool initial = false});
}

const _unset = Object();
