import 'dart:collection';

import '../models/asset_kind.dart';
import '../models/document.dart';

/// The relationship between two immutable synchronization clocks.
enum SyncRelation { equal, before, after, concurrent }

/// A compact version vector used to detect offline edits made on different
/// devices. The map is copied and exposed as an unmodifiable view so sync
/// metadata cannot be changed through an alias.
class SyncVersionVector {
  SyncVersionVector([Map<String, int> values = const <String, int>{}])
      : values = UnmodifiableMapView(<String, int>{
          for (final entry in values.entries)
            if (entry.value > 0) entry.key: entry.value,
        });

  final Map<String, int> values;

  int operator [](String deviceId) => values[deviceId] ?? 0;

  SyncVersionVector increment(String deviceId) {
    final next = <String, int>{...values};
    next[deviceId] = (next[deviceId] ?? 0) + 1;
    return SyncVersionVector(next);
  }

  SyncVersionVector merge(SyncVersionVector other) {
    final next = <String, int>{...values};
    for (final entry in other.values.entries) {
      next[entry.key] = (next[entry.key] ?? 0) > entry.value
          ? next[entry.key]!
          : entry.value;
    }
    return SyncVersionVector(next);
  }

  SyncRelation relationTo(SyncVersionVector other) {
    var thisAtLeast = true;
    var otherAtLeast = true;
    final devices = <String>{...values.keys, ...other.values.keys};
    for (final device in devices) {
      final left = this[device];
      final right = other[device];
      if (left < right) thisAtLeast = false;
      if (right < left) otherAtLeast = false;
    }
    if (thisAtLeast && otherAtLeast) return SyncRelation.equal;
    if (thisAtLeast) return SyncRelation.after;
    if (otherAtLeast) return SyncRelation.before;
    return SyncRelation.concurrent;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{...values};

  factory SyncVersionVector.fromJson(Object? raw) {
    if (raw is! Map) return SyncVersionVector();
    return SyncVersionVector(<String, int>{
      for (final entry in raw.entries)
        if (entry.key is String && entry.value is num)
          entry.key as String: (entry.value as num).toInt(),
    });
  }

  @override
  bool operator ==(Object other) =>
      other is SyncVersionVector && _mapsEqual(values, other.values);

  @override
  int get hashCode => values.entries.fold<int>(0, (hash, entry) =>
      hash ^ Object.hash(entry.key, entry.value));
}

/// A deterministic tie-breaker for concurrent versions. Version vectors make
/// causality authoritative; this stamp is only used when two versions are
/// genuinely concurrent.
class SyncMutationStamp implements Comparable<SyncMutationStamp> {
  const SyncMutationStamp({
    required this.modifiedAt,
    required this.deviceId,
    required this.counter,
  });

  final DateTime modifiedAt;
  final String deviceId;
  final int counter;

  @override
  int compareTo(SyncMutationStamp other) {
    final byTime = modifiedAt.compareTo(other.modifiedAt);
    if (byTime != 0) return byTime;
    final byDevice = deviceId.compareTo(other.deviceId);
    if (byDevice != 0) return byDevice;
    return counter.compareTo(other.counter);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'modifiedAt': modifiedAt.toUtc().toIso8601String(),
        'deviceId': deviceId,
        'counter': counter,
      };

