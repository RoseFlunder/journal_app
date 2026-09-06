import 'package:flutter_test/flutter_test.dart';

import 'package:journal_app/models/document.dart';
import 'package:journal_app/models/view_state.dart';
import 'package:journal_app/services/storage_codec.dart';

void main() {
  final base = EntryDocument(
    id: 'page',
    title: 'Frozen',
    createdAt: DateTime.utc(2026, 1, 1),
    modifiedAt: DateTime.utc(2026, 1, 1),
    nodes: [
      CanvasNode(
        id: 'text',
        type: BlockType.text,
        transform: const Transform2D(width: 30, height: 12),
        payload: const {
          'text': 'Hello',
          'richTextDelta': [
            {'insert': 'Hello'},
          ],
        },
      ),
    ],
    view: const ViewState(zoom: 2, panX: 4),
  );

  test('canonical records keep revisions and view state out of content', () {
    final record = JournalDocumentCodec.encodeRecord(base, revision: 7);
    final document = record['document'] as Map<String, dynamic>;
    final node = (document['nodes'] as List).single as Map<String, dynamic>;

    expect(record['format'], JournalStorageFormat.document);
    expect(record['revision'], 7);
    expect(document['schemaVersion'], 1);
    expect(document['view'], isNull);
    expect((document['music'] as Object?), isNull);
    expect(document['previewImageNodeId'], isNull);
    expect(node['kind'], 'text');
    expect(node['version'], 1);
    expect(node['data'], isA<Map<String, dynamic>>());
    expect(
      JournalDocumentCodec.sameContent(
        base,
        base.copyWith(view: const ViewState(zoom: 0.5, panY: 80)),
      ),
      isTrue,
    );
  });

  test('preview image choice is optional and round-trips canonically', () {
    final oldDocument = JournalDocumentCodec.canonicalDocument(base)
      ..remove('previewImageNodeId');
    expect(
      JournalDocumentCodec.decodeDocument(oldDocument).previewImageNodeId,
      isNull,
    );

    final selected = base.copyWith(previewImageNodeId: 'photo');
    final decoded = JournalDocumentCodec.decodeDocument(
      JournalDocumentCodec.canonicalDocument(selected),
    );
    expect(decoded.previewImageNodeId, 'photo');
    expect(JournalDocumentCodec.sameContent(base, selected), isFalse);
  });

  test(
    'unknown node kinds stay opaque and round-trip without becoming text',
    () {
      final raw = <String, dynamic>{
        'schemaVersion': 1,
        'id': 'future-page',
        'title': 'Future',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'modifiedAt': '2026-01-01T00:00:00.000Z',
        'page': const {
          'format': 'a4Portrait',
          'coordinateSystemVersion': 1,
          'width': 100.0,
          'height': 141.4,
        },
        'nodes': [
          {
            'id': 'future-node',
            'kind': 'magicBrush',
            'version': 4,
            'transform': {'x': 1, 'y': 2, 'w': 10, 'h': 10, 'rotation': 0},
            'opacity': 1,
            'locked': false,
            'visible': true,
            'data': {
              'newField': [1, 2, 3],
            },
          },
        ],
        'board': {
          'backgroundColorValue': 0xFFFFFFFF,
          'snapToGrid': false,
          'gridSize': 8,
        },
        'titleFontSize': 28,
        'titleBold': true,
        'titleItalic': false,
      };

      final document = JournalDocumentCodec.decodeDocument(raw);
      final node = document.nodes.single;
      expect(node.isOpaque, isTrue);
      expect(node.locked, isTrue);
      expect(
        JournalDocumentCodec.canonicalDocument(document)['nodes'],
        raw['nodes'],
      );
    },
  );

  test('invalid duplicate node IDs are rejected before persistence', () {
    final duplicate = base.copyWith(
      nodes: [
        base.nodes.single,
        base.nodes.single.copyWith(
          transform: const Transform2D(width: 4, height: 4),
        ),
      ],
    );
    expect(
      () => JournalDocumentCodec.encodeRecord(duplicate, revision: 0),
      throwsA(isA<StorageFormatException>()),
    );
  });

  test('malformed nested nodes are rejected instead of being dropped', () {
    final raw = JournalDocumentCodec.canonicalDocument(base);
    final nodes = raw['nodes'] as List<dynamic>;
    final node = Map<String, dynamic>.from(nodes.single as Map)
      ..['children'] = <Object?>[42];
    raw['nodes'] = <Object?>[node];

    expect(
      () => JournalDocumentCodec.decodeDocument(raw),
      throwsA(isA<StorageFormatException>()),
    );
  });

  test('asset records are content addressed and verify their bytes', () {
    final record = StoredAssetRecord(
      id: 'wrong',
      kind: 'image',
      mime: 'image/png',
      bytes: const [1, 2, 3],
    );
    final json = record.toJson();
    expect(json['sha256'], isNot('wrong'));
    expect(
      () => StoredAssetRecord.fromJson(json),
      throwsA(isA<StorageFormatException>()),
    );
  });
}
