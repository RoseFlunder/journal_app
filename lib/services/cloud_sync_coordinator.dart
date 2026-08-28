import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/document.dart';
import 'cloud_gateway.dart';
import 'cloud_sync_repository.dart';
import 'repositories.dart';
import 'sync_local_store.dart';
import 'sync_models.dart';

export 'cloud_sync_repository.dart';

/// Coordinates local persistence and Drive snapshots. This class is the only
/// component allowed to merge cloud heads into local repository state.
class CloudSyncCoordinator extends ChangeNotifier
    implements CloudSyncRepository {
  CloudSyncCoordinator({
    required this.documents,
    required this.local,
    required this.account,
    required this.drive,
    required this.persistence,
    bool enabled = true,
  })  : enabled = enabled,
        _state = enabled
           ? const CloudSyncState.signedOut()
           : const CloudSyncState.disabled() {
    _changesSubscription = documents.changes.listen(_onLocalChange);
    _accountSubscription = account.states.listen(_onAuthState);
  }

  static const _documentType = 'document-head';
  static const _collectionType = 'collection-head';
  static const _assetType = 'asset';
  static const _jsonMime = 'application/vnd.cozy-bloom.journal+json';
  static const _uuid = Uuid();

  final DocumentRepository documents;
  final SyncLocalStore local;
  final CloudAccountGateway account;
  final DriveSyncGateway drive;
  final PersistenceRepository persistence;
  final bool enabled;
  late final StreamSubscription<void> _changesSubscription;
  late final StreamSubscription<CloudAuthState> _accountSubscription;
  Timer? _uploadTimer;
  Timer? _pollTimer;
  Timer? _retryTimer;
  int _retryAttempt = 0;
  CloudSyncState _state;
  Future<void>? _activeSync;
  Future<void>? _accountHandling;
  bool _applyingRemote = false;
  bool _initialized = false;

  @override
  CloudSyncState get state => _state;

  @override
  Stream<CloudSyncState> get states async* {
    yield _state;
    yield* _stateStream.stream;
  }

  /// Initializes local sync metadata after the composition root has opened
  /// its storage. Session restoration is deliberately delayed until this
  /// point so secure credentials cannot race Hive initialization.
  Future<void> init() async {
    if (_initialized) return;
    await local.init();
    _initialized = true;
    if (local.lastSyncedAt != null) {
      _setState(_state.copyWith(lastSyncedAt: local.lastSyncedAt));
    }
    if (enabled) await _restoreSession();
  }

  final StreamController<CloudSyncState> _stateStream =
      StreamController<CloudSyncState>.broadcast();

  @override
  Future<void> connect() async {
    if (!enabled) return;
    if (!_initialized) await init();
    _setState(_state.copyWith(phase: CloudSyncPhase.signingIn, error: null));
    try {
      final signedIn = await account.authenticate();
      await _handleAuthenticatedAccount(signedIn);
    } on CloudAuthorizationException catch (error) {
      _setState(_state.copyWith(
        phase: error.code == CloudAuthErrorCode.canceled
            ? CloudSyncPhase.signedOut
            : CloudSyncPhase.authorizationRequired,
        error: error.code == CloudAuthErrorCode.canceled ? null : error,
      ));
    } catch (error) {
      _setState(_state.copyWith(phase: CloudSyncPhase.failed, error: error));
    }
  }

  @override
  Future<void> reauthorize() async {
    if (!enabled) return;
    if (!_initialized) await init();
    try {
      await account.requestDriveAuthorization();
      final current = _state.account;
      if (current != null) await _handleAuthenticatedAccount(current);
    } catch (error) {
      _setState(
        _state.copyWith(
          phase: error is CloudAuthorizationException
              ? CloudSyncPhase.authorizationRequired
              : CloudSyncPhase.failed,
          error: error,
        ),
      );
    }
  }

  @override
  Future<void> disconnect() async {
    _uploadTimer?.cancel();
    _pollTimer?.cancel();
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryAttempt = 0;
    await account.signOut();
    _setState(const CloudSyncState.signedOut());
  }

  @override
  Future<void> resetLocalData() async {
    await persistence.flush();
    await account.signOut();
    await local.clearAllLocalData();
    _retryAttempt = 0;
    _setState(const CloudSyncState.signedOut());
  }

  Future<void> onAppResumed() async {
    if (_state.phase == CloudSyncPhase.synced ||
        _state.phase == CloudSyncPhase.offline ||
        _state.phase == CloudSyncPhase.failed) {
      await syncNow();
    }
  }

  /// Stops foreground polling while the host app is paused or backgrounded.
  /// A subsequent resume performs an immediate pull and reinstates polling
  /// after a successful run.
  void onAppPaused() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  @override
  Future<void> syncNow({bool initial = false}) {
    if (_closeFuture != null || _notifierDisposed) return Future<void>.value();
    final existing = _activeSync;
    if (existing != null) return existing;
    final operation = _sync(initial: initial);
    _activeSync = operation;
    operation.whenComplete(() {
      if (identical(_activeSync, operation)) _activeSync = null;
    });
    return operation;
  }

  bool _notifierDisposed = false;
  Future<void>? _closeFuture;

  /// Completes asynchronous gateway shutdown before the composition root
  /// closes its storage. Calling [dispose] remains safe for widget owners.
  Future<void> close() async {
    final future = _closeFuture ??= _closeResources();
    await future;
    if (!_notifierDisposed) {
      _notifierDisposed = true;
      super.dispose();
    }
  }

  @override
  void dispose() {
    if (_notifierDisposed) return;
    _notifierDisposed = true;
    super.dispose();
    _closeFuture ??= _closeResources();
  }

  Future<void> _closeResources() async {
    _uploadTimer?.cancel();
    _pollTimer?.cancel();
    _retryTimer?.cancel();
    _retryTimer = null;
    final active = _activeSync;
    if (active != null) await active;
    // A successful run can install polling while the close was waiting for
    // it; cancel once more after the run has settled.
    _uploadTimer?.cancel();
    _pollTimer?.cancel();
    _retryTimer?.cancel();
    _retryTimer = null;
    await _changesSubscription.cancel();
    await _accountSubscription.cancel();
    await _stateStream.close();
    await account.dispose();
    await drive.dispose();
  }

  Future<void> _restoreSession() async {
    try {
      final restored = await account.restoreSession();
      if (restored == null) return;
      await _handleAuthenticatedAccount(restored);
    } catch (error) {
      _setState(_state.copyWith(phase: CloudSyncPhase.failed, error: error));
    }
  }

  Future<void> _acceptAccount(CloudAccount next) async {
    final bound = local.boundAccountId;
    if (bound != null && bound != next.id) {
      await account.signOut();
      throw const CloudAccountMismatchException();
    }
    if (bound == null) await local.bindAccount(next.id);
    _setState(
      CloudSyncState(
        phase: _state.phase,
        account: next,
        lastSyncedAt: _state.lastSyncedAt,
      ),
    );
  }

  Future<void> _sync({required bool initial}) async {
    if (!enabled || _state.account == null) return;
    if (!_initialized) await init();
    _setState(
      _state.copyWith(
        phase: initial ? CloudSyncPhase.initialSync : CloudSyncPhase.syncing,
        error: null,
      ),
    );
    try {
      await persistence.flush();
      await _captureLocalChanges();
      final remote = await drive.listRecords();
      final remoteHeads = await _readRemoteHeads(remote);
      await _downloadMissingAssets(remote, remoteHeads);
      await _mergeDocuments(remoteHeads);
      await _mergeCollection();
      await _pushLocalHeads(remote);
      final syncedAt = DateTime.now().toUtc();
      await local.setLastSyncedAt(syncedAt);
      _setState(
        _state.copyWith(
          phase: CloudSyncPhase.synced,
          lastSyncedAt: syncedAt,
          completed: 0,
          total: 0,
        ),
      );
      _retryAttempt = 0;
      _retryTimer?.cancel();
      _retryTimer = null;
      _ensurePolling();
    } on CloudAuthorizationException catch (error) {
      _setState(
        _state.copyWith(
          phase: CloudSyncPhase.authorizationRequired,
          error: error,
        ),
      );
    } on CloudHttpException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        _setState(
          _state.copyWith(
            phase: CloudSyncPhase.authorizationRequired,
            error: error,
          ),
        );
      } else {
        _setOffline(error, retry: _isTransientStatus(error.statusCode));
      }
    } on http.ClientException catch (error) {
      _setOffline(error, retry: true);
    } on TimeoutException catch (error) {
      _setOffline(error, retry: true);
    } catch (error) {
      _setState(_state.copyWith(phase: CloudSyncPhase.failed, error: error));
    }
  }

  Future<void> _captureLocalChanges() async {
    final current = <String, EntryDocument>{
      for (final document in documents.documents) document.id: document,
    };
    var counter = _maxLocalCounter();
    final knownIds = <String>{...local.documentHeads.map((head) => head.documentId)};
    for (final document in current.values) {
      final existing = local.documentHead(document.id);
      if (existing != null && _sameDocument(existing.document, document)) {
        knownIds.remove(document.id);
        continue;
      }
      counter++;
      final vector = (existing?.vector ?? SyncVersionVector())
          .increment(local.deviceId);
      await local.saveDocumentHead(
        SyncedDocumentHead(
          documentId: document.id,
          deviceId: local.deviceId,
          vector: vector,
          stamp: SyncMutationStamp(
            modifiedAt: document.modifiedAt.toUtc(),
            deviceId: local.deviceId,
            counter: counter,
          ),
          document: document,
          deletedAt: null,
          assets: _assetDescriptors(document),
          driveFileId: existing?.driveFileId,
        ),
      );
      knownIds.remove(document.id);
    }
    for (final id in knownIds) {
      final existing = local.documentHead(id);
      if (existing == null || existing.isDeleted) continue;
      counter++;
      await local.saveDocumentHead(
        SyncedDocumentHead(
          documentId: id,
          deviceId: local.deviceId,
          vector: existing.vector.increment(local.deviceId),
          stamp: SyncMutationStamp(
            modifiedAt: DateTime.now().toUtc(),
            deviceId: local.deviceId,
            counter: counter,
          ),
          document: null,
          deletedAt: DateTime.now().toUtc(),
          assets: existing.assets,
          driveFileId: existing.driveFileId,
        ),
      );
    }
    final existingCollection = local.collectionHead;
    final ids = current.keys.toList(growable: false);
    if (existingCollection == null || !_sameIds(existingCollection.documentIds, ids)) {
      counter++;
      await local.saveCollectionHead(
        SyncedCollectionHead(
          deviceId: local.deviceId,
          vector: (existingCollection?.vector ?? SyncVersionVector())
              .increment(local.deviceId),
          stamp: SyncMutationStamp(
            modifiedAt: DateTime.now().toUtc(),
            deviceId: local.deviceId,
            counter: counter,
          ),
          documentIds: ids,
          driveFileId: existingCollection?.driveFileId,
        ),
      );
    }
  }

  Future<Map<String, List<SyncedDocumentHead>>> _readRemoteHeads(
    List<DriveSyncRecord> records,
  ) async {
    final grouped = <String, List<SyncedDocumentHead>>{};
    _remoteCollections = <SyncedCollectionHead>[];
    for (final record in records) {
      if (record.properties['type'] != _documentType &&
          record.properties['type'] != _collectionType) {
        continue;
      }
      try {
        final bytes = await drive.downloadRecord(record.fileId);
        final raw = jsonDecode(utf8.decode(bytes));
        if (raw is! Map) continue;
        final json = Map<String, dynamic>.from(raw);
        if (record.properties['type'] == _collectionType) {
          _remoteCollections!.add(
            SyncedCollectionHead.fromJson(json).copyWith(
              driveFileId: record.fileId,
            ),
          );
          continue;
        }
        final head = SyncedDocumentHead.fromJson(json);
        grouped.putIfAbsent(head.documentId, () => <SyncedDocumentHead>[]).add(
              head.copyWith(driveFileId: record.fileId),
            );
      } catch (_) {}
    }
    return grouped;
  }

  List<SyncedCollectionHead>? _remoteCollections;

  Future<void> _downloadMissingAssets(
    List<DriveSyncRecord> records,
    Map<String, List<SyncedDocumentHead>> heads,
  ) async {
    final needed = <String, SyncedAssetDescriptor>{};
    for (final versions in heads.values) {
      for (final head in versions) {
        for (final asset in head.assets) {
          needed[asset.id] = asset;
        }
      }
    }
    final assetsByHash = <String, DriveSyncRecord>{
      for (final record in records)
        if (record.properties['type'] == _assetType &&
            record.properties['sha256'] != null)
          record.properties['sha256']!: record,
    };
    for (final descriptor in needed.values) {
      if (local.asset(descriptor.id) != null) continue;
      final record = assetsByHash[descriptor.sha256];
      if (record == null) continue;
      try {
        final bytes = await drive.downloadRecord(record.fileId);
        // The Drive metadata is not trusted until the downloaded bytes match
        // the content hash embedded in the immutable page head.
        if (descriptor.sha256.isEmpty ||
            sha256.convert(bytes).toString() != descriptor.sha256) {
          continue;
        }
        await local.putAssetExact(
          LocalAssetSnapshot(
            id: descriptor.id,
            ownerId: descriptor.ownerId,
            kind: descriptor.kind,
            mime: descriptor.mime,
            bytes: bytes,
          ),
        );
      } catch (_) {
        // A single malformed or unavailable asset must not prevent other
        // pages from synchronizing. Its page head remains pending below.
      }
    }
  }

  Future<void> _mergeDocuments(
    Map<String, List<SyncedDocumentHead>> remoteHeads,
  ) async {
    _applyingRemote = true;
    try {
      for (final entry in remoteHeads.entries) {
        final localHead = local.documentHead(entry.key);
        final availableRemoteHeads = entry.value
            .where(_assetsAvailable)
            .toList(growable: false);
        final candidates = <SyncedDocumentHead>[
          ...availableRemoteHeads,
          ..._optionalHead(localHead),
        ];
        final winner = _chooseWinner(candidates);
        if (winner == null) continue;
        final winnerRelation = localHead == null
            ? null
            : winner.vector.relationTo(localHead.vector);
        final localWon = identical(winner, localHead);
        final shouldApply = localHead == null ||
            winnerRelation == SyncRelation.after ||
            (winnerRelation == SyncRelation.concurrent && !localWon);
        if (shouldApply) {
          if (winner.isDeleted) {
            await local.deleteDocumentExact(entry.key);
          } else if (winner.document != null) {
            await local.upsertDocumentExact(winner.document!);
          }
          await local.saveDocumentHead(winner);
        }
        final concurrentLosers = candidates
            .where(
              (head) =>
                  !identical(head, winner) &&
                  head.vector.relationTo(winner.vector) ==
                      SyncRelation.concurrent,
            )
            .toList(growable: false);
        for (final loser in concurrentLosers) {
          if (loser.document != null) {
            await _createConflictCopy(loser.document!, loser.stamp.deviceId);
          }
        }
        if (concurrentLosers.isNotEmpty) {
          // Collapse concurrent branches into a local head so the same
          // conflict copies are not generated again during the next poll.
          final now = DateTime.now().toUtc();
          final resolvedVector = candidates
              .fold<SyncVersionVector>(
                SyncVersionVector(),
                (merged, head) => merged.merge(head.vector),
              )
              .increment(local.deviceId);
          await local.saveDocumentHead(
            SyncedDocumentHead(
              documentId: entry.key,
              deviceId: local.deviceId,
              vector: resolvedVector,
              stamp: SyncMutationStamp(
                modifiedAt: now,
                deviceId: local.deviceId,
                counter: _maxLocalCounter() + 1,
              ),
              document: winner.isDeleted ? null : winner.document,
              deletedAt: winner.deletedAt,
              assets: winner.assets,
            ),
          );
        }
      }
    } finally {
      _applyingRemote = false;
    }
  }

  Future<void> _mergeCollection() async {
    // Collection records are read in a separate pass because they do not
    // belong to the document-head map.
    final wasApplyingRemote = _applyingRemote;
    _applyingRemote = true;
    try {
      final localCollection = local.collectionHead;
      final candidates = <SyncedCollectionHead>[
        ..._optionalCollection(localCollection),
        ...?_remoteCollections,
      ];
      if (candidates.isEmpty) return;
      final winner = _chooseCollectionWinner(candidates);
      final currentIds = documents.documents.map((document) => document.id);
      final mergedIds = <String>[
        ...winner.documentIds,
        ...currentIds.where((id) => !winner.documentIds.contains(id)),
      ];
      final relation = localCollection?.vector.relationTo(winner.vector);
      final localNeedsPublish = localCollection != null &&
          (relation == SyncRelation.concurrent ||
              !_sameIdSet(winner.documentIds, currentIds));
      if (!_sameIds(winner.documentIds, mergedIds) ||
          relation != SyncRelation.equal) {
        if (!_sameIds(
          documents.documents.map((document) => document.id),
          mergedIds,
        )) {
          final byId = <String, EntryDocument>{
            for (final document in documents.documents) document.id: document,
          };
          // Exact ordering is a storage concern; the source rebuilds order from
          // the current document list. Reordering is therefore persisted by the
          // repository only when a new order differs from the current list.
          final ordered = <EntryDocument>[
            for (final id in mergedIds)
              if (byId[id] != null) byId[id]!,
          ];
          if (ordered.length == byId.length) {
            await local.reorderDocumentsExact(ordered);
          }
        }
        if (localNeedsPublish) {
          final now = DateTime.now().toUtc();
          await local.saveCollectionHead(
            SyncedCollectionHead(
              deviceId: local.deviceId,
              vector: winner.vector
                  .merge(localCollection.vector)
                  .increment(local.deviceId),
              stamp: SyncMutationStamp(
                modifiedAt: now,
                deviceId: local.deviceId,
                counter: _maxLocalCounter() + 1,
              ),
              documentIds: mergedIds,
            ),
          );
        } else {
          await local.saveCollectionHead(
            winner.copyWith(documentIds: mergedIds),
          );
        }
      }
    } finally {
      _applyingRemote = wasApplyingRemote;
    }
  }

  Future<void> _pushLocalHeads(
    List<DriveSyncRecord> records,
  ) async {
    final existingByKey = <String, DriveSyncRecord>{
      for (final record in records)
        if (record.properties['type'] == _documentType &&
            record.properties['deviceId'] != null &&
            record.properties['documentId'] != null)
          '${record.properties['documentId']}:${record.properties['deviceId']}': record,
    };
    for (final head in local.documentHeads) {
      if (head.deviceId != local.deviceId) continue;
      // Publish immutable assets first. A remote device never observes a
      // document head that references an asset which has not been uploaded.
      await _pushAssets(head);
      final payload = utf8.encode(jsonEncode(head.toJson()));
      final key = '${head.documentId}:${head.deviceId}';
      final old = existingByKey[key];
      final record = old == null
          ? await drive.createRecord(
              name: 'document-${head.documentId}-${head.deviceId}.json',
              mimeType: _jsonMime,
              properties: <String, String>{
                'type': _documentType,
                'documentId': head.documentId,
                'deviceId': head.deviceId,
              },
              bytes: payload,
            )
          : await drive.updateRecord(
              fileId: old.fileId,
              mimeType: _jsonMime,
              bytes: payload,
            );
      if (record.fileId != head.driveFileId) {
        await local.saveDocumentHead(head.copyWith(driveFileId: record.fileId));
      }
    }
    final collection = local.collectionHead;
    if (collection != null && collection.deviceId == local.deviceId) {
      final payload = utf8.encode(jsonEncode(collection.toJson()));
      final old = _firstWhereOrNull(
        records,
        (record) =>
            record.properties['type'] == _collectionType &&
            record.properties['deviceId'] == collection.deviceId,
      );
      final record = old == null
          ? await drive.createRecord(
              name: 'collection-${local.deviceId}.json',
              mimeType: _jsonMime,
              properties: <String, String>{
                'type': _collectionType,
                'deviceId': collection.deviceId,
              },
              bytes: payload,
            )
          : await drive.updateRecord(
              fileId: old.fileId,
              mimeType: _jsonMime,
              bytes: payload,
            );
      if (record.fileId != collection.driveFileId) {
        await local.saveCollectionHead(
          SyncedCollectionHead(
            deviceId: collection.deviceId,
            vector: collection.vector,
            stamp: collection.stamp,
            documentIds: collection.documentIds,
            driveFileId: record.fileId,
          ),
        );
      }
    }
  }

  Future<void> _pushAssets(SyncedDocumentHead head) async {
    final records = await drive.listRecords();
    for (final descriptor in head.assets) {
      final asset = local.asset(descriptor.id);
      if (asset == null) continue;
      final existing = _firstWhereOrNull(
        records,
        (record) =>
            record.properties['type'] == _assetType &&
            record.properties['sha256'] == descriptor.sha256,
      );
      if (existing != null) continue;
      await drive.createRecord(
        name: 'asset-${descriptor.sha256}.${_extension(descriptor.mime)}',
        mimeType: descriptor.mime,
        properties: <String, String>{
          'type': _assetType,
          'sha256': descriptor.sha256,
          'assetId': descriptor.id,
        },
        bytes: asset.bytes,
      );
    }
  }

  Future<void> _createConflictCopy(EntryDocument document, String deviceId) async {
    final now = DateTime.now().toUtc();
    final suffix = now.toIso8601String().split('.').first;
    final copy = document.copyWith(
      title: '${document.title} (conflict from $deviceId, $suffix)',
    );
    final conflict = EntryDocument(
      id: _uuid.v4(),
      title: copy.title,
      createdAt: document.createdAt,
      modifiedAt: now,
      nodes: copy.nodes,
      board: copy.board,
      view: copy.view,
      music: copy.music,
      titleFontSize: copy.titleFontSize,
      titleFontFamily: copy.titleFontFamily,
      titleTextColorValue: copy.titleTextColorValue,
      titleBold: copy.titleBold,
      titleItalic: copy.titleItalic,
      schemaVersion: copy.schemaVersion,
    );
    await local.upsertDocumentExact(conflict);
    await local.saveDocumentHead(
      SyncedDocumentHead(
        documentId: conflict.id,
        deviceId: local.deviceId,
        vector: SyncVersionVector().increment(local.deviceId),
        stamp: SyncMutationStamp(
          modifiedAt: conflict.modifiedAt,
          deviceId: local.deviceId,
          counter: _maxLocalCounter() + 1,
        ),
        document: conflict,
        deletedAt: null,
        assets: _assetDescriptors(conflict),
      ),
    );
  }

  SyncedDocumentHead? _chooseWinner(List<SyncedDocumentHead> candidates) {
    if (candidates.isEmpty) return null;
    var winner = candidates.first;
    for (final candidate in candidates.skip(1)) {
      final relation = candidate.vector.relationTo(winner.vector);
      if (relation == SyncRelation.after ||
          (relation == SyncRelation.concurrent &&
              candidate.stamp.compareTo(winner.stamp) > 0)) {
        winner = candidate;
      }
    }
    return winner;
  }

  SyncedCollectionHead _chooseCollectionWinner(
    List<SyncedCollectionHead> candidates,
  ) {
    var winner = candidates.first;
    for (final candidate in candidates.skip(1)) {
      final relation = candidate.vector.relationTo(winner.vector);
      if (relation == SyncRelation.after ||
          (relation == SyncRelation.concurrent &&
              candidate.stamp.compareTo(winner.stamp) > 0)) {
        winner = candidate;
      }
    }
    return winner;
  }

  List<SyncedAssetDescriptor> _assetDescriptors(EntryDocument document) {
    final ids = <String>{};
    void visit(Iterable<CanvasNode> nodes) {
      for (final node in nodes) {
        if (node.assetId != null) ids.add(node.assetId!);
        visit(node.children);
      }
    }
    visit(document.nodes);
    return List<SyncedAssetDescriptor>.unmodifiable(
      ids.map((id) {
        final asset = local.asset(id);
        return SyncedAssetDescriptor(
          id: id,
          ownerId: asset?.ownerId ?? document.id,
          kind: asset?.kind ?? AssetKind.image,
          mime: asset?.mime ?? 'application/octet-stream',
          sha256: asset == null ? '' : sha256.convert(asset.bytes).toString(),
        );
      }),
    );
  }

  int _maxLocalCounter() => local.documentHeads
      .expand((head) => head.vector.values.values)
      .fold<int>(0, math.max);

  bool _assetsAvailable(SyncedDocumentHead head) => head.assets.every(
        (descriptor) => local.asset(descriptor.id) != null,
      );

  void _onLocalChange(void _) {
    if (_closeFuture != null || _notifierDisposed || _applyingRemote || _state.account == null) {
      return;
    }
    _uploadTimer?.cancel();
    _uploadTimer = Timer(const Duration(seconds: 2), () {
      unawaited(syncNow());
    });
  }

  void _onAuthState(CloudAuthState next) {
    if (_closeFuture != null || _notifierDisposed) return;
    if (next.phase == CloudAuthPhase.signedIn && next.account != null) {
      unawaited(_handleAuthenticatedAccount(next.account!));
    } else if (next.phase == CloudAuthPhase.authorizationRequired) {
      _setState(
        _state.copyWith(
          phase: CloudSyncPhase.authorizationRequired,
          error: next.error,
        ),
      );
    } else if (next.phase == CloudAuthPhase.signedOut) {
      _setState(const CloudSyncState.signedOut());
    } else if (next.phase == CloudAuthPhase.failed) {
      _setState(
        _state.copyWith(phase: CloudSyncPhase.failed, error: next.error),
      );
    }
  }

  Future<void> _handleAuthenticatedAccount(CloudAccount accountInfo) async {
    final active = _accountHandling;
    if (active != null) return active;
    final operation = _processAuthenticatedAccount(accountInfo);
    _accountHandling = operation;
    try {
      await operation;
    } finally {
      if (identical(_accountHandling, operation)) _accountHandling = null;
    }
  }

  Future<void> _processAuthenticatedAccount(CloudAccount accountInfo) async {
    try {
      await _acceptAccount(accountInfo);
      if (!await account.hasDriveAuthorization()) {
        _setState(_state.copyWith(
          phase: CloudSyncPhase.authorizationRequired,
          error: null,
        ));
        return;
      }
      await syncNow(initial: true);
    } on CloudAccountMismatchException catch (error) {
      _setState(_state.copyWith(phase: CloudSyncPhase.failed, error: error));
    } on CloudAuthorizationException catch (error) {
      _setState(
        _state.copyWith(
          phase: CloudSyncPhase.authorizationRequired,
          error: error,
        ),
      );
    } catch (error) {
      _setState(_state.copyWith(phase: CloudSyncPhase.failed, error: error));
    }
  }

  void _ensurePolling() {
    _pollTimer ??= Timer.periodic(const Duration(seconds: 60), (_) {
      unawaited(syncNow());
    });
  }

  void _setOffline(Object error, {required bool retry}) {
    _setState(_state.copyWith(phase: CloudSyncPhase.offline, error: error));
    if (!retry || _retryTimer != null) return;
    final seconds = math.min(30, 1 << math.min(_retryAttempt, 4));
    _retryAttempt++;
    _retryTimer = Timer(Duration(seconds: seconds), () {
      _retryTimer = null;
      unawaited(syncNow());
    });
  }

  void _setState(CloudSyncState next) {
    _state = next;
    if (!_stateStream.isClosed) _stateStream.add(next);
    if (hasListeners) notifyListeners();
  }
}

