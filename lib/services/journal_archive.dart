import 'dart:convert';
import 'dart:typed_data';

import '../models/document.dart';

/// One immutable media file embedded in a `.cozyjournal` archive.
class ArchiveAsset {
  ArchiveAsset({required this.id, required this.mime, required this.bytes});

  final String id;
  final String mime;
  final Uint8List bytes;

  Map<String, dynamic> toJson() => {
    'id': id,
    'mime': mime,
    'bytes': base64Encode(bytes),
  };

  factory ArchiveAsset.fromJson(Map<String, dynamic> json) => ArchiveAsset(
    id: json['id'] as String,
    mime: json['mime'] as String? ?? 'application/octet-stream',
    bytes: base64Decode(json['bytes'] as String? ?? ''),
  );
}

class JournalArchive {
  const JournalArchive({
    required this.document,
    this.assets = const [],
  });

  static const format = 'cozyjournal';
  static const schemaVersion = 1;

  final EntryDocument document;
  final List<ArchiveAsset> assets;

  Uint8List encode() {
    final envelope = <String, dynamic>{
      'format': format,
      'schemaVersion': schemaVersion,
      'document': document.toJson(),
      'assets': assets.map((asset) => asset.toJson()).toList(),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
  }

  factory JournalArchive.decode(Uint8List bytes) {
    final raw = jsonDecode(utf8.decode(bytes));
    if (raw is! Map || raw['format'] != format) {
      throw const FormatException('Not a Cozy Journal archive');
    }
    final version = (raw['schemaVersion'] as num?)?.toInt();
    if (version != schemaVersion) {
      throw FormatException('Unsupported archive schema: $version');
    }
    final document = raw['document'];
    if (document is! Map) {
      throw const FormatException('Archive is missing its document');
    }
    final assets = (raw['assets'] as List<dynamic>? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map((asset) => ArchiveAsset.fromJson(Map<String, dynamic>.from(asset)))
        .toList(growable: false);
    return JournalArchive(
      document: EntryDocument.fromJson(Map<String, dynamic>.from(document)),
      assets: assets,
    );
  }
}
