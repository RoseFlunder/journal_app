import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../models/document.dart';
import '../models/entry.dart';
import '../models/storage_records.dart';
import 'entry_document_codec.dart';
import 'hive_journal_data_source.dart';
import 'journal_archive.dart';
import 'storage_codec.dart';
import 'repositories.dart';

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
  final Map<String, int> _revisions = <String, int>{};
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
    final now = DateTime.now().toUtc();
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
        JournalDocumentCodec.encodeRecord(document, revision: 0),
      );
      await _writeManifest(order);
      _publish();
    });
    return document;
  }

  Future<void> saveDocument(EntryDocument document) async {
    await _ensureLoaded();
    final index = _documents.indexWhere((item) => item.id == document.id);
    if (index < 0) return;
    final existing = _documents[index];
    final contentChanged = !JournalDocumentCodec.sameContent(existing, document);
    final next = document.copyWith(
      modifiedAt: contentChanged ? DateTime.now().toUtc() : existing.modifiedAt,
    );
    // Camera and grid preferences are device-local metadata. A view-only
    // update must not advance the durable document revision or rewrite its
    // canonical content record.
    if (!contentChanged) {
      final updated = List<EntryDocument>.from(_documents)..[index] = next;
      _documents = List<EntryDocument>.unmodifiable(updated);
      await storage.enqueue(() async {
        await storage.writeMeta(
          _viewKey(next.id),
          StoredViewPreferences(
            view: next.view,
            gridVisible: next.board.gridVisible,
          ).toJson(),
        );
        _publish();
      });
      return;
    }
    final revision = (_revisions[document.id] ?? 0) + 1;
    _revisions[document.id] = revision;
    final updated = List<EntryDocument>.from(_documents)..[index] = next;
    _documents = List<EntryDocument>.unmodifiable(updated);
    await storage.enqueue(() async {
      await storage.writeEntry(
        next.id,
        JournalDocumentCodec.encodeRecord(next, revision: revision),
      );
      await storage.writeMeta(
        _viewKey(next.id),
        StoredViewPreferences(
          view: next.view,
          gridVisible: next.board.gridVisible,
        ).toJson(),
      );
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
      await storage.deleteMeta(_viewKey(id));
      await _writeManifest(order);
      _publish();
    });
  }

  Future<void> replaceRestoredDocument(EntryDocument document) async {
    await _ensureLoaded();
    final index = _documents.indexWhere((item) => item.id == document.id);
    if (index < 0) return;
    final current = _documents[index];
    final restored = document.copyWith(
      view: current.view,
      board: document.board.copyWith(gridVisible: current.board.gridVisible),
    );
    final updated = List<EntryDocument>.from(_documents)..[index] = restored;
    _documents = List<EntryDocument>.unmodifiable(updated);
    await storage.enqueue(() async {
      await storage.writeEntry(
        restored.id,
        JournalDocumentCodec.encodeRecord(
          restored,
          revision: _revisions[document.id] ?? 0,
        ),
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
    final current = index < 0 ? null : _documents[index];
    final imported = current == null
        ? document
        : document.copyWith(
            view: current.view,
            board: document.board.copyWith(gridVisible: current.board.gridVisible),
          );
    final updated = List<EntryDocument>.from(_documents);
    if (index < 0) {
      updated.add(imported);
    } else {
      updated[index] = imported;
    }
    _documents = List<EntryDocument>.unmodifiable(updated);
    final order = _documents.map((item) => item.id).toList(growable: false);
    await storage.enqueue(() async {
      await storage.writeEntry(
        imported.id,
        JournalDocumentCodec.encodeRecord(
          imported,
          revision: _revisions[document.id] ?? 0,
        ),
      );
      await _writeManifest(order);
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
      await storage.deleteMeta(_viewKey(id));
      await _writeManifest(order);
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
        await storage.deleteMeta(_viewKey(id.toString()));
      }
      _revisions.clear();
      await _writeManifest(const <String>[]);
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
        'journal.manifest',
        StoredJournalManifest(
          next.map((document) => document.id),
        ).toJson(),
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
    final rawManifest = storage.readMeta('journal.manifest');
    Object? rawOrder;
    if (rawManifest is Map) {
      try {
        rawOrder = StoredJournalManifest.fromJson(rawManifest).documentIds;
      } catch (error) {
        unawaited(storage.quarantine('manifest', 'journal.manifest', rawManifest, error));
        rawOrder = const <String>[];
      }
    } else {
      rawOrder = storage.readMeta('entryOrder');
    }
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
    final repairedOrder = loaded.map((document) => document.id).toList(growable: false);
    if (rawManifest is! Map ||
        !_sameIds(rawOrder is List ? rawOrder.whereType<String>() : const [], repairedOrder)) {
      unawaited(storage.enqueue(() => _writeManifest(repairedOrder)));
    }
    _publish();
  }

  EntryDocument? _readDocument(String id) {
    final raw = storage.readEntry(id);
    if (raw == null) {
      return null;
    }
    if (raw is! Map) {
      unawaited(
        storage.quarantine(
          'document',
          id,
          raw,
          const StorageFormatException('Document record is not an object'),
        ),
      );
      return null;
    }
    try {
      final json = Map<String, dynamic>.from(raw);
      if (json['format'] == JournalStorageFormat.document) {
        final record = JournalDocumentCodec.decodeRecord(json);
        _revisions[id] = record.revision;
        final view = _readView(id);
        final gridVisible = _readGridVisible(id);
        var document = record.document;
        if (view != null) document = document.copyWith(view: view);
        if (gridVisible != null) {
          document = document.copyWith(
            board: document.board.copyWith(gridVisible: gridVisible),
          );
        }
        return document;
      }
      if (!storage.resetLegacyNamespace &&
          json['nodes'] is List &&
          json['blocks'] == null) {
        return EntryDocument.fromJson(json);
      }
      if (!storage.resetLegacyNamespace) {
        return EntryDocumentCodec.fromEntry(Entry.fromJson(json));
      }
      throw const StorageFormatException('Unsupported document record format');
    } catch (error) {
      unawaited(storage.quarantine('document', id, raw, error));
      return null;
    }
  }

  ViewState? _readView(String id) {
    final raw = storage.readMeta(_viewKey(id));
    if (raw == null) {
      return null;
    }
    if (raw is! Map) {
      unawaited(
        storage.quarantine(
          'view',
          id,
          raw,
          const StorageFormatException('View preferences are not an object'),
        ),
      );
      return null;
    }
    try {
      return StoredViewPreferences.fromJson(raw).view;
    } catch (error) {
      unawaited(storage.quarantine('view', id, raw, error));
      return null;
    }
  }

  bool? _readGridVisible(String id) {
    final raw = storage.readMeta(_viewKey(id));
    if (raw == null) {
      return null;
    }
    if (raw is! Map) {
      unawaited(
        storage.quarantine(
          'view',
          id,
          raw,
          const StorageFormatException('View preferences are not an object'),
        ),
      );
      return null;
    }
    try {
      return StoredViewPreferences.fromJson(raw).gridVisible;
    } catch (error) {
      unawaited(storage.quarantine('view', id, raw, error));
      return null;
    }
  }

  Future<void> _writeManifest(Iterable<String> ids) => storage.writeMeta(
        'journal.manifest',
        StoredJournalManifest(ids).toJson(),
      );

  static String _viewKey(String id) => 'viewPreferences:$id';

  static bool _sameIds(Iterable<String> left, Iterable<String> right) {
    final a = left.toList(growable: false);
    final b = right.toList(growable: false);
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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

  Future<String> putAsset(
    String ownerId,
    AssetKind kind,
    String mime,
    List<int> bytes,
  ) async {
    if (mime.trim().isEmpty || !mime.contains('/') || mime.contains(RegExp(r'\s'))) {
      throw const StorageFormatException('Asset MIME type is invalid');
    }
    if (bytes.any((byte) => byte < 0 || byte > 255)) {
      throw const StorageFormatException('Asset bytes are invalid');
    }
    final digest = sha256.convert(bytes).toString();
    final record = StoredAssetRecord(
      id: digest,
      kind: assetKindDiscriminator(kind),
      mime: mime,
      bytes: bytes,
    );
    final existing = storage.readAsset(digest);
    if (existing is Map && existing['format'] == JournalStorageFormat.asset) {
      final stored = StoredAssetRecord.fromJson(existing);
      if (stored.kind != assetKindDiscriminator(kind) || stored.mime != mime) {
        throw const StorageFormatException(
          'Content-addressed asset metadata cannot be changed',
        );
      }
      return digest;
    }
    await storage.enqueue(() => storage.writeAsset(digest, record.toJson()));
    return digest;
  }

  Future<AssetDescriptor> putImmutableAsset(
    AssetKind kind,
    String mime,
    List<int> bytes,
  ) async {
    final id = await putAsset('', kind, mime, bytes);
    final record = StoredAssetRecord(
      id: id,
      kind: assetKindDiscriminator(kind),
      mime: mime,
      bytes: bytes,
    );
    return AssetDescriptor(
      id: id,
      kind: kind,
      mime: mime,
      byteLength: record.bytes.length,
      sha256: id,
      width: record.width,
      height: record.height,
    );
  }

  Uint8List? readAsset(String id) {
    final raw = storage.readAsset(id);
    if (raw == null) return null;
    if (raw is! Map) {
      unawaited(
        storage.quarantine(
          'asset',
          id,
          raw,
          const StorageFormatException('Asset record is not an object'),
        ),
      );
      return null;
    }
    try {
      if (raw['format'] == JournalStorageFormat.asset) {
        return Uint8List.fromList(StoredAssetRecord.fromJson(raw).bytes);
      }
      return Uint8List.fromList(
        AssetRecord.fromJson(Map<String, dynamic>.from(raw)).data,
      );
    } catch (error) {
      unawaited(storage.quarantine('asset', id, raw, error));
      return null;
    }
  }

  String? assetMime(String id) {
    final raw = storage.readAsset(id);
    if (raw == null) return null;
    if (raw is! Map) {
      unawaited(
        storage.quarantine(
          'asset',
          id,
          raw,
          const StorageFormatException('Asset record is not an object'),
        ),
      );
      return null;
    }
    try {
      if (raw['format'] == JournalStorageFormat.asset) {
        return StoredAssetRecord.fromJson(raw).mime;
      }
      return AssetRecord.fromJson(Map<String, dynamic>.from(raw)).mime;
    } catch (error) {
      unawaited(storage.quarantine('asset', id, raw, error));
      return null;
    }
  }

  AssetBlob? readAssetBlob(String id) {
    final raw = storage.readAsset(id);
    if (raw == null) return null;
    if (raw is! Map) {
      unawaited(
        storage.quarantine(
          'asset',
          id,
          raw,
          const StorageFormatException('Asset record is not an object'),
        ),
      );
      return null;
    }
    try {
      if (raw['format'] == JournalStorageFormat.asset) {
        final stored = StoredAssetRecord.fromJson(raw);
        return AssetBlob(
          descriptor: AssetDescriptor(
            id: stored.id,
            kind: assetKindFromDiscriminator(stored.kind),
            mime: stored.mime,
            byteLength: stored.bytes.length,
            sha256: stored.id,
            width: stored.width,
            height: stored.height,
          ),
          bytes: stored.bytes,
        );
      }
      final legacy = AssetRecord.fromJson(Map<String, dynamic>.from(raw));
      final digest = sha256.convert(legacy.data).toString();
      return AssetBlob(
        descriptor: AssetDescriptor(
          id: digest,
          kind: legacy.kind,
          mime: legacy.mime,
          byteLength: legacy.data.length,
          sha256: digest,
        ),
        bytes: legacy.data,
      );
    } catch (error) {
      unawaited(storage.quarantine('asset', id, raw, error));
      return null;
    }
  }

  AssetRecord? snapshot(String id) {
    final raw = storage.readAsset(id);
    if (raw is! Map) return null;
    try {
      if (raw['format'] == JournalStorageFormat.asset) {
        final stored = StoredAssetRecord.fromJson(raw);
        return AssetRecord(
          entryId: '',
          kind: assetKindFromDiscriminator(stored.kind),
          mime: stored.mime,
          data: stored.bytes,
        );
      }
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
    final digest = sha256.convert(bytes).toString();
    if (id != digest) {
      throw StorageFormatException('Asset ID $id does not match its content hash');
    }
    final record = StoredAssetRecord(
      id: id,
      kind: assetKindDiscriminator(kind),
      mime: mime,
      bytes: bytes,
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
      if (raw is! Map) continue;
      try {
        final document = raw['format'] == JournalStorageFormat.checkpoint
            ? StoredCheckpointRecord.fromJson(raw).document
            : EntryDocumentCodec.fromEntry(
                Entry.fromJson(Map<String, dynamic>.from(raw['entry'] as Map)),
              );
        collectNodes(document.nodes);
      } catch (error) {
        unawaited(storage.quarantine('checkpoint', key.toString(), raw, error));
      }
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
        final json = Map<String, dynamic>.from(raw);
        final entryId = json['format'] == JournalStorageFormat.checkpoint
            ? StoredCheckpointRecord.fromJson(json).documentId
            : EntryCheckpoint.fromJson(key, json).entryId;
        final createdAt = json['format'] == JournalStorageFormat.checkpoint
            ? StoredCheckpointRecord.fromJson(json).createdAt
            : EntryCheckpoint.fromJson(key, json).createdAt;
        if (entryId == documentId) {
          result.add(
            CheckpointInfo(
              id: key,
              documentId: entryId,
              createdAt: createdAt.toUtc(),
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
    final now = DateTime.now().toUtc();
    final id = '$documentId:${now.microsecondsSinceEpoch}';
    final checkpoint = StoredCheckpointRecord(
      id: id,
      documentId: documentId,
      createdAt: now,
      document: document,
    ).toJson();
    await storage.enqueue(() async {
      await storage.writeCheckpoint(id, checkpoint);
      await _prune(documentId, now);
    });
  }

  Future<void> restoreCheckpoint(String checkpointId) async {
    final raw = storage.readCheckpoint(checkpointId);
    if (raw is! Map) return;
    final json = Map<String, dynamic>.from(raw);
    late final EntryDocument restored;
    try {
      restored = json['format'] == JournalStorageFormat.checkpoint
          ? StoredCheckpointRecord.fromJson(json)
              .document
              .copyWith(modifiedAt: DateTime.now().toUtc())
          : EntryDocumentCodec.fromEntry(
              EntryCheckpoint.fromJson(checkpointId, json).entry,
            ).copyWith(modifiedAt: DateTime.now().toUtc());
    } catch (error) {
      await storage.quarantine('checkpoint', checkpointId, raw, error);
      rethrow;
    }
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
        final json = Map<String, dynamic>.from(raw);
        final entryId = json['format'] == JournalStorageFormat.checkpoint
            ? StoredCheckpointRecord.fromJson(json).documentId
            : EntryCheckpoint.fromJson(key, json).entryId;
        final createdAt = json['format'] == JournalStorageFormat.checkpoint
            ? StoredCheckpointRecord.fromJson(json).createdAt
            : EntryCheckpoint.fromJson(key, json).createdAt;
        if (entryId == documentId) {
          checkpoints.add((id: key, createdAt: createdAt.toUtc()));
        }
      } catch (error) {
        unawaited(storage.quarantine('checkpoint', key, raw, error));
      }
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
    archive.validate();
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
      pageSpec: source.pageSpec,
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
