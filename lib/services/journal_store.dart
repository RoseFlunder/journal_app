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

  static const _uuid = Uuid();

  late Box _entriesBox;
  late Box _assetsBox;
  late Box _metaBox;

  List<Entry> _entries = [];
  bool _loaded = false;
  Future<void> _writeQueue = Future<void>.value();

  /// The entries in page order. Index 0 of this list is page 1 (after TOC).
  List<Entry> get entries => List.unmodifiable(_entries);

  bool get isLoaded => _loaded;

  /// Opens the Hive boxes and loads all entries.
  Future<void> init() async {
    _entriesBox = await Hive.openBox(_boxEntries);
    _assetsBox = await Hive.openBox(_boxAssets);
    _metaBox = await Hive.openBox(_boxMeta);
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
}
