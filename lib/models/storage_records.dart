import 'entry.dart';
import 'asset_kind.dart';

/// A binary asset owned by a journal document.
class AssetRecord {
  AssetRecord({
    required this.entryId,
    required this.kind,
    required this.mime,
    required this.data,
  });

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

/// A restorable local document snapshot.
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