bool _isTransientStatus(int statusCode) =>
    statusCode == 408 || statusCode == 429 || statusCode >= 500;

class CloudAccountMismatchException implements Exception {
  const CloudAccountMismatchException();

  @override
  String toString() =>
      'This journal is linked to a different Google account. Reset local data before switching accounts.';
}

String _extension(String mime) => switch (mime) {
      'image/png' => 'png',
      'image/jpeg' => 'jpg',
      'image/webp' => 'webp',
      _ => 'bin',
    };

bool _sameDocument(EntryDocument? left, EntryDocument right) {
  if (left == null) return false;
  // Revisions count local storage writes and deliberately do not participate
  // in cloud content identity.
  return jsonEncode(left.copyWith(revision: 0).toJson()) ==
      jsonEncode(right.copyWith(revision: 0).toJson());
}

bool _sameIds(Iterable<String> left, Iterable<String> right) {
  final leftList = left.toList(growable: false);
  final rightList = right.toList(growable: false);
  if (leftList.length != rightList.length) return false;
  for (var index = 0; index < leftList.length; index++) {
    if (leftList[index] != rightList[index]) return false;
  }
  return true;
}

bool _sameIdSet(Iterable<String> left, Iterable<String> right) {
  final leftSet = left.toSet();
  final rightSet = right.toSet();
  return leftSet.length == rightSet.length && leftSet.containsAll(rightSet);
}

T? _firstWhereOrNull<T>(Iterable<T> values, bool Function(T value) test) {
  for (final value in values) {
    if (test(value)) return value;
  }
  return null;
}

Iterable<SyncedDocumentHead> _optionalHead(SyncedDocumentHead? head) sync* {
  if (head != null) yield head;
}

Iterable<SyncedCollectionHead> _optionalCollection(
  SyncedCollectionHead? head,
) sync* {
  if (head != null) yield head;
}
