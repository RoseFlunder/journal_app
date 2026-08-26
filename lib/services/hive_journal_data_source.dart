import 'package:hive_flutter/hive_flutter.dart';

/// Raw Hive access for the journal data layer.
///
/// This service owns box names, box handles, and serialized values. Domain
/// conversion and in-memory notifications stay in repositories/store code.
class HiveJournalDataSource {
  static const _entriesBoxName = 'entries';
  static const _assetsBoxName = 'assets';
  static const _metaBoxName = 'meta';
  static const _checkpointsBoxName = 'entryCheckpoints';
  static const _templatesBoxName = 'journalTemplates';

  late Box<dynamic> _entries;
  late Box<dynamic> _assets;
  late Box<dynamic> _meta;
  late Box<dynamic> _checkpoints;
  late Box<dynamic> _templates;
  Future<void> _writeQueue = Future<void>.value();

  Future<void> open() async {
    _entries = await Hive.openBox<dynamic>(_entriesBoxName);
    _assets = await Hive.openBox<dynamic>(_assetsBoxName);
    _meta = await Hive.openBox<dynamic>(_metaBoxName);
    _checkpoints = await Hive.openBox<dynamic>(_checkpointsBoxName);
    _templates = await Hive.openBox<dynamic>(_templatesBoxName);
  }

  dynamic readEntry(String id) => _entries.get(id);

  Iterable<dynamic> get entryKeys => _entries.keys;

  Future<void> writeEntry(String id, dynamic value) => _entries.put(id, value);

  Future<void> deleteEntry(String id) => _entries.delete(id);

  dynamic readMeta(String key) => _meta.get(key);

  Future<void> writeMeta(String key, dynamic value) => _meta.put(key, value);

  dynamic readAsset(String id) => _assets.get(id);

  Iterable<dynamic> get assetKeys => _assets.keys;

  Future<void> writeAsset(String id, dynamic value) => _assets.put(id, value);

  Future<void> deleteAsset(String id) => _assets.delete(id);

  dynamic readCheckpoint(String id) => _checkpoints.get(id);

  Iterable<dynamic> get checkpointKeys => _checkpoints.keys;

  Future<void> writeCheckpoint(String id, dynamic value) =>
      _checkpoints.put(id, value);

  Future<void> deleteCheckpoint(String id) => _checkpoints.delete(id);

  dynamic readTemplate(String id) => _templates.get(id);

  Iterable<dynamic> get templateKeys => _templates.keys;

  Future<void> writeTemplate(String id, dynamic value) =>
      _templates.put(id, value);

  Future<void> deleteTemplate(String id) => _templates.delete(id);

  Future<void> enqueue(Future<void> Function() operation) {
    final result = _writeQueue.then((_) => operation());
    _writeQueue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }

  Future<void> flush() async {
    await _writeQueue;
    await _entries.flush();
    await _assets.flush();
    await _meta.flush();
    await _checkpoints.flush();
    await _templates.flush();
  }
}
