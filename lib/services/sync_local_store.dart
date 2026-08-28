import 'package:uuid/uuid.dart';

import '../models/asset_kind.dart';
import '../models/document.dart';
import 'hive_capability_sources.dart';
import 'hive_journal_data_source.dart';
import 'sync_models.dart';

/// Immutable asset bytes plus the metadata required by the Drive adapter.
class LocalAssetSnapshot {
  LocalAssetSnapshot({
    required this.id,
    required this.ownerId,
    required this.kind,
    required this.mime,
    required List<int> bytes,
  }) : bytes = List<int>.unmodifiable(bytes);

  final String id;
  final String ownerId;
  final AssetKind kind;
  final String mime;
  final List<int> bytes;
}

/// Internal storage contract used only by the synchronization coordinator.
/// Feature code continues to depend on the narrow document and asset
/// repositories and cannot perform exact remote upserts.
abstract interface class SyncLocalStore {
  Future<void> init();

  String get deviceId;

  String? get boundAccountId;

  DateTime? get lastSyncedAt;

  Future<void> setLastSyncedAt(DateTime? value);

  List<SyncedDocumentHead> get documentHeads;

  SyncedDocumentHead? documentHead(String id);

  SyncedCollectionHead? get collectionHead;

  Future<void> saveDocumentHead(SyncedDocumentHead head);

  Future<void> saveCollectionHead(SyncedCollectionHead head);

  Future<void> bindAccount(String accountId);

  Future<void> clearAccountBinding();

  Future<void> upsertDocumentExact(EntryDocument document);

  Future<void> deleteDocumentExact(String id);

  Future<void> reorderDocumentsExact(Iterable<EntryDocument> ordered);

  LocalAssetSnapshot? asset(String id);

  Future<void> putAssetExact(LocalAssetSnapshot asset);

  Future<void> clearAllLocalData();
}

/// Hive implementation of [SyncLocalStore]. Sync records live in the existing
/// meta box; the raw storage source remains below the repository boundary.
class HiveSyncLocalStore implements SyncLocalStore {
  HiveSyncLocalStore({
    required this.storage,
    required this.documents,
    required this.assets,
  });

  static const _headsKey = 'sync.documentHeads';
  static const _collectionKey = 'sync.collectionHead';
  static const _deviceIdKey = 'sync.deviceId';
  static const _accountIdKey = 'sync.accountId';
  static const _lastSyncedAtKey = 'sync.lastSyncedAt';
  static const _uuid = Uuid();

  final HiveJournalDataSource storage;
  final HiveDocumentDataSource documents;
  final HiveAssetDataSource assets;
  final Map<String, SyncedDocumentHead> _heads = <String, SyncedDocumentHead>{};
  SyncedCollectionHead? _collection;
  String? _device;
  String? _account;
  DateTime? _lastSynced;

  @override
  Future<void> init() async {
    await storage.open();
    _device = storage.readMeta(_deviceIdKey) as String?;
    if (_device == null || _device!.isEmpty) {
      _device = _uuid.v4();
      await storage.enqueue(() => storage.writeMeta(_deviceIdKey, _device));
    }
    _account = storage.readMeta(_accountIdKey) as String?;
    _lastSynced = DateTime.tryParse(
      storage.readMeta(_lastSyncedAtKey) as String? ?? '',
    );
    _heads
      ..clear()
      ..addAll(_readHeads());
    final rawCollection = storage.readMeta(_collectionKey);
    if (rawCollection is Map) {
      try {
        _collection = SyncedCollectionHead.fromJson(
          Map<String, dynamic>.from(rawCollection),
        );
      } catch (_) {
        _collection = null;
      }
    }
  }

  @override
  String get deviceId => _device ?? (throw StateError('Sync store not initialized'));

  @override
  String? get boundAccountId => _account;

  @override
  DateTime? get lastSyncedAt => _lastSynced;

  @override
  Future<void> setLastSyncedAt(DateTime? value) async {
    _lastSynced = value?.toUtc();
    await storage.enqueue(
      () => storage.writeMeta(_lastSyncedAtKey, _lastSynced?.toIso8601String()),
    );
  }

  @override
  List<SyncedDocumentHead> get documentHeads =>
      List<SyncedDocumentHead>.unmodifiable(_heads.values);

  @override
  SyncedDocumentHead? documentHead(String id) => _heads[id];

  @override
  SyncedCollectionHead? get collectionHead => _collection;

  @override
  Future<void> saveDocumentHead(SyncedDocumentHead head) async {
    _heads[head.documentId] = head;
    await _persistHeads();
  }

  @override
  Future<void> saveCollectionHead(SyncedCollectionHead head) async {
    _collection = head;
    await storage.enqueue(() => storage.writeMeta(_collectionKey, head.toJson()));
  }

  @override
  Future<void> bindAccount(String accountId) async {
    _account = accountId;
    await storage.enqueue(() => storage.writeMeta(_accountIdKey, accountId));
  }

  @override
  Future<void> clearAccountBinding() async {
    _account = null;
    await storage.enqueue(() => storage.writeMeta(_accountIdKey, null));
  }

