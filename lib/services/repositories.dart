import 'dart:typed_data';

import '../models/document.dart';
import '../models/template.dart';
import 'journal_store.dart';

/// Repository boundary used by the editor. UI code can depend on this
/// contract while a future sync implementation replaces the Hive adapter.
abstract interface class JournalRepository {
  Future<void> init();

  List<EntryDocument> get documents;

  Future<EntryDocument> createDocument({String title});

  Future<void> saveDocument(EntryDocument document);

  Future<void> deleteDocument(String id);

  Future<void> flush();
}

/// Immutable asset storage boundary. Asset bytes are never modified in
/// place; image editing stores crop/adjustment metadata on the node instead.
abstract interface class AssetRepository {
  Future<String> putAsset(
    String ownerId,
    AssetKind kind,
    String mime,
    List<int> bytes,
  );

  Uint8List? readAsset(String id);

  String? assetMime(String id);

  Future<void> collectUnreferencedAssets();
}

abstract interface class CheckpointRepository {
  List<EntryCheckpoint> checkpointsFor(String documentId);

  Future<void> createCheckpoint(String documentId);

  Future<void> restoreCheckpoint(String checkpointId);
}

abstract interface class TemplateRepository {
  List<JournalTemplate> get templates;

  Future<void> saveTemplate(JournalTemplate template);

  Future<void> deleteTemplate(String id);
}

/// Hive-backed repository facade. [JournalStore] remains available to the
/// existing navigation shell, while new editor features can depend only on
/// these repository interfaces.
class HiveJournalRepository
    implements
        JournalRepository,
        AssetRepository,
        CheckpointRepository,
        TemplateRepository {
  HiveJournalRepository(this.store);

  final JournalStore store;

  @override
  Future<void> init() => store.init();

  @override
  List<EntryDocument> get documents =>
      store.entries.map(EntryDocument.fromEntry).toList(growable: false);

  @override
  Future<EntryDocument> createDocument({String title = ''}) async =>
      EntryDocument.fromEntry(await store.addEntry(title: title));

  @override
  Future<void> saveDocument(EntryDocument document) =>
      store.updateEntry(document.id, (entry) {
        final next = document.toEntry();
        entry
          ..title = next.title
          ..blocks = next.blocks
          ..board = next.board
          ..view = next.view
          ..music = next.music
          ..revision = next.revision
          ..schemaVersion = next.schemaVersion;
      });

  @override
  Future<void> deleteDocument(String id) => store.deleteEntry(id);

  @override
  Future<void> flush() => store.flush();

  @override
  Future<String> putAsset(
    String ownerId,
    AssetKind kind,
    String mime,
    List<int> bytes,
  ) => store.addAsset(ownerId, kind, mime, bytes);

  @override
  Uint8List? readAsset(String id) => store.getAsset(id);

  @override
  String? assetMime(String id) => store.getAssetMime(id);

  @override
  Future<void> collectUnreferencedAssets() => store.collectUnreferencedAssets();

  @override
  List<EntryCheckpoint> checkpointsFor(String documentId) =>
      store.checkpointsFor(documentId);

  @override
  Future<void> createCheckpoint(String documentId) =>
      store.createCheckpoint(documentId);

  @override
  Future<void> restoreCheckpoint(String checkpointId) =>
      store.restoreCheckpoint(checkpointId);

  @override
  List<JournalTemplate> get templates => store.templates;

  @override
  Future<void> saveTemplate(JournalTemplate template) =>
      store.saveTemplate(template);

  @override
  Future<void> deleteTemplate(String id) => store.deleteTemplate(id);
}
