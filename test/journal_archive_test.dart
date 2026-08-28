import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/models/entry.dart';
import 'package:journal_app/models/template.dart';
import 'package:journal_app/services/journal_archive.dart';
import 'package:journal_app/services/entry_document_codec.dart';

void main() {
  test('cozyjournal archive round-trips document, assets, and templates', () {
    final document = EntryDocumentCodec.fromEntry(
      Entry(
        id: 'archive-entry',
        title: 'Backup',
        createdAt: DateTime.utc(2026),
        blocks: [
          ContentBlock(
            id: 'photo',
            type: BlockType.image,
            assetId: 'asset-1',
            x: -8,
            y: 12,
            w: 40,
            h: 30,
          ),
        ],
      ),
    );
    final template = JournalTemplate(
      id: 'template-1',
      name: 'Starter',
      document: document,
      createdAt: DateTime.utc(2026),
    );
    final archive = JournalArchive(
      document: document,
      assets: [
        ArchiveAsset(
          id: 'asset-1',
          mime: 'image/png',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      ],
      templates: [template],
    );

    final decoded = JournalArchive.decode(archive.encode());
    expect(decoded.document.id, 'archive-entry');
    expect(decoded.document.nodes.single.payload['assetId'], 'asset-1');
    expect(decoded.assets.single.bytes, [1, 2, 3]);
    expect(decoded.templates.single.name, 'Starter');
  });

  test('cozyjournal archive rejects invalid format and schema', () {
    expect(
      () => JournalArchive.decode(
        Uint8List.fromList('{"format":"other"}'.codeUnits),
      ),
      throwsFormatException,
    );
    expect(
      () => JournalArchive.decode(
        Uint8List.fromList(
          '{"format":"cozyjournal","schemaVersion":99}'.codeUnits,
        ),
      ),
      throwsFormatException,
    );
  });
}
