import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/document.dart';
import '../models/entry.dart';
import '../models/storage_records.dart';
import '../models/template.dart';
import 'journal_archive.dart';
import 'hive_journal_data_source.dart';

export '../models/storage_records.dart'
    show AssetKind, AssetRecord, EntryCheckpoint;

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
  static const _kRecentColorValues = 'colorPickerRecent';
  static const _kFavoriteColorValues = 'colorPickerFavorites';

  static const _uuid = Uuid();

  final HiveJournalDataSource _storage = HiveJournalDataSource();
  List<Entry> _entries = [];
  List<int> _recentColorValues = <int>[];
  Set<int> _favoriteColorValues = <int>{};
  bool _loaded = false;
  final Map<String, Timer> _checkpointTimers = {};
  final Set<Future<void> Function()> _flushHooks = {};

  /// The entries in page order. Index 0 of this list is page 1 (after TOC).
  List<Entry> get entries => List.unmodifiable(_entries);

  List<int> get recentColorValues => List.unmodifiable(_recentColorValues);

  Set<int> get favoriteColorValues => Set.unmodifiable(_favoriteColorValues);

  bool get isLoaded => _loaded;

  /// Registers an in-memory editor flush that must complete before storage
  /// is flushed. This keeps app lifecycle persistence ordered when the app
  /// shell and an active editor observe the same lifecycle event.
  void addFlushHook(Future<void> Function() hook) => _flushHooks.add(hook);

  void removeFlushHook(Future<void> Function() hook) =>
      _flushHooks.remove(hook);

  /// Opens the Hive boxes and loads all entries.
  Future<void> init() async {
    await _storage.open();
    _loadColorPreferences();
    _load();
  }

  void _loadColorPreferences() {
    final recent = _storage.readMeta(_kRecentColorValues);
    _recentColorValues = recent is List
        ? recent.whereType<num>().map((value) => value.toInt()).take(8).toList()
        : <int>[];
    final favorites = _storage.readMeta(_kFavoriteColorValues);
    _favoriteColorValues = favorites is List
        ? favorites
              .whereType<num>()
              .map((value) => value.toInt())
              .take(12)
              .toSet()
        : <int>{};
  }

  /// Persists the user's color-picker recents and favorites independently of
  /// journal documents so they are available on every page.
  Future<void> updateColorPreferences({
    List<int>? recent,
    Set<int>? favorites,
  }) {
    if (recent != null) {
      _recentColorValues = recent.take(8).toList(growable: false);
    }
    if (favorites != null) {
      _favoriteColorValues = favorites.take(12).toSet();
    }
    return _enqueue(() async {
      if (recent != null) {
        await _storage.writeMeta(_kRecentColorValues, _recentColorValues);
      }
      if (favorites != null) {
        await _storage.writeMeta(
          _kFavoriteColorValues,
          _favoriteColorValues.toList(growable: false),
        );
      }
      notifyListeners();
    });
  }

  void _load() {
    final rawOrder = _storage.readMeta(_kOrderKey);
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
        _storage.entryKeys
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
    final raw = _storage.readEntry(id);
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
  Future<Entry> addEntry({String title = ''}) {
    final entry = Entry.newPage()..title = title.trim();
    _entries.add(entry);
    final order = _entries.map((entry) => entry.id).toList();
    final write = _enqueue(() async {
      await _storage.writeEntry(entry.id, entry.toJson());
      await _storage.writeMeta(_kOrderKey, order);
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
      await _storage.writeEntry(id, json);
      notifyListeners();
    });
  }

  /// Updates the in-memory entry without enqueueing a disk write.
  ///
  /// Editors use this for responsive previews between transaction commits.
  /// The next normal update persists the complete current entry.
  void previewEntry(String id, void Function(Entry e) mutate) {
    final index = indexOfEntry(id);
    if (index < 0) return;
    mutate(_entries[index]);
  }

  /// Deletes an entry and all of its assets.
  Future<void> deleteEntry(String id) {
    final i = indexOfEntry(id);
    if (i < 0) return Future<void>.value();
    _entries.removeAt(i);
    final order = _entries.map((entry) => entry.id).toList();
    return _enqueue(() async {
      await _storage.deleteEntry(id);
      await _storage.writeMeta(_kOrderKey, order);
      notifyListeners();
    }).then((_) => collectUnreferencedAssets());
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    return _storage.enqueue(operation);
  }

  /// Waits for all queued writes and Hive's pending disk operations.
  Future<void> flush() async {
    for (final hook in List<Future<void> Function()>.from(_flushHooks)) {
      await hook();
    }
    await _storage.flush();
  }

  /// Schedules a five-minute dirty-session recovery point. The timer is
  /// deliberately independent from normal saves so rapid transforms do not
  /// generate many snapshots.
  void scheduleCheckpoint(String entryId) {
    if (_checkpointTimers.containsKey(entryId)) return;
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
      await _storage.writeCheckpoint(checkpoint.id, checkpoint.toJson());
      await _pruneCheckpoints(entryId, now);
    });
  }

  List<EntryCheckpoint> checkpointsFor(String entryId) {
    final checkpoints = <EntryCheckpoint>[];
    for (final key in _storage.checkpointKeys.whereType<String>()) {
      final raw = _storage.readCheckpoint(key);
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
    final raw = _storage.readCheckpoint(checkpointId);
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
      await _storage.writeEntry(checkpoint.entryId, json);
      notifyListeners();
    });
  }

  Future<void> _pruneCheckpoints(String entryId, DateTime now) async {
    final checkpoints = checkpointsFor(entryId);
    final weekAgo = now.subtract(const Duration(days: 7));
    for (var index = 0; index < checkpoints.length; index++) {
      final checkpoint = checkpoints[index];
      if (index >= 20 && checkpoint.createdAt.isBefore(weekAgo)) {
        await _storage.deleteCheckpoint(checkpoint.id);
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
    await _storage.writeAsset(
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
    final raw = _storage.readAsset(id);
    if (raw is Map) {
      return Uint8List.fromList(
        AssetRecord.fromJson(Map<String, dynamic>.from(raw)).data,
      );
    }
    return null;
  }

  /// The mime type of an asset, or null if it doesn't exist.
  String? getAssetMime(String id) {
    final raw = _storage.readAsset(id);
    if (raw is Map) {
      return AssetRecord.fromJson(Map<String, dynamic>.from(raw)).mime;
    }
    return null;
  }

  void removeAsset(String id) => _storage.deleteAsset(id);

  void removeAssetIfUnreferenced(
    String assetId,
    Iterable<ContentBlock> remainingBlocks,
  ) {
    final stillReferenced = remainingBlocks.any(
      (block) => block.type == BlockType.image && block.assetId == assetId,
    );
    if (!stillReferenced) removeAsset(assetId);
  }

  /// Removes only assets that are not referenced by a live document,
  /// checkpoint, template, or retained clipboard payload. Asset bytes are
  /// immutable, so this is safe to run after destructive document operations.
  Future<void> collectUnreferencedAssets() async {
    final referenced = <String>{};
    void collectBlocks(Iterable<ContentBlock> blocks) {
      for (final block in blocks) {
        if (block.assetId != null) referenced.add(block.assetId!);
        if (block.stickerId != null) referenced.add(block.stickerId!);
      }
    }

    for (final entry in _entries) {
      collectBlocks(entry.blocks);
    }
    for (final key in _storage.checkpointKeys) {
      final raw = _storage.readCheckpoint(key.toString());
      if (raw is! Map || raw['entry'] is! Map) continue;
      try {
        collectBlocks(
          Entry.fromJson(Map<String, dynamic>.from(raw['entry'] as Map)).blocks,
        );
      } catch (_) {
        // A corrupt checkpoint must not prevent cleanup of known-unused data.
      }
    }
    for (final key in _storage.templateKeys) {
      final raw = _storage.readTemplate(key.toString());
      if (raw is! Map || raw['document'] is! Map) continue;
      try {
        collectBlocks(
          EntryDocument.fromJson(
            Map<String, dynamic>.from(raw['document'] as Map),
          ).toEntry().blocks,
        );
      } catch (_) {
        // Ignore a corrupt template record and leave its media in place.
      }
    }
    for (final key in _storage.assetKeys.toList()) {
      if (!referenced.contains(key)) {
        await _storage.deleteAsset(key.toString());
      }
    }
  }

  List<JournalTemplate> get templates {
    final result = <JournalTemplate>[];
    for (final key in _storage.templateKeys.whereType<String>()) {
      final raw = _storage.readTemplate(key);
      if (raw is! Map) continue;
      try {
        result.add(JournalTemplate.fromJson(Map<String, dynamic>.from(raw)));
      } catch (_) {
        // Keep unrelated templates available if one record is malformed.
      }
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(result);
  }

  Future<void> saveTemplate(JournalTemplate template) =>
      _enqueue(() => _storage.writeTemplate(template.id, template.toJson()));

  Future<void> deleteTemplate(String id) =>
      _enqueue(() => _storage.deleteTemplate(id));

  /// Creates a portable `.cozyjournal` backup for one entry. The archive is
  /// self-contained: referenced media bytes, the document snapshot, and all
  /// reusable local templates are included.
  JournalArchive? archiveForEntry(String entryId) {
    final index = indexOfEntry(entryId);
    if (index < 0) return null;
    final referenced = <String>{};
    for (final block in _entries[index].blocks) {
      if (block.assetId != null) referenced.add(block.assetId!);
    }
    final assets = <ArchiveAsset>[];
    for (final id in referenced) {
      final raw = _storage.readAsset(id);
      if (raw is! Map) continue;
      final asset = AssetRecord.fromJson(Map<String, dynamic>.from(raw));
      assets.add(
        ArchiveAsset(
          id: id,
          mime: asset.mime,
          bytes: Uint8List.fromList(asset.data),
        ),
      );
    }
    return JournalArchive(
      document: EntryDocument.fromEntry(_entries[index]),
      assets: assets,
      templates: templates,
    );
  }

  /// Imports an archive as a new entry. IDs are remapped so importing the
  /// same backup twice never aliases its assets or group references.
  Future<Entry> importArchive(JournalArchive archive) async {
    final source = archive.document.toEntry();
    final entry = await addEntry(title: source.title);
    final assetIds = <String, String>{};
    for (final asset in archive.assets) {
      assetIds[asset.id] = await addAsset(
        entry.id,
        asset.mime.startsWith('audio/') ? AssetKind.audio : AssetKind.image,
        asset.mime,
        asset.bytes,
      );
    }
    final blocks = source.blocks.map((block) {
      final copy = block.clone();
      if (copy.assetId != null) copy.assetId = assetIds[copy.assetId!];
      return copy;
    }).toList();
    await updateEntry(entry.id, (target) {
      target
        ..blocks = blocks
        ..board = source.board
        ..view = source.view
        ..music = source.music;
    });
    for (final template in archive.templates) {
      await saveTemplate(template);
    }
    return entries.firstWhere((item) => item.id == entry.id);
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
