import 'dart:async';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../models/asset_kind.dart';
import '../models/checkpoint.dart';
import '../models/document.dart';
import '../models/entry.dart';
import '../models/storage_records.dart';
import 'entry_document_codec.dart';
import 'hive_journal_data_source.dart';
import 'journal_archive.dart';

/// Internal document data source backed by the shared raw Hive boxes.
///
/// This source owns the in-memory document projection and order metadata. It
/// deliberately exposes only immutable [EntryDocument] values to repository
/// adapters; mutable [Entry] records are confined to the codec boundary.
class HiveDocumentDataSource {
  HiveDocumentDataSource(this.storage) {
    if (storage.isOpen) _load();
  }

  final HiveJournalDataSource storage;
  final StreamController<void> _changes =
      StreamController<void>.broadcast();
  List<EntryDocument> _documents = <EntryDocument>[];
  bool _loaded = false;

  bool get isLoaded => _loaded;
  List<EntryDocument> get documents =>
      List<EntryDocument>.unmodifiable(_documents);
  Stream<void> get changes => _changes.stream;

  Future<void> init() async {
    await storage.open();
    _load();
  }

  EntryDocument? documentById(String id) {
    for (final document in _documents) {
      if (document.id == id) return document;
    }
    return null;
  }

  Future<EntryDocument> createDocument({String title = ''}) async {
    await _ensureLoaded();
    final now = DateTime.now();
    final document = EntryDocument(
      id: const Uuid().v4(),
      title: title.trim(),
      createdAt: now,
      modifiedAt: now,
    );
    _documents = List<EntryDocument>.unmodifiable([..._documents, document]);
    final order = _documents.map((item) => item.id).toList(growable: false);
    await storage.enqueue(() async {
      await storage.writeEntry(
        document.id,
        EntryDocumentCodec.toEntry(document).toJson(),
      );
      await storage.writeMeta('entryOrder', order);
      _publish();
    });
    return document;
  }

  Future<void> saveDocument(EntryDocument document) async {
    await _ensureLoaded();
    final index = _documents.indexWhere((item) => item.id == document.id);
    if (index < 0) return;
    final next = document.copyWith(
      modifiedAt: DateTime.now(),
      revision: document.revision + 1,
    );
    final updated = List<EntryDocument>.from(_documents)..[index] = next;
    _documents = List<EntryDocument>.unmodifiable(updated);
    final json = EntryDocumentCodec.toEntry(next).toJson();
    await storage.enqueue(() async {
      await storage.writeEntry(next.id, json);
      _publish();
    });
  }

  /// Publishes a responsive in-memory preview without writing to Hive.
  void previewDocument(EntryDocument document) {
    final index = _documents.indexWhere((item) => item.id == document.id);
    if (index < 0) return;
    final updated = List<EntryDocument>.from(_documents)..[index] = document;
    _documents = List<EntryDocument>.unmodifiable(updated);
  }

  Future<void> deleteDocument(String id) async {
    await _ensureLoaded();
    final remaining = _documents.where((item) => item.id != id).toList();
    if (remaining.length == _documents.length) return;
    _documents = List<EntryDocument>.unmodifiable(remaining);
    final order = remaining.map((item) => item.id).toList(growable: false);
    await storage.enqueue(() async {
      await storage.deleteEntry(id);
      await storage.writeMeta('entryOrder', order);
      _publish();
    });
  }

  Future<void> replaceRestoredDocument(EntryDocument document) async {
    await _ensureLoaded();
    final index = _documents.indexWhere((item) => item.id == document.id);
    if (index < 0) return;
    final updated = List<EntryDocument>.from(_documents)..[index] = document;
    _documents = List<EntryDocument>.unmodifiable(updated);
    await storage.enqueue(() async {
      await storage.writeEntry(
        document.id,
        EntryDocumentCodec.toEntry(document).toJson(),
      );
      _publish();
    });
  }

  /// Applies a cloud document without incrementing its local revision. This
  /// method is intentionally kept on the internal source so feature code can
  /// only persist through the normal repository contract.
  Future<void> upsertExact(EntryDocument document) async {
    await _ensureLoaded();
    final index = _documents.indexWhere((item) => item.id == document.id);
    final updated = List<EntryDocument>.from(_documents);
    if (index < 0) {
      updated.add(document);
    } else {
      updated[index] = document;
    }
    _documents = List<EntryDocument>.unmodifiable(updated);
    final order = _documents.map((item) => item.id).toList(growable: false);
    await storage.enqueue(() async {
      await storage.writeEntry(
        document.id,
        EntryDocumentCodec.toEntry(document).toJson(),
      );
      await storage.writeMeta('entryOrder', order);
      _publish();
    });
  }

