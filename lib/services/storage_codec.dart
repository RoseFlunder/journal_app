import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models/asset_kind.dart';
import '../models/document.dart';
import '../models/view_state.dart';

/// The permanent on-disk format used by the journal.  The value is deliberately
/// not tied to a Dart class name: it is part of the storage contract.
abstract final class JournalStorageFormat {
  static const namespace = 'cozy-bloom-storage-v2';
  static const document = 'cozy-bloom.document';
  static const manifest = 'cozy-bloom.manifest';
  static const asset = 'cozy-bloom.asset';
  static const checkpoint = 'cozy-bloom.checkpoint';
  static const viewPreferences = 'cozy-bloom.view-preferences';
  static const sync = 'cozy-bloom.sync';
  static const schemaVersion = 1;
}

/// Stable persisted discriminators. Enum names are implementation details and
/// must not silently change a long-lived storage contract.
String assetKindDiscriminator(AssetKind kind) => switch (kind) {
  AssetKind.image => 'image',
  AssetKind.audio => 'audio',
};

AssetKind assetKindFromDiscriminator(Object? value) => switch (value) {
  'image' => AssetKind.image,
  'audio' => AssetKind.audio,
  _ => throw const StorageFormatException('Unsupported asset kind'),
};

class StorageFormatException implements Exception {
  const StorageFormatException(this.message, {this.path});

  final String message;
  final String? path;

  @override
  String toString() => path == null
      ? 'StorageFormatException: $message'
      : 'StorageFormatException at $path: $message';
}

Map<String, dynamic> _stringMap(Object? raw, String message) {
  if (raw is! Map || raw.keys.any((key) => key is! String)) {
    throw StorageFormatException(message);
  }
  return Map<String, dynamic>.from(raw);
}

/// The decoded document record.  [revision] is a local write counter and is
/// intentionally kept outside [EntryDocument], so it never participates in
/// cloud conflict resolution or archive identity.
class StoredDocumentRecord {
  const StoredDocumentRecord({required this.revision, required this.document});

  final int revision;
  final EntryDocument document;

  Map<String, dynamic> toJson() =>
      JournalDocumentCodec.encodeRecord(document, revision: revision);
}

class StoredJournalManifest {
  StoredJournalManifest(Iterable<String> documentIds)
    : documentIds = List<String>.unmodifiable(documentIds) {
    if (this.documentIds.any((id) => id.trim().isEmpty)) {
      throw const StorageFormatException(
        'Manifest document IDs must not be empty',
      );
    }
    if (this.documentIds.toSet().length != this.documentIds.length) {
      throw const StorageFormatException(
        'Manifest contains duplicate document IDs',
      );
    }
  }

  final List<String> documentIds;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'format': JournalStorageFormat.manifest,
    'schemaVersion': JournalStorageFormat.schemaVersion,
    'documentIds': documentIds,
  };

  factory StoredJournalManifest.fromJson(Object? raw) {
    final json = _stringMap(raw, 'Manifest is not an object');
    _requireFormat(json, JournalStorageFormat.manifest);
    _requireVersion(json);
    final ids = json['documentIds'];
    if (ids is! List || ids.any((value) => value is! String || value.isEmpty)) {
      throw const StorageFormatException(
        'Manifest documentIds must be strings',
      );
    }
    final result = ids.cast<String>();
    if (result.toSet().length != result.length) {
      throw const StorageFormatException(
        'Manifest contains duplicate document IDs',
      );
    }
    return StoredJournalManifest(result);
  }
}

/// Device-local camera/grid state. It is keyed by document ID in storage but
/// deliberately never appears in a durable document or cloud head.
class StoredViewPreferences {
  const StoredViewPreferences({this.view, this.gridVisible = false});

  final ViewState? view;
  final bool gridVisible;