  @override
  Future<void> upsertDocumentExact(EntryDocument document) {
    // Revision is a local persistence counter, not a cloud clock. Preserve
    // the receiving device's value while importing the immutable snapshot.
    final localRevision = documents.documentById(document.id)?.revision ?? 0;
    return documents.upsertExact(document.copyWith(revision: localRevision));
  }

  @override
  Future<void> deleteDocumentExact(String id) => documents.deleteExact(id);

  @override
  Future<void> reorderDocumentsExact(Iterable<EntryDocument> ordered) =>
      documents.reorderExact(ordered);

  @override
  LocalAssetSnapshot? asset(String id) {
    final record = assets.snapshot(id);
    if (record == null) return null;
    return LocalAssetSnapshot(
      id: id,
      ownerId: record.entryId,
      kind: record.kind,
      mime: record.mime,
      bytes: record.data,
    );
  }

  @override
  Future<void> putAssetExact(LocalAssetSnapshot asset) => assets.putExact(
        asset.id,
        asset.ownerId,
        asset.kind,
        asset.mime,
        asset.bytes,
      );

  @override
  Future<void> clearAllLocalData() async {
    _heads.clear();
    _collection = null;
    await documents.clearAll();
    await assets.clearAll();
    await storage.enqueue(() async {
      await storage.writeMeta(_headsKey, <String, dynamic>{});
      await storage.writeMeta(_collectionKey, null);
      await storage.writeMeta(_accountIdKey, null);
      await storage.writeMeta(_lastSyncedAtKey, null);
    });
    _account = null;
    _lastSynced = null;
  }

  Map<String, SyncedDocumentHead> _readHeads() {
    final raw = storage.readMeta(_headsKey);
    if (raw is! Map) return <String, SyncedDocumentHead>{};
    final result = <String, SyncedDocumentHead>{};
    for (final entry in raw.entries) {
      if (entry.key is! String || entry.value is! Map) continue;
      try {
        result[entry.key as String] = SyncedDocumentHead.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        );
      } catch (_) {}
    }
    return result;
  }

  Future<void> _persistHeads() => storage.enqueue(
        () => storage.writeMeta(
          _headsKey,
          <String, dynamic>{
            for (final entry in _heads.entries) entry.key: entry.value.toJson(),
          },
        ),
      );
}

/// Small in-memory store used by repository-backed widget tests and by the
/// disabled cloud-sync composition path.
class MemorySyncLocalStore implements SyncLocalStore {
  MemorySyncLocalStore({String? deviceId}) : _device = deviceId ?? _uuid.v4();

  static const _uuid = Uuid();
  final String _device;
  final Map<String, SyncedDocumentHead> _heads = <String, SyncedDocumentHead>{};
  SyncedCollectionHead? _collection;
  String? _account;
  DateTime? _lastSynced;
  final Map<String, LocalAssetSnapshot> _assets = <String, LocalAssetSnapshot>{};
  final List<EntryDocument> _documents = <EntryDocument>[];

  /// Exact-document projection is exposed only for in-memory test shells.
  /// Production callers use [SyncLocalStore] and the document repository.
  List<EntryDocument> get exactDocuments =>
      List<EntryDocument>.unmodifiable(_documents);

  @override
  Future<void> init() async {}

  @override
  String get deviceId => _device;

  @override
  String? get boundAccountId => _account;

  @override
  DateTime? get lastSyncedAt => _lastSynced;

  @override
  Future<void> setLastSyncedAt(DateTime? value) async {
    _lastSynced = value?.toUtc();
  }

  @override
  List<SyncedDocumentHead> get documentHeads =>
      List<SyncedDocumentHead>.unmodifiable(_heads.values);

  @override
  SyncedDocumentHead? documentHead(String id) => _heads[id];

  @override
  SyncedCollectionHead? get collectionHead => _collection;

  @override
  Future<void> saveDocumentHead(SyncedDocumentHead head) async {
    _heads[head.documentId] = head;
  }

  @override
  Future<void> saveCollectionHead(SyncedCollectionHead head) async {
    _collection = head;
  }

  @override
  Future<void> bindAccount(String accountId) async => _account = accountId;

  @override
  Future<void> clearAccountBinding() async => _account = null;

  @override
  Future<void> upsertDocumentExact(EntryDocument document) async {
    final index = _documents.indexWhere((item) => item.id == document.id);
    if (index < 0) {
      _documents.add(document);
    } else {
      _documents[index] = document;
    }
  }

  @override
  Future<void> deleteDocumentExact(String id) async {
    _documents.removeWhere((document) => document.id == id);
  }

  @override
  Future<void> reorderDocumentsExact(Iterable<EntryDocument> ordered) async {
    final byId = <String, EntryDocument>{
      for (final document in _documents) document.id: document,
    };
    final next = <EntryDocument>[
      for (final document in ordered)
        if (byId[document.id] != null) byId[document.id]!,
    ];
    if (next.length == _documents.length) {
      _documents
        ..clear()
        ..addAll(next);
    }
  }

  @override
  LocalAssetSnapshot? asset(String id) => _assets[id];

  @override
  Future<void> putAssetExact(LocalAssetSnapshot asset) async {
    _assets[asset.id] = asset;
  }

  @override
  Future<void> clearAllLocalData() async {
    _heads.clear();
    _collection = null;
    _documents.clear();
    _assets.clear();
    _account = null;
    _lastSynced = null;
  }
}
