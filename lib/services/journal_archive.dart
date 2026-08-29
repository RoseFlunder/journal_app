import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import '../models/document.dart';
import 'storage_codec.dart';

/// One immutable media file embedded in a `.cozyjournal` archive. The ID is
/// kept as the document's reference; the archive also carries a hash so an
/// import can convert it to the local content-addressed asset ID safely.
class ArchiveAsset {
  ArchiveAsset({
    required this.id,
    required this.mime,
    required List<int> bytes,
    this.width,
    this.height,
  })
      : bytes = List<int>.unmodifiable(bytes);

  final String id;
  final String mime;
  final List<int> bytes;
  final int? width;
  final int? height;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'mime': mime,
        'byteLength': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
        'width': width,
        'height': height,
      };
}

class JournalArchive {
  JournalArchive({required this.document, Iterable<ArchiveAsset> assets = const []})
      : assets = List<ArchiveAsset>.unmodifiable(assets);

  static const format = 'cozy-bloom-archive';
  static const schemaVersion = 2;
  static const _manifestPath = 'manifest.json';
  static const _maxAssetBytes = 32 * 1024 * 1024;
  static const _maxTotalBytes = 512 * 1024 * 1024;
  static const _maxAssets = 2048;
  static const _maxManifestBytes = 16 * 1024 * 1024;

  final EntryDocument document;
  final List<ArchiveAsset> assets;

  /// Validates the complete archive graph before it is published to storage.
  /// This is also used for archives assembled in memory rather than decoded
  /// from a ZIP file.
  void validate() {
    if (assets.length > _maxAssets) {
      throw const FormatException('Archive contains too many assets');
    }
    var total = 0;
    final ids = <String>{};
    final hashes = <String>{};
    for (final asset in assets) {
      if (asset.id.isEmpty || !ids.add(asset.id) || !_validMime(asset.mime) ||
          asset.bytes.any((byte) => byte < 0 || byte > 255) ||
          _invalidDimension(asset.width) || _invalidDimension(asset.height)) {
        throw const FormatException('Archive asset metadata is invalid');
      }
      if (asset.bytes.length > _maxAssetBytes) {
        throw const FormatException('Archive asset is too large');
      }
      total += asset.bytes.length;
      if (total > _maxTotalBytes) {
        throw const FormatException('Archive assets are too large');
      }
      final hash = sha256.convert(asset.bytes).toString();
      if (!hashes.add(hash)) {
        throw const FormatException('Archive contains duplicate asset bytes');
      }
    }
    JournalDocumentCodec.canonicalDocument(document);
    _validateReferences(document, ids);
  }

  Uint8List encode() {
    validate();
    var total = 0;
    final manifestAssets = <Map<String, dynamic>>[];
    final files = <ArchiveFile>[];
    final paths = <String>{};
    final ids = <String>{};
    for (final asset in assets) {
      if (asset.id.isEmpty || !ids.add(asset.id) || !_validMime(asset.mime) ||
          asset.bytes.any((byte) => byte < 0 || byte > 255) ||
          _invalidDimension(asset.width) || _invalidDimension(asset.height)) {
        throw const FormatException('Archive asset metadata is invalid');
      }
      if (asset.bytes.length > _maxAssetBytes) {
        throw const FormatException('Archive asset is too large');
      }
      total += asset.bytes.length;
      if (total > _maxTotalBytes) {
        throw const FormatException('Archive assets are too large');
      }
      final hash = sha256.convert(asset.bytes).toString();
      final path = 'assets/$hash';
      if (!paths.add(path)) {
        throw const FormatException('Archive contains duplicate asset bytes');
      }
      manifestAssets.add(<String, dynamic>{
        'id': asset.id,
        'mime': asset.mime,
        'byteLength': asset.bytes.length,
        'sha256': hash,
        'path': path,
        'width': asset.width,
        'height': asset.height,
      });
      files.add(ArchiveFile.bytes(path, asset.bytes));
    }
    final manifest = <String, dynamic>{
      'format': format,
      'schemaVersion': schemaVersion,
      'document': JournalDocumentCodec.canonicalDocument(document),
      'assets': manifestAssets,
    };
    final manifestBytes = Uint8List.fromList(utf8.encode(jsonEncode(manifest)));
    if (manifestBytes.length > _maxManifestBytes) {
      throw const FormatException('Archive manifest is too large');
    }
    if (total + manifestBytes.length > _maxTotalBytes) {
      throw const FormatException('Archive uncompressed data is too large');
    }
    files.add(ArchiveFile.bytes(_manifestPath, manifestBytes));
    final archive = Archive();
    for (final file in files) {
      archive.add(file);
    }
    return ZipEncoder().encodeBytes(
      archive,
      level: DeflateLevel.bestSpeed,
      modified: DateTime.utc(2026),
    );
  }