  Map<String, dynamic> toJson() {
    if (view != null &&
        (!view!.zoom.isFinite ||
            view!.zoom <= 0 ||
            !view!.panX.isFinite ||
            !view!.panY.isFinite)) {
      throw const StorageFormatException(
        'View preferences contain invalid numbers',
      );
    }
    return <String, dynamic>{
      'format': JournalStorageFormat.viewPreferences,
      'schemaVersion': JournalStorageFormat.schemaVersion,
      'view': view?.toJson(),
      'gridVisible': gridVisible,
    };
  }

  factory StoredViewPreferences.fromJson(Object? raw) {
    final json = _stringMap(raw, 'View preferences are not an object');
    _requireFormat(json, JournalStorageFormat.viewPreferences);
    _requireVersion(json);
    final rawView = json['view'];
    if (rawView != null && rawView is! Map) {
      throw const StorageFormatException('View preferences view is invalid');
    }
    if (json['gridVisible'] is! bool) {
      throw const StorageFormatException(
        'View preferences grid visibility is invalid',
      );
    }
    final preferences = StoredViewPreferences(
      view: rawView == null
          ? null
          : ViewState.fromJson(Map<String, dynamic>.from(rawView as Map)),
      gridVisible: json['gridVisible'] as bool,
    );
    preferences.toJson();
    return preferences;
  }
}

/// Versioned checkpoint envelope containing a canonical document snapshot.
class StoredCheckpointRecord {
  const StoredCheckpointRecord({
    required this.id,
    required this.documentId,
    required this.createdAt,
    required this.document,
  });

  final String id;
  final String documentId;
  final DateTime createdAt;
  final EntryDocument document;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'format': JournalStorageFormat.checkpoint,
    'schemaVersion': JournalStorageFormat.schemaVersion,
    'id': id,
    'documentId': documentId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'document': JournalDocumentCodec.canonicalDocument(document),
  };

  factory StoredCheckpointRecord.fromJson(Object? raw) {
    final json = _stringMap(raw, 'Checkpoint is not an object');
    _requireFormat(json, JournalStorageFormat.checkpoint);
    _requireVersion(json);
    final id = json['id'];
    final documentId = json['documentId'];
    final createdAt = json['createdAt'];
    if (id is! String ||
        id.isEmpty ||
        documentId is! String ||
        documentId.isEmpty ||
        createdAt is! String) {
      throw const StorageFormatException('Checkpoint metadata is invalid');
    }
    final documentRaw = json['document'];
    if (documentRaw is! Map) {
      throw const StorageFormatException('Checkpoint document is missing');
    }
    final parsedAt = DateTime.tryParse(createdAt);
    if (parsedAt == null) {
      throw const StorageFormatException('Checkpoint timestamp is invalid');
    }
    final document = JournalDocumentCodec.decodeDocument(documentRaw);
    if (document.id != documentId) {
      throw const StorageFormatException(
        'Checkpoint document ID does not match metadata',
      );
    }
    return StoredCheckpointRecord(
      id: id,
      documentId: documentId,
      createdAt: parsedAt.toUtc(),
      document: document,
    );
  }
}

/// Canonical JSON codec shared by Hive, archives, and cloud synchronization.
/// Domain models remain usable without knowing about storage envelopes.
abstract final class JournalDocumentCodec {
  static Map<String, dynamic> encodeRecord(
    EntryDocument document, {
    required int revision,
  }) {
    if (revision < 0) {
      throw const StorageFormatException('Document revision is invalid');
    }
    _validateDocument(document);
    return <String, dynamic>{
      'format': JournalStorageFormat.document,
      'schemaVersion': JournalStorageFormat.schemaVersion,
      'revision': revision,
      'document': _canonicalDocument(document),
    };
  }

  static StoredDocumentRecord decodeRecord(Object? raw) {
    final json = _stringMap(raw, 'Document record is not an object');
    _requireFormat(json, JournalStorageFormat.document);
    _requireVersion(json);
    final revision = json['revision'];
    if (revision is! num ||
        !revision.isFinite ||
        revision < 0 ||
        revision != revision.toInt()) {
      throw const StorageFormatException('Document revision is invalid');
    }
    final document = json['document'];
    if (document is! Map) {
      throw const StorageFormatException('Document record is missing document');
    }
    final decoded = decodeDocument(document);
    return StoredDocumentRecord(revision: revision.toInt(), document: decoded);
  }

