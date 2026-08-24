import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/entry.dart';

/// Kinds of binary assets stored in the `assets` box.
enum AssetKind { image, audio }

/// A binary asset (image or audio) stored in the `assets` box.
class AssetRecord {
  AssetRecord({
    required this.entryId,
    required this.kind,
    required this.mime,
    required this.data,
  });

  /// The entry this asset belongs to.
  final String entryId;
  final AssetKind kind;
  final String mime;
  final List<int> data;

  Map<String, dynamic> toJson() => {
    'entryId': entryId,
    'kind': kind.name,
    'mime': mime,
    'data': data,
  };

  factory AssetRecord.fromJson(Map<String, dynamic> json) => AssetRecord(
    entryId: json['entryId'] as String,
    kind: AssetKind.values.byName(json['kind'] as String? ?? 'image'),
    mime: json['mime'] as String? ?? '',
    data: (json['data'] as List<dynamic>? ?? const [])
        .map((e) => e is int ? e : (e as num).toInt())
        .toList(),
  );
}

/// A restorable local document snapshot. Assets stay immutable in the normal
/// assets box, so checkpoints only need entry JSON and asset references.
class EntryCheckpoint {
  EntryCheckpoint({
    required this.id,
    required this.entryId,
    required this.createdAt,
    required this.entry,
  });

  final String id;
  final String entryId;
  final DateTime createdAt;
  final Entry entry;

  Map<String, dynamic> toJson() => {
    'entryId': entryId,
    'createdAt': createdAt.toIso8601String(),
    'entry': entry.toJson(),
  };

  factory EntryCheckpoint.fromJson(String id, Map<String, dynamic> json) =>
      EntryCheckpoint(
        id: id,
        entryId: json['entryId'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        entry: Entry.fromJson(Map<String, dynamic>.from(json['entry'] as Map)),
      );
}

/// Loads, owns and persists all journal data.
///
/// Hive layout (see PLAN.md, section 2):
///  * `entries` box: key = entry id, value = Entry JSON
///  * `assets` box:  key = asset id, value = AssetRecord JSON
///  * `meta` box:    key = `entryOrder`, value = `List<String>` of entry
///    ids in page order.
///
/// The store is the single writer: every mutation goes through it and is
/// persisted before [notifyListeners] fires.
class JournalStore extends ChangeNotifier {
  static const _kOrderKey = 'entryOrder';
  static const _boxEntries = 'entries';
  static const _boxAssets = 'assets';
  static const _boxMeta = 'meta';
  static const _boxCheckpoints = 'entryCheckpoints';

  static const _uuid = Uuid();

  late Box _entriesBox;
  late Box _assetsBox;
  late Box _metaBox;
  late Box _checkpointsBox;

  List<Entry> _entries = [];
  bool _loaded = false;
  Future<void> _writeQueue = Future<void>.value();
  final Map<String, Timer> _checkpointTimers = {};

  /// The entries in page order. Index 0 of this list is page 1 (after TOC).
  List<Entry> get entries => List.unmodifiable(_entries);

  bool get isLoaded => _loaded;

  /// Opens the Hive boxes and loads all entries.
  Future<void> init() async {
    _entriesBox = await Hive.openBox(_boxEntries);
    _assetsBox = await Hive.openBox(_boxAssets);
    _metaBox = await Hive.openBox(_boxMeta);
    _checkpointsBox = await Hive.openBox(_boxCheckpoints);
    _load();
  }

  void _load() {
    final rawOrder = _metaBox.get(_kOrderKey);
    final order = rawOrder is List
        ? rawOrder.whereType<String>().toList()
        : <String>[];
    _entries = <Entry>[];
    final loadedIds = <String>{};
    for (final id in order) {
      final entry = _readEntry(id);
      if (entry != null) {
        _entries.add(entry);
        loadedIds.add(id);
      }
    }

    // Recover entries that survived while the order metadata did not.
    final unorderedIds =
        _entriesBox.keys
            .whereType<String>()
            .where((id) => !loadedIds.contains(id))
            .toList()
          ..sort();
    for (final id in unorderedIds) {
      final entry = _readEntry(id);
      if (entry != null) _entries.add(entry);
    }
    _loaded = true;
    notifyListeners();
  }

  Entry? _readEntry(String id) {
    final raw = _entriesBox.get(id);
    if (raw is! Map) {
      debugPrint('Dropping dangling entry id $id (missing data)');
      return null;
    }
    try {
      return Entry.fromJson(Map<String, dynamic>.from(raw));
    } catch (error) {
      debugPrint('Skipping corrupt entry $id: $error');
      return null;
    }
  }

  int indexOfEntry(String id) => _entries.indexWhere((e) => e.id == id);

  /// Creates a new (empty) page at the end and returns it.
  Future<Entry> addEntry() {
    final entry = Entry.newPage();
    _entries.add(entry);
    final order = _entries.map((entry) => entry.id).toList();
    final write = _enqueue(() async {
      await _entriesBox.put(entry.id, entry.toJson());
      await _metaBox.put(_kOrderKey, order);
      notifyListeners();
    });
    return write.then((_) => entry);
  }

  /// Applies [mutate] to the entry and persists the result.
  Future<void> updateEntry(String id, void Function(Entry e) mutate) {
    final i = indexOfEntry(id);
    if (i < 0) return Future<void>.value();
    mutate(_entries[i]);
    _entries[i].modifiedAt = DateTime.now();
    _entries[i].revision += 1;
    final json = _entries[i].toJson();
    return _enqueue(() async {
      await _entriesBox.put(id, json);
      notifyListeners();
    });
  }