  factory JournalArchive.decode(Uint8List bytes) {
    if (bytes.length > _maxTotalBytes + _maxManifestBytes) {
      throw const FormatException('Archive is too large');
    }
    late final Archive decoded;
    try {
      decoded = ZipDecoder().decodeBytes(bytes, verify: true);
    } catch (error) {
      // Version 1 was a plain JSON envelope. Recognize it explicitly so
      // callers can present an actionable incompatibility message instead
      // of a ZIP parser failure.
      try {
        final legacy = utf8.decode(bytes, allowMalformed: true).trimLeft();
        if (legacy.startsWith('{') && legacy.contains('"cozyjournal"')) {
          throw const FormatException('Unsupported archive schema: 1');
        }
      } catch (legacyError) {
        if (legacyError is FormatException &&
            legacyError.message.startsWith('Unsupported archive schema')) {
          rethrow;
        }
      }
      throw FormatException('Invalid Cozy Bloom archive: $error');
    }
    final names = <String>{};
    var listedBytes = 0;
    for (final file in decoded.files) {
      if (!names.add(file.name)) {
        throw const FormatException('Archive contains duplicate paths');
      }
      if (file.isFile) {
        listedBytes += file.size;
        if (listedBytes > _maxTotalBytes) {
          throw const FormatException('Archive uncompressed data is too large');
        }
      }
    }
    final manifestFile = decoded.find(_manifestPath);
    if (manifestFile == null || !manifestFile.isFile) {
      throw const FormatException('Archive is missing manifest.json');
    }
    final manifestBytes = manifestFile.readBytes();
    if (manifestBytes == null || manifestBytes.length > _maxManifestBytes) {
      throw const FormatException('Archive manifest is invalid');
    }
    if (listedBytes > _maxTotalBytes) {
      throw const FormatException('Archive uncompressed data is too large');
    }
    final raw = jsonDecode(utf8.decode(manifestBytes));
    if (raw is! Map || raw['format'] != format) {
      throw const FormatException('Not a Cozy Bloom archive');
    }
    if (raw['schemaVersion'] != schemaVersion) {
      throw FormatException('Unsupported archive schema: ${raw['schemaVersion']}');
    }
    final documentRaw = raw['document'];
    if (documentRaw is! Map) {
      throw const FormatException('Archive is missing its document');
    }
    final document = JournalDocumentCodec.decodeDocument(documentRaw);
    final assetRaw = raw['assets'];
    if (assetRaw is! List || assetRaw.length > _maxAssets) {
      throw const FormatException('Archive asset manifest is invalid');
    }
    var total = 0;
    final ids = <String>{};
    final paths = <String>{_manifestPath};
    final assets = <ArchiveAsset>[];
    for (final item in assetRaw) {
      if (item is! Map) throw const FormatException('Archive asset descriptor is invalid');
      final descriptor = Map<String, dynamic>.from(item);
      final id = descriptor['id'];
      final mime = descriptor['mime'];
      final path = descriptor['path'];
      final expectedHash = descriptor['sha256'];
      final expectedLength = descriptor['byteLength'];
      final width = descriptor['width'];
      final height = descriptor['height'];
      if (id is! String || id.isEmpty || !ids.add(id) ||
          mime is! String || !_validMime(mime) || path is! String ||
          expectedHash is! String || expectedHash.length != 64 ||
          expectedLength is! num || !expectedLength.isFinite ||
          expectedLength < 0 || expectedLength != expectedLength.toInt() ||
          !path.startsWith('assets/') || path.contains('..') ||
          path != 'assets/$expectedHash' ||
          !paths.add(path) ||
          width != null &&
              (width is! num || !width.isFinite || width <= 0 || width != width.toInt()) ||
          height != null &&
              (height is! num || !height.isFinite || height <= 0 || height != height.toInt())) {
        throw const FormatException('Archive asset descriptor is invalid');
      }
      final file = decoded.find(path);
      final data = file?.readBytes();
      if (file == null || !file.isFile || data == null ||
          data.length != expectedLength.toInt() ||
          data.length > _maxAssetBytes) {
        throw const FormatException('Archive asset bytes are missing or invalid');
      }
      total += data.length;
      if (total > _maxTotalBytes || sha256.convert(data).toString() != expectedHash) {
        throw const FormatException('Archive asset hash does not match bytes');
      }
      assets.add(
        ArchiveAsset(
          id: id,
          mime: mime,
          bytes: data,
          width: (width as num?)?.toInt(),
          height: (height as num?)?.toInt(),
        ),
      );
    }
    final actualFiles = decoded.files.where((file) => file.isFile).map((file) => file.name).toSet();
    if (actualFiles.length != paths.length || !actualFiles.containsAll(paths)) {
      throw const FormatException('Archive contains unlisted files');
    }
    _validateReferences(document, ids);
    return JournalArchive(document: document, assets: assets);
  }
}

void _validateReferences(EntryDocument document, Set<String> assetIds) {
  void visit(Iterable<CanvasNode> nodes) {
    for (final node in nodes) {
      final id = node.assetId;
      if (id != null && !assetIds.contains(id)) {
        throw const FormatException('Archive document references a missing asset');
      }
      visit(node.children);
    }
  }

  visit(document.nodes);
}

bool _validMime(String value) =>
    value.trim().isNotEmpty && value.contains('/') && !value.contains(RegExp(r'\s'));

bool _invalidDimension(int? value) => value != null && value <= 0;