  /// Content identity intentionally omits local camera state, persistence
  /// revision, and schema envelopes.  The canonical key ordering keeps this
  /// stable across Dart map insertion order and Hive map implementations.
  static String fingerprint(EntryDocument document) {
    final bytes = utf8.encode(jsonEncode(_canonicalDocument(document)));
    return sha256.convert(bytes).toString();
  }

  static bool sameContent(EntryDocument left, EntryDocument right) =>
      fingerprint(left) == fingerprint(right);

  static Map<String, dynamic> canonicalDocument(EntryDocument document) {
    _validateDocument(document);
    return _canonicalDocument(document);
  }

  static EntryDocument decodeDocument(Object? raw) {
    final json = _stringMap(raw, 'Document payload is not an object');
    if (json['schemaVersion'] != JournalStorageFormat.schemaVersion) {
      throw StorageFormatException(
        'Unsupported document schema: ${json['schemaVersion']}',
      );
    }
    _validateDocumentEnvelope(json);
    _validateNodeEnvelopes(json['nodes'] as List<dynamic>);
    late final EntryDocument decoded;
    try {
      decoded = EntryDocument.fromJson(json);
    } catch (error) {
      throw StorageFormatException('Document payload is malformed: $error');
    }
    _validateDocument(decoded);
    return decoded;
  }

  static void _validateDocument(EntryDocument document) {
    if (document.id.trim().isEmpty) {
      throw const StorageFormatException('Document ID must not be empty');
    }
    if (!document.titleFontSize.isFinite || document.titleFontSize <= 0) {
      throw const StorageFormatException('Title font size is invalid');
    }
    final gridSize = document.board.gridSize;
    if (!gridSize.isFinite || gridSize <= 0) {
      throw const StorageFormatException('Board grid size is invalid');
    }
    final music = document.music;
    if (music != null &&
        (music.provider.trim().isEmpty ||
            music.trackId.trim().isEmpty ||
            music.duration.isNegative)) {
      throw const StorageFormatException('Music reference is invalid');
    }
    if (document.pageSpec.format != 'a4Portrait' ||
        document.pageSpec.coordinateSystemVersion != 1 ||
        !document.pageSpec.width.isFinite ||
        !document.pageSpec.height.isFinite ||
        document.pageSpec.width != 100 ||
        document.pageSpec.height != 141.4) {
      throw const StorageFormatException('Unsupported page coordinate space');
    }
    final ids = <String>{};
    var count = 0;
    void visit(Iterable<CanvasNode> nodes, int depth) {
      if (depth > 32) {
        throw const StorageFormatException('Group nesting exceeds 32 levels');
      }
      for (final node in nodes) {
        count++;
        if (count > 10000) {
          throw const StorageFormatException(
            'Document contains too many nodes',
          );
        }
        if (node.id.trim().isEmpty || !ids.add(node.id)) {
          throw const StorageFormatException(
            'Node IDs must be unique and non-empty',
          );
        }
        final transform = node.transform;
        for (final value in <double>[
          transform.x,
          transform.y,
          transform.width,
          transform.height,
          transform.rotation,
          node.opacity,
        ]) {
          if (!value.isFinite) {
            throw const StorageFormatException(
              'Node contains a non-finite number',
            );
          }
        }
        if (transform.width <= 0 || transform.height <= 0) {
          throw const StorageFormatException(
            'Node dimensions must be positive',
          );
        }
        if (node.opacity < 0 || node.opacity > 1) {
          throw const StorageFormatException('Node opacity is outside 0..1');
        }
        _validateNodeData(node);
        visit(node.children, depth + 1);
      }
    }

    visit(document.nodes, 0);
  }