  factory SyncMutationStamp.fromJson(Object? raw) {
    if (raw is! Map) {
      return SyncMutationStamp(
        modifiedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        deviceId: '',
        counter: 0,
      );
    }
    return SyncMutationStamp(
      modifiedAt: DateTime.tryParse(raw['modifiedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      deviceId: raw['deviceId'] as String? ?? '',
      counter: (raw['counter'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Metadata needed to fetch a referenced binary asset without exposing raw
/// Hive records to synchronization callers.
class SyncedAssetDescriptor {
  const SyncedAssetDescriptor({
    required this.id,
    required this.ownerId,
    required this.kind,
    required this.mime,
    required this.sha256,
  });

  final String id;
  final String ownerId;
  final AssetKind kind;
  final String mime;
  final String sha256;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'ownerId': ownerId,
        'kind': kind.name,
        'mime': mime,
        'sha256': sha256,
      };

  factory SyncedAssetDescriptor.fromJson(Map<String, dynamic> json) =>
      SyncedAssetDescriptor(
        id: json['id'] as String,
        ownerId: json['ownerId'] as String? ?? '',
        kind: AssetKind.values.firstWhere(
          (value) => value.name == json['kind'],
          orElse: () => AssetKind.image,
        ),
        mime: json['mime'] as String? ?? 'application/octet-stream',
        sha256: json['sha256'] as String? ?? '',
      );
}

/// A complete immutable page head, including tombstones for deleted pages.
class SyncedDocumentHead {
  SyncedDocumentHead({
    required this.documentId,
    required this.deviceId,
    required this.vector,
    required this.stamp,
    required this.document,
    required this.deletedAt,
    this.driveFileId,
    Iterable<SyncedAssetDescriptor> assets = const <SyncedAssetDescriptor>[],
  }) : assets = List<SyncedAssetDescriptor>.unmodifiable(assets);

  final String documentId;
  final String deviceId;
  final SyncVersionVector vector;
  final SyncMutationStamp stamp;
  final EntryDocument? document;
  final DateTime? deletedAt;
  final String? driveFileId;
  final List<SyncedAssetDescriptor> assets;

  bool get isDeleted => deletedAt != null || document == null;

  SyncedDocumentHead copyWith({
    Object? driveFileId = _unset,
    SyncVersionVector? vector,
    SyncMutationStamp? stamp,
    Object? document = _unset,
    Object? deletedAt = _unset,
    List<SyncedAssetDescriptor>? assets,
  }) =>
      SyncedDocumentHead(
        documentId: documentId,
        deviceId: deviceId,
        vector: vector ?? this.vector,
        stamp: stamp ?? this.stamp,
        document: identical(document, _unset)
            ? this.document
            : document as EntryDocument?,
        deletedAt: identical(deletedAt, _unset)
            ? this.deletedAt
            : deletedAt as DateTime?,
        driveFileId: identical(driveFileId, _unset)
            ? this.driveFileId
            : driveFileId as String?,
        assets: List<SyncedAssetDescriptor>.unmodifiable(
          assets ?? this.assets,
        ),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schemaVersion': 1,
        'entityType': 'document',
        'documentId': documentId,
        'deviceId': deviceId,
        'vector': vector.toJson(),
        'stamp': stamp.toJson(),
        'document': document?.toJson(),
        'deletedAt': deletedAt?.toUtc().toIso8601String(),
        'assets': assets.map((asset) => asset.toJson()).toList(),
      };

  factory SyncedDocumentHead.fromJson(Map<String, dynamic> json) {
    final rawAssets = json['assets'];
    return SyncedDocumentHead(
      documentId: json['documentId'] as String,
      deviceId: json['deviceId'] as String? ?? '',
      vector: SyncVersionVector.fromJson(json['vector']),
      stamp: SyncMutationStamp.fromJson(json['stamp']),
      document: json['document'] is Map
          ? EntryDocument.fromJson(
              Map<String, dynamic>.from(json['document'] as Map),
            )
          : null,
      deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? ''),
      assets: rawAssets is List
          ? List<SyncedAssetDescriptor>.unmodifiable(
              rawAssets
                  .whereType<Map<Object?, Object?>>()
                  .map(
                    (asset) => SyncedAssetDescriptor.fromJson(
                      Map<String, dynamic>.from(asset),
                    ),
                  ),
            )
          : const <SyncedAssetDescriptor>[],
    );
  }
}

/// Versioned page ordering. Missing IDs are appended during a merge so a
/// concurrent reorder cannot hide a newly-created page.
class SyncedCollectionHead {
  SyncedCollectionHead({
    required this.deviceId,
    required this.vector,
    required this.stamp,
    required Iterable<String> documentIds,
    this.driveFileId,
  }) : documentIds = List.unmodifiable(documentIds);

  final String deviceId;
  final SyncVersionVector vector;
  final SyncMutationStamp stamp;
  final List<String> documentIds;
  final String? driveFileId;

  SyncedCollectionHead copyWith({
    String? deviceId,
    SyncVersionVector? vector,
    SyncMutationStamp? stamp,
    Iterable<String>? documentIds,
    Object? driveFileId = _unset,
  }) => SyncedCollectionHead(
        deviceId: deviceId ?? this.deviceId,
        vector: vector ?? this.vector,
        stamp: stamp ?? this.stamp,
        documentIds: documentIds ?? this.documentIds,
        driveFileId: identical(driveFileId, _unset)
            ? this.driveFileId
            : driveFileId as String?,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schemaVersion': 1,
        'entityType': 'collection',
        'deviceId': deviceId,
        'vector': vector.toJson(),
        'stamp': stamp.toJson(),
        'documentIds': documentIds,
      };

  factory SyncedCollectionHead.fromJson(Map<String, dynamic> json) =>
      SyncedCollectionHead(
        deviceId: json['deviceId'] as String? ?? '',
        vector: SyncVersionVector.fromJson(json['vector']),
        stamp: SyncMutationStamp.fromJson(json['stamp']),
        documentIds: (json['documentIds'] as List<dynamic>? ?? const [])
            .whereType<String>(),
      );
}

/// Drive file metadata used by the gateway; it intentionally contains no
/// Google SDK types.
class DriveSyncRecord {
  DriveSyncRecord({
    required this.fileId,
    required this.name,
    required this.mimeType,
    required Map<String, String> properties,
    required this.modifiedAt,
    this.size,
  }) : properties = Map<String, String>.unmodifiable(properties);

  final String fileId;
  final String name;
  final String mimeType;
  final Map<String, String> properties;
  final DateTime? modifiedAt;
  final int? size;
}

const _unset = Object();

bool _mapsEqual(Map<String, int> left, Map<String, int> right) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) return false;
  }
  return true;
}
