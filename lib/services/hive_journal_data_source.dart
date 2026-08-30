import 'dart:async';

import 'package:hive_flutter/hive_flutter.dart';

import 'storage_codec.dart';

/// Raw Hive access for the journal data layer.
///
/// This service owns box names, box handles, and serialized values. Domain
/// conversion and in-memory notifications stay in repositories/store code.
class HiveJournalDataSource {
  HiveJournalDataSource();

  static const _legacyEntriesBoxName = 'entries';
  static const _legacyAssetsBoxName = 'assets';
  static const _legacyMetaBoxName = 'meta';
  static const _legacyCheckpointsBoxName = 'entryCheckpoints';
  static const _legacySyncHeadsBoxName = 'syncHeads';
  static const _legacyQuarantineBoxName = 'storageQuarantine';
  static const _entriesBoxName = 'cozyBloom.documents.v2';
  static const _assetsBoxName = 'cozyBloom.assets.v2';
  static const _metaBoxName = 'cozyBloom.meta.v2';
  static const _checkpointsBoxName = 'cozyBloom.checkpoints.v2';
  static const _syncHeadsBoxName = 'cozyBloom.syncHeads.v2';
  static const _quarantineBoxName = 'cozyBloom.quarantine.v2';
  static const _schemaKey = 'storage.format';
  static const _schemaNamespace = JournalStorageFormat.namespace;

  late Box<dynamic> _entries;
  late Box<dynamic> _assets;
  late Box<dynamic> _meta;
  late Box<dynamic> _checkpoints;
  late Box<dynamic> _syncHeads;
  late Box<dynamic> _quarantine;
  Future<void> _writeQueue = Future<void>.value();
  Future<void>? _openOperation;
  Future<void>? _closeOperation;

  bool get isOpen => _openOperation != null;

  Future<void> open() {
    final existing = _openOperation;
    if (existing != null) return existing;
    final operation = () async {
      _entries = await Hive.openBox<dynamic>(_entriesName);
      _assets = await Hive.openBox<dynamic>(_assetsName);
      _meta = await Hive.openBox<dynamic>(_metaName);
      _checkpoints = await Hive.openBox<dynamic>(_checkpointsName);
      _syncHeads = await Hive.openBox<dynamic>(_syncHeadsName);
      _quarantine = await Hive.openBox<dynamic>(_quarantineName);
      await _initializeNamespace();
    }();
    _openOperation = operation;
    return operation;
  }

  dynamic readEntry(String id) => _entries.get(id);

  Iterable<dynamic> get entryKeys => _entries.keys;

  Future<void> writeEntry(String id, dynamic value) => _entries.put(id, value);

  Future<void> deleteEntry(String id) => _entries.delete(id);

  dynamic readMeta(String key) => _meta.get(key);

  Future<void> writeMeta(String key, dynamic value) => _meta.put(key, value);

  Future<void> deleteMeta(String key) => _meta.delete(key);

  Future<void> writeSchemaMarker() => _meta.put(_schemaKey, _schemaNamespace);

  dynamic readAsset(String id) => _assets.get(id);

  Iterable<dynamic> get assetKeys => _assets.keys;

  Future<void> writeAsset(String id, dynamic value) => _assets.put(id, value);

  Future<void> deleteAsset(String id) => _assets.delete(id);

  dynamic readCheckpoint(String id) => _checkpoints.get(id);

  Iterable<dynamic> get checkpointKeys => _checkpoints.keys;

  Future<void> writeCheckpoint(String id, dynamic value) =>
      _checkpoints.put(id, value);

  Future<void> deleteCheckpoint(String id) => _checkpoints.delete(id);

  Future<void> clearCheckpoints() => _checkpoints.clear();

  Future<void> clearQuarantine() => _quarantine.clear();

  dynamic readSyncHead(String key) => _syncHeads.get(key);

  Iterable<dynamic> get syncHeadKeys => _syncHeads.keys;

  Future<void> writeSyncHead(String key, dynamic value) =>
      _syncHeads.put(key, value);

  Future<void> deleteSyncHead(String key) => _syncHeads.delete(key);

  Future<void> clearSyncHeads() => _syncHeads.clear();

  Future<void> quarantine(String category, String key, Object? raw, Object error) =>
      _quarantine.put('$category:$key', <String, dynamic>{
        'category': category,
        'key': key,
        'raw': raw,
        'error': error.toString(),
        'recordedAt': DateTime.now().toUtc().toIso8601String(),
      });

  Future<void> enqueue(Future<void> Function() operation) {
    final result = _writeQueue.then((_) => operation());
    _writeQueue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }

  Future<void> flush() async {
    if (!isOpen) return;
    await _writeQueue;
    await _entries.flush();
    await _assets.flush();
    await _meta.flush();
    await _checkpoints.flush();
    await _syncHeads.flush();
    await _quarantine.flush();
  }

  /// Closes the boxes owned by this source when the composition root is
  /// disposed. The global Hive registry remains owned by the platform boot.
  ///
  /// The returned future completes only after queued writes and every box
  /// close have finished, so composition roots and tests can await shutdown.
  Future<void> dispose() async {
    if (!isOpen) return;
    final existing = _closeOperation;
    if (existing != null) {
      await existing;
      return;
    }
    final operation = _closeBoxes();
    _closeOperation = operation;
    await operation;
  }

  Future<void> _closeBoxes() async {
    await _writeQueue;
    await _entries.close();
    await _assets.close();
    await _meta.close();
    await _checkpoints.close();
    await _syncHeads.close();
    await _quarantine.close();
  }

  /// Development builds wrote a different shape into these boxes.  The final
  /// contract intentionally starts clean; the marker is written only after
  /// the old records have been removed so a failed initialization cannot leave
  /// a partially adopted namespace.
  Future<void> _initializeNamespace() async {
    if (_meta.get(_schemaKey) == _schemaNamespace) return;
    await _entries.clear();
    await _assets.clear();
    await _checkpoints.clear();
    await _syncHeads.clear();
    await _quarantine.clear();
    await _meta.clear();
    await _removeLegacyBoxes();
    await _meta.put(_schemaKey, _schemaNamespace);
  }

  Future<void> _removeLegacyBoxes() async {
    for (final name in <String>[
      _legacyEntriesBoxName,
      _legacyAssetsBoxName,
      _legacyMetaBoxName,
      _legacyCheckpointsBoxName,
      _legacySyncHeadsBoxName,
      _legacyQuarantineBoxName,
    ]) {
      if (Hive.isBoxOpen(name)) await Hive.box<dynamic>(name).close();
      if (await Hive.boxExists(name)) await Hive.deleteBoxFromDisk(name);
    }
  }

  String get _entriesName => _entriesBoxName;
  String get _assetsName => _assetsBoxName;
  String get _metaName => _metaBoxName;
  String get _checkpointsName => _checkpointsBoxName;
  String get _syncHeadsName => _syncHeadsBoxName;
  String get _quarantineName => _quarantineBoxName;
}