  static void _validateDocumentEnvelope(Map<String, dynamic> json) {
    final id = json['id'];
    final createdAt = json['createdAt'];
    final modifiedAt = json['modifiedAt'];
    if (id is! String ||
        id.trim().isEmpty ||
        createdAt is! String ||
        DateTime.tryParse(createdAt) == null ||
        modifiedAt is! String ||
        DateTime.tryParse(modifiedAt) == null) {
      throw const StorageFormatException('Document metadata is invalid');
    }
    if (json['page'] is! Map ||
        json['nodes'] is! List ||
        json['board'] is! Map) {
      throw const StorageFormatException(
        'Document structural fields are invalid',
      );
    }
    final page = _stringMap(
      json['page'],
      'Document page specification is invalid',
    );
    if (page['format'] is! String ||
        page['coordinateSystemVersion'] is! num ||
        page['width'] is! num ||
        page['height'] is! num) {
      throw const StorageFormatException(
        'Document page specification is invalid',
      );
    }
    final board = _stringMap(
      json['board'],
      'Document board settings are invalid',
    );
    final gridSize = board['gridSize'];
    if (gridSize != null &&
        (gridSize is! num || !gridSize.isFinite || gridSize <= 0)) {
      throw const StorageFormatException('Document board settings are invalid');
    }
  }

  static void _validateNodeEnvelopes(List<dynamic> rawNodes, [int depth = 0]) {
    if (depth > 32) {
      throw const StorageFormatException('Group nesting exceeds 32 levels');
    }
    for (final raw in rawNodes) {
      if (raw is! Map) {
        throw const StorageFormatException('Canvas node must be an object');
      }
      final node = _stringMap(raw, 'Canvas node must have string keys');
      final id = node['id'];
      final kind = node['kind'] ?? node['type'];
      if (id is! String ||
          id.trim().isEmpty ||
          kind is! String ||
          kind.isEmpty) {
        throw const StorageFormatException('Canvas node metadata is invalid');
      }
      if (node['version'] != null) {
        final version = node['version'];
        if (version is! num ||
            !version.isFinite ||
            version != version.toInt()) {
          throw const StorageFormatException('Canvas node version is invalid');
        }
      }
      final transform = node['transform'];
      if (transform is! Map) {
        throw const StorageFormatException('Canvas node transform is missing');
      }
      final transformMap = _stringMap(
        transform,
        'Canvas node transform must have string keys',
      );
      for (final key in const ['x', 'y', 'w', 'h', 'rotation']) {
        final value = transformMap[key];
        if (value is! num || !value.isFinite) {
          throw StorageFormatException('Canvas node transform.$key is invalid');
        }
      }
      final opacity = node['opacity'];
      if (opacity != null &&
          (opacity is! num ||
              !opacity.isFinite ||
              opacity < 0 ||
              opacity > 1)) {
        throw const StorageFormatException('Canvas node opacity is invalid');
      }
      for (final key in const ['locked', 'visible']) {
        if (node[key] != null && node[key] is! bool) {
          throw StorageFormatException('Canvas node $key is invalid');
        }
      }
      if (node['data'] != null && node['data'] is! Map) {
        throw const StorageFormatException('Canvas node data is invalid');
      }
      if (node['data'] is Map) {
        _stringMap(node['data'], 'Canvas node data must have string keys');
      }
      final children = node['children'];
      if (children != null && children is! List) {
        throw const StorageFormatException('Canvas node children are invalid');
      }
      if (children is List) {
        _validateNodeEnvelopes(children, depth + 1);
      }
    }
  }