  /// Deletes an entry and all of its assets.
  Future<void> deleteEntry(String id) {
    final i = indexOfEntry(id);
    if (i < 0) return Future<void>.value();
    _entries.removeAt(i);
    final assetIds = _assetIdsForEntry(id);
    final order = _entries.map((entry) => entry.id).toList();
    return _enqueue(() async {
      await _entriesBox.delete(id);
      for (final assetId in assetIds) {
        await _assetsBox.delete(assetId);
      }
      await _metaBox.put(_kOrderKey, order);
      notifyListeners();
    });
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _writeQueue.then((_) => operation());
    _writeQueue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }

  /// Waits for all queued writes and Hive's pending disk operations.
  Future<void> flush() async {
    await _writeQueue;
    await _entriesBox.flush();
    await _assetsBox.flush();
    await _metaBox.flush();
    await _checkpointsBox.flush();
  }

  /// Schedules a five-minute dirty-session recovery point. The timer is
  /// deliberately independent from normal saves so rapid transforms do not
  /// generate many snapshots.
  void scheduleCheckpoint(String entryId) {
    _checkpointTimers.remove(entryId)?.cancel();
    _checkpointTimers[entryId] = Timer(const Duration(minutes: 5), () {
      _checkpointTimers.remove(entryId);
      unawaited(createCheckpoint(entryId));
    });
  }

  /// Persists a restorable local checkpoint and prunes snapshots older than a
  /// week once more than the latest twenty are present.
  Future<void> createCheckpoint(String entryId) {
    final index = indexOfEntry(entryId);
    if (index < 0) return Future<void>.value();
    final now = DateTime.now();
    final checkpoint = EntryCheckpoint(
      id: '$entryId:${now.microsecondsSinceEpoch}',
      entryId: entryId,
      createdAt: now,
      entry: Entry.fromJson(_entries[index].toJson()),
    );
    return _enqueue(() async {
      await _checkpointsBox.put(checkpoint.id, checkpoint.toJson());
      await _pruneCheckpoints(entryId, now);
    });
  }

  List<EntryCheckpoint> checkpointsFor(String entryId) {
    final checkpoints = <EntryCheckpoint>[];
    for (final key in _checkpointsBox.keys.whereType<String>()) {
      final raw = _checkpointsBox.get(key);
      if (raw is! Map) continue;
      try {
        final checkpoint = EntryCheckpoint.fromJson(
          key,
          Map<String, dynamic>.from(raw),
        );
        if (checkpoint.entryId == entryId) checkpoints.add(checkpoint);
      } catch (_) {
        // Ignore a corrupt recovery point without risking the current entry.
      }
    }
    checkpoints.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(checkpoints);
  }

  Future<void> restoreCheckpoint(String checkpointId) {
    final raw = _checkpointsBox.get(checkpointId);
    if (raw is! Map) return Future<void>.value();
    final checkpoint = EntryCheckpoint.fromJson(
      checkpointId,
      Map<String, dynamic>.from(raw),
    );
    final index = indexOfEntry(checkpoint.entryId);
    if (index < 0) return Future<void>.value();
    _entries[index] = checkpoint.entry;
    _entries[index].modifiedAt = DateTime.now();
    _entries[index].revision += 1;
    final json = _entries[index].toJson();
    return _enqueue(() async {
      await _entriesBox.put(checkpoint.entryId, json);
      notifyListeners();
    });
  }

  Future<void> _pruneCheckpoints(String entryId, DateTime now) async {
    final checkpoints = checkpointsFor(entryId);
    final weekAgo = now.subtract(const Duration(days: 7));
    for (var index = 0; index < checkpoints.length; index++) {
      final checkpoint = checkpoints[index];
      if (index >= 20 && checkpoint.createdAt.isBefore(weekAgo)) {
        await _checkpointsBox.delete(checkpoint.id);
      }
    }
  }

  /// Stores [data] as an asset belonging to [entryId] and returns the new
  /// asset id.
  Future<String> addAsset(
    String entryId,
    AssetKind kind,
    String mime,
    List<int> data,
  ) async {
    final id = _uuid.v4();
    await _assetsBox.put(
      id,
      AssetRecord(
        entryId: entryId,
        kind: kind,
        mime: mime,
        data: data,
      ).toJson(),
    );
    return id;
  }

  /// Returns the raw bytes of an asset, or null if it doesn't exist.
  Uint8List? getAsset(String id) {
    final raw = _assetsBox.get(id);
    if (raw is Map) {
      return Uint8List.fromList(
        AssetRecord.fromJson(Map<String, dynamic>.from(raw)).data,
      );
    }
    return null;
  }

  /// The mime type of an asset, or null if it doesn't exist.
  String? getAssetMime(String id) {
    final raw = _assetsBox.get(id);
    if (raw is Map) {
      return AssetRecord.fromJson(Map<String, dynamic>.from(raw)).mime;
    }
    return null;
  }

  void removeAsset(String id) => _assetsBox.delete(id);

  void removeAssetIfUnreferenced(
    String assetId,
    Iterable<ContentBlock> remainingBlocks,
  ) {
    final stillReferenced = remainingBlocks.any(
      (block) => block.type == BlockType.image && block.assetId == assetId,
    );
    if (!stillReferenced) removeAsset(assetId);
  }

  List<dynamic> _assetIdsForEntry(String entryId) {
    return _assetsBox.keys.where((k) {
      final raw = _assetsBox.get(k);
      return raw is Map &&
          AssetRecord.fromJson(Map<String, dynamic>.from(raw)).entryId ==
              entryId;
    }).toList();
  }

  @override
  void dispose() {
    for (final timer in _checkpointTimers.values) {
      timer.cancel();
    }
    _checkpointTimers.clear();
    super.dispose();
  }
}