  /// Removes a cloud tombstoned document without changing any sync metadata.
  Future<void> deleteExact(String id) async {
    await _ensureLoaded();
    final remaining = _documents.where((item) => item.id != id).toList();
    if (remaining.length == _documents.length) return;
    _documents = List<EntryDocument>.unmodifiable(remaining);
    final order = remaining.map((item) => item.id).toList(growable: false);
    await storage.enqueue(() async {
      await storage.deleteEntry(id);
      await storage.writeMeta('entryOrder', order);
      _publish();
    });
  }

  Future<void> clearAll() async {
    await _ensureLoaded();
    final ids = storage.entryKeys.toList();
    _documents = const <EntryDocument>[];
    await storage.enqueue(() async {
      for (final id in ids) {
        await storage.deleteEntry(id.toString());
      }
      await storage.writeMeta('entryOrder', const <String>[]);
      _publish();
    });
  }

  Future<void> reorderExact(Iterable<EntryDocument> ordered) async {
    await _ensureLoaded();
    final byId = <String, EntryDocument>{
      for (final document in _documents) document.id: document,
    };
    final next = <EntryDocument>[
      for (final document in ordered)
        if (byId[document.id] != null) byId[document.id]!,
    ];
    if (next.length != _documents.length) return;
    _documents = List<EntryDocument>.unmodifiable(next);
    await storage.enqueue(() async {
      await storage.writeMeta(
        'entryOrder',
        next.map((document) => document.id).toList(growable: false),
      );
      _publish();
    });
  }

  Future<void> dispose() async {
    if (!_changes.isClosed) await _changes.close();
  }

  Future<void> _ensureLoaded() async {
    if (!_loaded) await init();
  }

  void _load() {
    final rawOrder = storage.readMeta('entryOrder');
    final order = rawOrder is List
        ? rawOrder.whereType<String>().toList(growable: false)
        : const <String>[];
    final loadedIds = <String>{};
    final loaded = <EntryDocument>[];
    for (final id in order) {
      final document = _readDocument(id);
      if (document != null) {
        loaded.add(document);
        loadedIds.add(id);
      }
    }
    final unordered = storage.entryKeys
        .whereType<String>()
        .where((id) => !loadedIds.contains(id))
        .toList()
      ..sort();
    for (final id in unordered) {
      final document = _readDocument(id);
      if (document != null) loaded.add(document);
    }
    _documents = List<EntryDocument>.unmodifiable(loaded);
    _loaded = true;
    _publish();
  }

  EntryDocument? _readDocument(String id) {
    final raw = storage.readEntry(id);
    if (raw is! Map) return null;
    try {
      final json = Map<String, dynamic>.from(raw);
      if (json['nodes'] is List && json['blocks'] == null) {
        return EntryDocument.fromJson(json);
      }
      return EntryDocumentCodec.fromEntry(Entry.fromJson(json));
    } catch (_) {
      return null;
    }
  }

  void _publish() {
    if (!_changes.isClosed) _changes.add(null);
  }
}

/// Internal asset data source. Asset bytes remain raw and immutable while
/// references are collected from immutable documents and storage snapshots.
class HiveAssetDataSource {
  HiveAssetDataSource(this.storage, {required this.documents});

  final HiveJournalDataSource storage;
  final Iterable<EntryDocument> Function() documents;
  static const _uuid = Uuid();

  Future<String> putAsset(
    String ownerId,
    AssetKind kind,
    String mime,
    List<int> bytes,
  ) async {
    final id = _uuid.v4();
    final record = AssetRecord(
      entryId: ownerId,
      kind: kind,
      mime: mime,
      data: List<int>.unmodifiable(bytes),
    );
    await storage.enqueue(() => storage.writeAsset(id, record.toJson()));
    return id;
  }

  Uint8List? readAsset(String id) {
    final raw = storage.readAsset(id);
    if (raw is! Map) return null;
    try {
      return Uint8List.fromList(
        AssetRecord.fromJson(Map<String, dynamic>.from(raw)).data,
      );
    } catch (_) {
      return null;
    }
  }

  String? assetMime(String id) {
    final raw = storage.readAsset(id);
    if (raw is! Map) return null;
    try {
      return AssetRecord.fromJson(Map<String, dynamic>.from(raw)).mime;
    } catch (_) {
      return null;
    }
  }

