import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models/document.dart';
import '../models/asset_kind.dart';
import '../models/checkpoint.dart';
import '../models/view_state.dart';
import 'journal_archive.dart';

export 'music_catalog_repository.dart'
    show DisabledMusicCatalogRepository, MusicCatalogRepository;

// Capability-owned value type; storage record classes remain private to the
// Hive adapters while repositories may still describe asset kind in a method
// contract.
export '../models/asset_kind.dart' show AssetKind;
export '../models/checkpoint.dart' show CheckpointInfo;

/// Immutable identity for a content-addressed asset.  The digest is the
/// durable ID; ownership belongs to document references rather than to the
/// blob itself.
class AssetDescriptor {
  const AssetDescriptor({
    required this.id,
    required this.kind,
    required this.mime,
    required this.byteLength,
    required this.sha256,
    this.width,
    this.height,
  });

  final String id;
  final AssetKind kind;
  final String mime;
  final int byteLength;
  final String sha256;
  final int? width;
  final int? height;
}

/// Verified immutable asset bytes returned by the storage capability.
class AssetBlob {
  AssetBlob({required this.descriptor, required List<int> bytes})
      : bytes = List<int>.unmodifiable(bytes);

  final AssetDescriptor descriptor;
  final List<int> bytes;
}

abstract interface class AssetRepository {
  /// Compatibility bridge for callers that still pass an owner document.
  /// New code should use [putImmutableAsset], because assets are shared blobs.
  @Deprecated('Use putImmutableAsset; asset ownership is no longer persisted.')
  Future<String> putAsset(
    String ownerId,
    AssetKind kind,
    String mime,
    List<int> bytes,
  );

  Uint8List? readAsset(String id);

  String? assetMime(String id);

  Future<void> collectUnreferencedAssets({
    Iterable<String> retainedAssetIds,
  });
}

/// Additive immutable-asset facade. Keeping this as an extension allows
/// third-party and test implementations of the legacy capability to migrate
/// without a flag-day interface break, while the Hive adapter supplies the
/// stronger implementation directly.
extension ImmutableAssetRepository on AssetRepository {
  Future<AssetDescriptor> putImmutableAsset(
    AssetKind kind,
    String mime,
    List<int> bytes,
  ) async {
    final id = await putAsset('', kind, mime, bytes);
    return AssetDescriptor(
      id: id,
      kind: kind,
      mime: mime,
      byteLength: bytes.length,
      sha256: id,
    );
  }

  AssetBlob? readAssetBlob(String id) {
    final bytes = readAsset(id);
    if (bytes == null) return null;
    final digest = sha256.convert(bytes).toString();
    if (digest != id) return null;
    final mime = assetMime(id) ?? 'application/octet-stream';
    return AssetBlob(
      descriptor: AssetDescriptor(
        id: id,
        kind: mime.startsWith('audio/') ? AssetKind.audio : AssetKind.image,
        mime: mime,
        byteLength: bytes.length,
        sha256: digest,
      ),
      bytes: bytes,
    );
  }
}

abstract interface class CheckpointRepository {
  List<CheckpointInfo> checkpointsFor(String documentId);

  void scheduleCheckpoint(String documentId);

  Future<void> createCheckpoint(String documentId);

  Future<void> restoreCheckpoint(String checkpointId);
}

abstract interface class PreferencesRepository {
  List<int> get recentColorValues;

  Set<int> get favoriteColorValues;

  Future<void> updateColorPreferences({List<int>? recent, Set<int>? favorites});
}

/// Device-local editor presentation state. It is intentionally separate from
/// [DocumentRepository] so camera movement cannot create a cloud document edit.
class DocumentViewPreferences {
  const DocumentViewPreferences({this.view, this.gridVisible = false});

  final ViewState? view;
  final bool gridVisible;
}

abstract interface class DocumentViewPreferencesRepository {
  DocumentViewPreferences preferencesFor(String documentId);

  Future<void> savePreferences(
    String documentId,
    DocumentViewPreferences preferences,
  );

  Future<void> clearPreferences(String documentId);
}

/// Persistence hooks shared by the application lifecycle and active editors.
abstract interface class PersistenceRepository {
  void addFlushHook(Future<void> Function() hook);

  void removeFlushHook(Future<void> Function() hook);

  Future<void> flush();
}

/// Archive capability kept separate from document CRUD because it coordinates
/// documents and assets as one portable transfer.
abstract interface class ArchiveRepository {
  JournalArchive? archiveForDocument(String id);

  Future<EntryDocument> importArchive(JournalArchive archive);
}

/// Document-only capability used by the journal navigation shell.
abstract interface class DocumentRepository {
  Future<void> init();

  List<EntryDocument> get documents;

  Stream<void> get changes;

  Future<EntryDocument> createDocument({String title});

  Future<void> saveDocument(EntryDocument document);

  void previewDocument(EntryDocument document);

  Future<void> deleteDocument(String id);
}

/// Narrow repository capabilities passed to feature views and view models.
class JournalRepositories {
  const JournalRepositories({
    required this.documentRepository,
    required this.assetRepository,
    required this.checkpointRepository,
    required this.preferenceRepository,
    required this.persistence,
    required this.archiveRepository,
    this.viewPreferencesRepository,
  });

  final DocumentRepository documentRepository;
  final AssetRepository assetRepository;
  final CheckpointRepository checkpointRepository;
  final PreferencesRepository preferenceRepository;
  final PersistenceRepository persistence;
  final ArchiveRepository archiveRepository;
  final DocumentViewPreferencesRepository? viewPreferencesRepository;

  /// Returns the same capability set with a lifecycle-aware persistence
  /// coordinator. Composition roots use this to ensure editor flush hooks and
  /// application lifecycle flushes share one owner.
  JournalRepositories withPersistence(PersistenceRepository next) =>
      JournalRepositories(
        documentRepository: documentRepository,
        assetRepository: assetRepository,
        checkpointRepository: checkpointRepository,
        preferenceRepository: preferenceRepository,
        persistence: next,
        archiveRepository: archiveRepository,
        viewPreferencesRepository: viewPreferencesRepository,
      );
}