  static Map<String, dynamic> _canonicalDocument(EntryDocument document) =>
      <String, dynamic>{
        'schemaVersion': JournalStorageFormat.schemaVersion,
        'id': document.id,
        'title': document.title,
        'createdAt': document.createdAt.toUtc().toIso8601String(),
        'modifiedAt': document.modifiedAt.toUtc().toIso8601String(),
        'page': <String, dynamic>{
          'format': document.pageSpec.format,
          'coordinateSystemVersion': document.pageSpec.coordinateSystemVersion,
          'width': document.pageSpec.width,
          'height': document.pageSpec.height,
        },
        'nodes': document.nodes.map(_canonicalNode).toList(growable: false),
        'board': <String, dynamic>{
          'backgroundColorValue': document.board.backgroundColorValue,
          'snapToGrid': document.board.snapToGrid,
          'gridSize': document.board.gridSize,
        },
        'music': document.music == null
            ? null
            : <String, dynamic>{
                'provider': document.music!.provider,
                'trackId': document.music!.trackId,
                'title': document.music!.title,
                'artist': document.music!.artist,
                'artworkUrl': document.music!.artworkUrl,
                'trackPageUrl': document.music!.trackPageUrl,
                'licenseUrl': document.music!.licenseUrl,
                'durationMs': document.music!.duration.inMilliseconds,
              },
        'titleFontSize': document.titleFontSize,
        'titleFontFamily': document.titleFontFamily,
        'titleTextColorValue': document.titleTextColorValue,
        'titleBold': document.titleBold,
        'titleItalic': document.titleItalic,
        'previewImageNodeId': document.previewImageNodeId,
      };

  static Map<String, dynamic> _canonicalNode(CanvasNode node) {
    if (node.isOpaque && node.opaqueJson != null) {
      return _deepMutable(node.opaqueJson!);
    }
    // The typed content projection supplies the known fields. Legacy payload
    // keys are merged afterwards so unsupported extensions are not discarded
    // while callers migrate away from the compatibility map.
    final payload =
        <String, dynamic>{...node.content.toPayload(), ...node.payload}
          ..remove('id')
          ..remove('type')
          ..remove('transform')
          ..remove('opacity')
          ..remove('locked')
          ..remove('visible')
          ..remove('accessibilityLabel')
          ..remove('children')
          ..remove('groupId')
          ..remove('childIds');
    if (node.type == BlockType.text && payload['richTextDelta'] is List) {
      payload['text'] = _plainTextFromDelta(payload['richTextDelta'] as List);
    }
    return <String, dynamic>{
      'id': node.id,
      'kind': _nodeKindDiscriminator(node.type),
      'version': node.nodeVersion,
      'transform': node.transform.toJson(),
      'opacity': node.opacity,
      'locked': node.locked || node.isOpaque,
      'visible': node.visible,
      'accessibilityLabel': node.accessibilityLabel,
      'data': _deepMutable(payload),
      if (node.children.isNotEmpty)
        'children': node.children.map(_canonicalNode).toList(growable: false),
    };
  }
}

String _nodeKindDiscriminator(BlockType type) => switch (type) {
  BlockType.text => 'text',
  BlockType.image => 'image',
  BlockType.sticker => 'sticker',
  BlockType.ink => 'ink',
  BlockType.shape => 'shape',
  BlockType.group => 'group',
};

