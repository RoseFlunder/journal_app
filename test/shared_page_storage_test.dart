import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:journal_app/models/document.dart';
import 'package:journal_app/models/page_music.dart';
import 'package:journal_app/services/hive_capability_sources.dart';
import 'package:journal_app/services/hive_journal_data_source.dart';
import 'package:journal_app/services/journal_archive.dart';

void main() {
  late Directory directory;
  late _FailingStorage storage;
  late HiveDocumentDataSource documents;
  late HiveArchiveDataSource archives;
  setUp(() async {
    directory = Directory.systemTemp.createTempSync('shared_page_storage');
    Hive.init(directory.path);
    storage = _FailingStorage();
    documents = HiveDocumentDataSource(storage);
    await documents.init();
    archives = HiveArchiveDataSource(
      storage,
      documents: documents,
      assets: HiveAssetDataSource(
        storage,
        documents: () => documents.documents,
      ),
    );
  });
  tearDown(() async {
    await documents.dispose();
    await storage.dispose();
    await Hive.close();
    directory.deleteSync(recursive: true);
  });

  test(
    'adds complete independent copies preserving content and original date',
    () async {
      final source = JournalArchive(
        document: EntryDocument(
          id: 'original',
          title: 'Spring',
          createdAt: DateTime.utc(2020, 3, 2),
          modifiedAt: DateTime.utc(2021),
          revision: 23,
          titleFontSize: 32,
          titleFontFamily: 'Lora',
          titleItalic: true,
          previewImageNodeId: 'image',
          music: const PageMusicTrack(
            provider: 'jamendo',
            trackId: '123',
            title: 'Song',
            artist: 'Artist',
            streamUrl: '',
            trackPageUrl: 'https://www.jamendo.com/track/123',
            licenseUrl: 'https://creativecommons.org/licenses/by/4.0/',
          ),
          nodes: [
            CanvasNode(
              id: 'group',
              type: BlockType.group,
              transform: const Transform2D(width: 40, height: 40),
              children: [
                CanvasNode(
                  id: 'image',
                  type: BlockType.image,
                  transform: const Transform2D(width: 20, height: 20),
                  payload: const {'assetId': 'source-asset'},
                ),
              ],
            ),
          ],
        ),
        assets: [
          ArchiveAsset(id: 'source-asset', mime: 'image/png', bytes: [1, 2, 3]),
        ],
      );
      final decoded = JournalArchive.decode(source.encode());
      final first = await archives.importArchive(decoded);
      final second = await archives.importArchive(decoded);
      expect(first.id, isNot('original'));
      expect(second.id, isNot(first.id));
      expect(first.createdAt, source.document.createdAt);
      expect(first.modifiedAt.isAfter(source.document.modifiedAt), isTrue);
      expect(first.revision, 0);
      expect(first.titleFontSize, 32);
      expect(first.titleFontFamily, 'Lora');
      expect(first.titleItalic, isTrue);
      expect(first.previewImageNodeId, 'image');
      expect(first.music!.trackId, '123');
      final assetId = first.nodes.single.children.single.assetId!;
      expect(assetId, isNot('source-asset'));
      expect(storage.assetKeys.length, 1);
      expect(archives.archiveForDocument(first.id)!.assets.single.bytes, [
        1,
        2,
        3,
      ]);
    },
  );

  test(
    'orders old, middle, future and tied pages across reload and sync order',
    () async {
      for (final year in [2022, 2020, 2021, 2090, 2021]) {
        await archives.importArchive(
          JournalArchive(document: _page('source', year)),
        );
      }
      final ordered = documents.documents;
      expect(ordered.map((page) => page.createdAt.year), [
        2020,
        2021,
        2021,
        2022,
        2090,
      ]);
      expect(ordered[1].id.compareTo(ordered[2].id), lessThan(0));
      await documents.reorderExact(ordered.reversed);
      expect(
        documents.documents.map((page) => page.id),
        ordered.map((page) => page.id),
      );
      await storage.flush();
      final reloaded = HiveDocumentDataSource(storage);
      expect(
        reloaded.documents.map((page) => page.id),
        ordered.map((page) => page.id),
      );
      await reloaded.dispose();
    },
  );

  test('failed document or manifest write leaves no partial page', () async {
    for (final manifest in [false, true]) {
      storage.failEntry = !manifest;
      storage.failManifest = manifest;
      await expectLater(
        archives.importArchive(JournalArchive(document: _page('source', 2020))),
        throwsStateError,
      );
      expect(documents.documents, isEmpty);
      expect(storage.entryKeys, isEmpty);
    }
    await archives.importArchive(
      JournalArchive(document: _page('source', 2020)),
    );
    expect(documents.documents.length, 1);
  });

  test(
    'asset failure does not create a blank page or remove existing assets',
    () async {
      final source = JournalArchive(
        document: _page('source', 2020),
        assets: [
          ArchiveAsset(id: 'unused', mime: 'image/png', bytes: [1, 2, 3]),
        ],
      );
      // Unreferenced assets are legal and still need durable staging.
      await archives.importArchive(source);
      final keys = storage.assetKeys.toList();
      storage.failAsset = true;
      await expectLater(
        archives.importArchive(
          JournalArchive(
            document: _page('other', 2021),
            assets: [
              ArchiveAsset(id: 'new', mime: 'image/png', bytes: [4, 5, 6]),
            ],
          ),
        ),
        throwsStateError,
      );
      expect(documents.documents.length, 1);
      expect(storage.assetKeys, keys);
    },
  );
}

EntryDocument _page(String id, int year) => EntryDocument(
  id: id,
  title: 'Page',
  createdAt: DateTime.utc(year),
  modifiedAt: DateTime.utc(year),
);

class _FailingStorage extends HiveJournalDataSource {
  bool failEntry = false;
  bool failManifest = false;
  bool failAsset = false;
  @override
  Future<void> writeEntry(String id, dynamic value) {
    if (failEntry) {
      failEntry = false;
      throw StateError('disk full');
    }
    return super.writeEntry(id, value);
  }

  @override
  Future<void> writeMeta(String key, dynamic value) {
    if (failManifest && key == 'journal.manifest') {
      failManifest = false;
      throw StateError('disk full');
    }
    return super.writeMeta(key, value);
  }

  @override
  Future<void> writeAsset(String id, dynamic value) {
    if (failAsset) {
      failAsset = false;
      throw StateError('disk full');
    }
    return super.writeAsset(id, value);
  }
}