  AssetRecord? snapshot(String id) {
    final raw = storage.readAsset(id);
    if (raw is! Map) return null;
    try {
      return AssetRecord.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> putExact(
    String id,
    String ownerId,
    AssetKind kind,
    String mime,
    List<int> bytes,
  ) {
    final record = AssetRecord(
      entryId: ownerId,
      kind: kind,
      mime: mime,
      data: List<int>.unmodifiable(bytes),
    );
    return storage.enqueue(() => storage.writeAsset(id, record.toJson()));
  }

  Future<void> clearAll() async {
    final ids = storage.assetKeys.toList();
    await storage.enqueue(() async {
      for (final id in ids) {
        await storage.deleteAsset(id.toString());
      }
    });
  }

  Future<void> collectUnreferencedAssets({
    Iterable<String> retainedAssetIds = const <String>[],
  }) async {
    final referenced = <String>{...retainedAssetIds};
    void collectNodes(Iterable<CanvasNode> nodes) {
      for (final node in nodes) {
        if (node.assetId != null) referenced.add(node.assetId!);
        if (node.children.isNotEmpty) collectNodes(node.children);
      }
    }

    for (final document in documents()) {
      collectNodes(document.nodes);
    }
    for (final key in storage.checkpointKeys) {
      final raw = storage.readCheckpoint(key.toString());
      if (raw is! Map || raw['entry'] is! Map) continue;
      try {
        final document = EntryDocumentCodec.fromEntry(
          Entry.fromJson(Map<String, dynamic>.from(raw['entry'] as Map)),
        );
        collectNodes(document.nodes);
      } catch (_) {}
    }
    for (final key in storage.assetKeys.toList()) {
      if (!referenced.contains(key.toString())) {
        await storage.deleteAsset(key.toString());
      }
    }
  }
}

/// Internal checkpoint data source that coordinates recovery with documents.
class HiveCheckpointDataSource {
  HiveCheckpointDataSource(this.storage, {required this.documents});

  final HiveJournalDataSource storage;
  final HiveDocumentDataSource documents;
  final Map<String, Timer> _timers = <String, Timer>{};

  List<CheckpointInfo> checkpointsFor(String documentId) {
    final result = <CheckpointInfo>[];
    for (final key in storage.checkpointKeys.whereType<String>()) {
      final raw = storage.readCheckpoint(key);
      if (raw is! Map) continue;
      try {
        final checkpoint = EntryCheckpoint.fromJson(
          key,
          Map<String, dynamic>.from(raw),
        );
        if (checkpoint.entryId == documentId) {
          result.add(
            CheckpointInfo(
              id: checkpoint.id,
              documentId: checkpoint.entryId,
              createdAt: checkpoint.createdAt,
            ),
          );
        }
      } catch (_) {}
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List<CheckpointInfo>.unmodifiable(result);
  }

  void scheduleCheckpoint(String documentId) {
    if (_timers.containsKey(documentId)) return;
    _timers[documentId] = Timer(const Duration(minutes: 5), () {
      _timers.remove(documentId);
      unawaited(createCheckpoint(documentId));
    });
  }

  Future<void> createCheckpoint(String documentId) async {
    final document = documents.documentById(documentId);
    if (document == null) return;
    final now = DateTime.now();
    final checkpoint = EntryCheckpoint(
      id: '$documentId:${now.microsecondsSinceEpoch}',
      entryId: documentId,
      createdAt: now,
      entry: EntryDocumentCodec.toEntry(document),
    );
    await storage.enqueue(() async {
      await storage.writeCheckpoint(checkpoint.id, checkpoint.toJson());
      await _prune(documentId, now);
    });
  }

  Future<void> restoreCheckpoint(String checkpointId) async {
    final raw = storage.readCheckpoint(checkpointId);
    if (raw is! Map) return;
    final checkpoint = EntryCheckpoint.fromJson(
      checkpointId,
      Map<String, dynamic>.from(raw),
    );
    final restored = EntryDocumentCodec.fromEntry(checkpoint.entry).copyWith(
      modifiedAt: DateTime.now(),
      revision: checkpoint.entry.revision + 1,
    );
    await documents.replaceRestoredDocument(restored);
  }

  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }

  Future<void> _prune(String documentId, DateTime now) async {
    final checkpoints = <({String id, DateTime createdAt})>[];
    for (final key in storage.checkpointKeys.whereType<String>()) {
      final raw = storage.readCheckpoint(key);
      if (raw is! Map) continue;
      try {
        final checkpoint = EntryCheckpoint.fromJson(
          key,
          Map<String, dynamic>.from(raw),
        );
        if (checkpoint.entryId == documentId) {
          checkpoints.add((id: key, createdAt: checkpoint.createdAt));
        }
      } catch (_) {}
    }
    checkpoints.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final weekAgo = now.subtract(const Duration(days: 7));
    for (var index = 20; index < checkpoints.length; index++) {
      final checkpoint = checkpoints[index];
      if (checkpoint.createdAt.isBefore(weekAgo)) {
        await storage.deleteCheckpoint(checkpoint.id);
      }
    }
  }
}

/// Internal color preference data source.
class HivePreferencesDataSource {
  HivePreferencesDataSource(this.storage);

  final HiveJournalDataSource storage;

  List<int> get recentColorValues => _readList('colorPickerRecent', 8);

  Set<int> get favoriteColorValues => _readList('colorPickerFavorites', 12).toSet();

  Future<void> updateColorPreferences({
    List<int>? recent,
    Set<int>? favorites,
  }) => storage.enqueue(() async {
    if (recent != null) {
      await storage.writeMeta(
        'colorPickerRecent',
        recent.take(8).toList(growable: false),
      );
    }
    if (favorites != null) {
      await storage.writeMeta(
        'colorPickerFavorites',
        favorites.take(12).toList(growable: false),
      );
    }
  });

  List<int> _readList(String key, int limit) {
    final raw = storage.readMeta(key);
    if (raw is! List) return const <int>[];
    return List<int>.unmodifiable(
      raw.whereType<num>().map((item) => item.toInt()).take(limit),
    );
  }
}

/// Internal archive data source coordinating document and asset capability
/// data sources without exposing the aggregate store.
class HiveArchiveDataSource {
  HiveArchiveDataSource(
    this.storage, {
    required this.documents,
    required this.assets,
  });

  final HiveJournalDataSource storage;
  final HiveDocumentDataSource documents;
  final HiveAssetDataSource assets;

  JournalArchive? archiveForDocument(String documentId) {
    final document = documents.documentById(documentId);
    if (document == null) return null;
    final ids = <String>{};
    void collect(Iterable<CanvasNode> nodes) {
      for (final node in nodes) {
        if (node.assetId != null) ids.add(node.assetId!);
        if (node.children.isNotEmpty) collect(node.children);
      }
    }

    collect(document.nodes);
    final archiveAssets = <ArchiveAsset>[];
    for (final id in ids) {
      final bytes = assets.readAsset(id);
      final mime = assets.assetMime(id);
      if (bytes != null && mime != null) {
        archiveAssets.add(ArchiveAsset(id: id, mime: mime, bytes: bytes));
      }
    }
    return JournalArchive(
      document: document,
      assets: archiveAssets,
    );
  }

  Future<EntryDocument> importArchive(JournalArchive archive) async {
    final target = await documents.createDocument(title: archive.document.title);
    final assetIds = <String, String>{};
    for (final asset in archive.assets) {
      assetIds[asset.id] = await assets.putAsset(
        target.id,
        asset.mime.startsWith('audio/') ? AssetKind.audio : AssetKind.image,
        asset.mime,
        asset.bytes,
      );
    }
    final imported = _remapAssets(archive.document, assetIds, target.id);
    await documents.replaceRestoredDocument(imported);
    return documents.documentById(target.id) ?? imported;
  }

  EntryDocument _remapAssets(
    EntryDocument source,
    Map<String, String> assetIds,
    String targetId,
  ) {
    List<CanvasNode> visit(Iterable<CanvasNode> nodes) => nodes
        .map(
          (node) {
            final payload = Map<String, dynamic>.from(node.payload);
            final original = node.assetId;
            if (original != null && assetIds.containsKey(original)) {
              payload['assetId'] = assetIds[original];
            }
            return node.copyWith(
              payload: payload,
              children: node.children.isEmpty ? node.children : visit(node.children),
            );
          },
        )
        .toList(growable: false);
    return EntryDocument(
      id: targetId,
      title: source.title,
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
      nodes: visit(source.nodes),
      board: source.board,
      view: source.view,
      music: source.music,
      titleFontSize: source.titleFontSize,
      titleFontFamily: source.titleFontFamily,
      titleTextColorValue: source.titleTextColorValue,
      titleBold: source.titleBold,
      titleItalic: source.titleItalic,
      revision: source.revision,
      schemaVersion: source.schemaVersion,
    );
  }
}