void _validateNodeData(CanvasNode node) {
  if (node.isOpaque) return;
  final payload = node.payload;
  _validateFiniteTree(payload);
  if (node.type == BlockType.text &&
      payload['richTextDelta'] != null &&
      payload['richTextDelta'] is! List) {
    throw const StorageFormatException('Text Delta is invalid');
  }
  if (node.type == BlockType.text && payload['richTextDelta'] is List) {
    final delta = payload['richTextDelta'] as List;
    for (final operation in delta) {
      if (operation is! Map) {
        throw const StorageFormatException('Text Delta operation is invalid');
      }
      if (operation.keys.any(
        (key) =>
            key != 'insert' &&
            key != 'delete' &&
            key != 'retain' &&
            key != 'attributes',
      )) {
        throw const StorageFormatException(
          'Text Delta operation has unknown fields',
        );
      }
      final keys = operation.keys.where(
        (key) => key == 'insert' || key == 'delete' || key == 'retain',
      );
      if (keys.length != 1) {
        throw const StorageFormatException(
          'Text Delta operation must have one action',
        );
      }
      final action = keys.single;
      final value = operation[action];
      if (action == 'insert') {
        if (value is! String && value is! Map) {
          throw const StorageFormatException('Text Delta insert is invalid');
        }
      } else if (value is! num ||
          !value.isFinite ||
          value <= 0 ||
          value != value.toInt()) {
        throw const StorageFormatException(
          'Text Delta retain/delete is invalid',
        );
      }
      final attributes = operation['attributes'];
      if (attributes != null && attributes is! Map) {
        throw const StorageFormatException('Text Delta attributes are invalid');
      }
    }
    final fontSize = payload['fontSize'];
    if (fontSize != null &&
        (fontSize is! num || !fontSize.isFinite || fontSize <= 0)) {
      throw const StorageFormatException('Text font size is invalid');
    }
  }
  if (node.type == BlockType.image || node.type == BlockType.sticker) {
    _validateFiniteField(payload, 'cornerRadius', minimum: 0);
    _validateFiniteField(payload, 'frameWidth', minimum: 0);
    _validateFiniteField(payload, 'brightness');
    _validateFiniteField(payload, 'contrast');
    _validateFiniteField(payload, 'saturation', minimum: 0);
    _validateFiniteField(payload, 'warmth');
    final crop = payload['crop'];
    if (crop != null && crop is! Map) {
      throw const StorageFormatException('Image crop is invalid');
    }
    if (crop is Map) {
      for (final key in const ['left', 'top', 'right', 'bottom']) {
        final value = crop[key];
        if (value != null &&
            (value is! num || !value.isFinite || value < 0 || value > 1)) {
          throw const StorageFormatException('Image crop is invalid');
        }
      }
    }
  }
  if (node.type == BlockType.ink) {
    final width = payload['strokeWidth'];
    if (width != null && (width is! num || !width.isFinite || width <= 0)) {
      throw const StorageFormatException('Ink stroke width is invalid');
    }
    final points = payload['inkPoints'];
    if (points != null && points is! List) {
      throw const StorageFormatException('Ink points are invalid');
    }
    if (points is List) {
      for (final point in points) {
        if (point is! Map) {
          throw const StorageFormatException('Ink point is invalid');
        }
        for (final value in point.values) {
          if (value is! num || !value.isFinite) {
            throw const StorageFormatException(
              'Ink point contains a non-finite number',
            );
          }
        }
      }
    }
  }
  if (node.type == BlockType.shape) {
    final width = payload['strokeWidth'];
    if (width != null && (width is! num || !width.isFinite || width <= 0)) {
      throw const StorageFormatException('Shape stroke width is invalid');
    }
  }
}

void _validateFiniteTree(Object? value) {
  if (value is num && !value.isFinite) {
    throw const StorageFormatException(
      'Node payload contains a non-finite number',
    );
  }
  if (value is Map) {
    for (final child in value.values) {
      _validateFiniteTree(child);
    }
  } else if (value is Iterable) {
    for (final child in value) {
      _validateFiniteTree(child);
    }
  }
}

void _validateFiniteField(
  Map<String, dynamic> payload,
  String key, {
  double? minimum,
}) {
  final value = payload[key];
  if (value == null) return;
  if (value is! num || !value.isFinite || minimum != null && value < minimum) {
    throw StorageFormatException('Node $key is invalid');
  }
}

String _plainTextFromDelta(List<dynamic> delta) {
  final buffer = StringBuffer();
  for (final operation in delta) {
    if (operation is! Map) continue;
    final insert = operation['insert'];
    if (insert is String) buffer.write(insert);
  }
  final value = buffer.toString();
  return value.endsWith('\n') ? value.substring(0, value.length - 1) : value;
}

class StoredAssetRecord {
  StoredAssetRecord({
    required this.id,
    required this.kind,
    required this.mime,
    required List<int> bytes,
    this.width,
    this.height,
  }) : bytes = List<int>.unmodifiable(bytes);

  final String id;
  final String kind;
  final String mime;
  final List<int> bytes;
  final int? width;
  final int? height;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'format': JournalStorageFormat.asset,
    'schemaVersion': JournalStorageFormat.schemaVersion,
    'id': id,
    'kind': kind,
    'mime': mime,
    'byteLength': bytes.length,
    'sha256': sha256.convert(bytes).toString(),
    'width': width,
    'height': height,
    'bytes': bytes.toList(growable: false),
  };

  factory StoredAssetRecord.fromJson(Object? raw) {
    final json = _stringMap(raw, 'Asset record is not an object');
    _requireFormat(json, JournalStorageFormat.asset);
    _requireVersion(json);
    final id = json['id'];
    final mime = json['mime'];
    final kind = json['kind'];
    final bytesRaw = json['bytes'];
    if (id is! String ||
        id.isEmpty ||
        mime is! String ||
        !_validMime(mime) ||
        (kind != 'image' && kind != 'audio')) {
      throw const StorageFormatException('Asset metadata is invalid');
    }
    if (bytesRaw is! List ||
        bytesRaw.any(
          (value) =>
              value is! num ||
              !value.isFinite ||
              value < 0 ||
              value > 255 ||
              value != value.toInt(),
        )) {
      throw const StorageFormatException('Asset bytes are invalid');
    }
    final bytes = Uint8List.fromList(
      bytesRaw.cast<num>().map((value) => value.toInt()).toList(),
    );
    final byteLength = json['byteLength'];
    if (byteLength is! num ||
        !byteLength.isFinite ||
        byteLength < 0 ||
        byteLength != byteLength.toInt() ||
        byteLength.toInt() != bytes.length) {
      throw const StorageFormatException(
        'Asset byte length does not match bytes',
      );
    }
    final expectedHash = sha256.convert(bytes).toString();
    if (json['sha256'] != expectedHash || id != expectedHash) {
      throw const StorageFormatException('Asset hash does not match its ID');
    }
    final width = json['width'];
    final height = json['height'];
    if (width != null &&
        (width is! num ||
            !width.isFinite ||
            width <= 0 ||
            width != width.toInt())) {
      throw const StorageFormatException('Asset width is invalid');
    }
    if (height != null &&
        (height is! num ||
            !height.isFinite ||
            height <= 0 ||
            height != height.toInt())) {
      throw const StorageFormatException('Asset height is invalid');
    }
    return StoredAssetRecord(
      id: id,
      kind: kind as String,
      mime: mime,
      bytes: bytes,
      width: (width as num?)?.toInt(),
      height: (height as num?)?.toInt(),
    );
  }
}

void _requireFormat(Map<String, dynamic> json, String expected) {
  if (json['format'] != expected) {
    throw StorageFormatException(
      'Unsupported record format: ${json['format']}',
    );
  }
}

void _requireVersion(Map<String, dynamic> json) {
  if (json['schemaVersion'] != JournalStorageFormat.schemaVersion) {
    throw StorageFormatException(
      'Unsupported storage schema: ${json['schemaVersion']}',
    );
  }
}

Map<String, dynamic> _deepMutable(Object? value) {
  if (value is Map<Object?, Object?>) {
    final entries = value.entries.toList()
      ..sort(
        (left, right) => left.key.toString().compareTo(right.key.toString()),
      );
    return <String, dynamic>{
      for (final entry in entries)
        entry.key.toString(): _deepValue(entry.value),
    };
  }
  return <String, dynamic>{'value': _deepValue(value)};
}

bool _validMime(String value) =>
    value.trim().isNotEmpty &&
    value.contains('/') &&
    !value.contains(RegExp(r'\s'));

Object? _deepValue(Object? value) => switch (value) {
  Map<Object?, Object?> map => <String, dynamic>{
    for (final entry
        in (map.entries.toList()..sort(
          (left, right) => left.key.toString().compareTo(right.key.toString()),
        )))
      entry.key.toString(): _deepValue(entry.value),
  },
  List<Object?> list => [for (final item in list) _deepValue(item)],
  _ => value,
};
