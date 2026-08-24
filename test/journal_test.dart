import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:image/image.dart' as img;
import 'package:journal_app/models/entry.dart';
import 'package:journal_app/models/sticker.dart';
import 'package:journal_app/models/document.dart';
import 'package:journal_app/models/template.dart';
import 'package:journal_app/services/image_source.dart';
import 'package:journal_app/services/journal_store.dart';
import 'package:journal_app/services/repositories.dart';

void main() {
  group('Entry JSON', () {
    test('bounds initial image size while preserving aspect ratio', () {
      final portrait = imageBlockSize(800, 2400);
      final landscape = imageBlockSize(2400, 800);
      final square = imageBlockSize(1000, 1000);

      expect(portrait.width, closeTo(16, 0.001));
      expect(portrait.height, closeTo(48, 0.001));
      expect(landscape.width, closeTo(64, 0.001));
      expect(landscape.height, closeTo(21.3333, 0.001));
      expect(square.width, closeTo(48, 0.001));
      expect(square.height, closeTo(48, 0.001));
    });

    test('defaults rotation for older saved blocks', () {
      final block = ContentBlock.fromJson({'id': 'legacy', 'type': 'text'});

      expect(block.rotation, 0);
      expect(block.fontSize, 21);
      expect(block.fontFamily, isNull);
      expect(block.textColorValue, isNull);
      expect(block.bold, isFalse);
      expect(block.italic, isFalse);
    });

    test('defaults missing title font family for older entries', () {
      final entry = Entry.fromJson({
        'id': 'legacy-entry',
        'createdAt': '2025-08-22T12:30:00.000Z',
      });

      expect(entry.titleFontFamily, isNull);
      expect(entry.titleTextColorValue, isNull);
    });

    test('round-trips all fields', () {
      final entry = Entry(
        id: 'abc',
        createdAt: DateTime.utc(2025, 8, 22, 12, 30),
        title: 'Hello',
        blocks: [
          ContentBlock(
            id: 'b1',
            type: BlockType.text,
            text: 'hi',
            x: 1,
            y: 2,
            w: 30,
            h: 10,
            rotation: 0.35,
            fontSize: 26,
            fontFamily: JournalFonts.lora,
            textColorValue: 0xFF873F4D,
            bold: true,
            italic: true,
          ),
        ],
        music: 'asset1',
        view: ViewState(zoom: 1.5, panX: 2, panY: -3),
        titleFontSize: 34,
        titleFontFamily: JournalFonts.caveat,
        titleTextColorValue: 0xFF3E5E86,
        titleBold: false,
        titleItalic: true,
      );
      final decoded = Entry.fromJson(entry.toJson());

      expect(decoded.id, 'abc');
      expect(decoded.title, 'Hello');
      expect(decoded.createdAt, DateTime.utc(2025, 8, 22, 12, 30));
      expect(decoded.music, 'asset1');
      expect(decoded.view?.zoom, 1.5);
      expect(decoded.view?.panY, -3);
      expect(decoded.titleFontSize, 34);
      expect(decoded.titleFontFamily, JournalFonts.caveat);
      expect(decoded.titleTextColorValue, 0xFF3E5E86);
      expect(decoded.titleBold, isFalse);
      expect(decoded.titleItalic, isTrue);
      final block = decoded.blocks.single;
      expect(block.id, 'b1');
      expect(block.type, BlockType.text);
      expect(block.text, 'hi');
      expect(block.w, 30);
      expect(block.rotation, closeTo(0.35, 0.0001));
      expect(block.fontSize, 26);
      expect(block.fontFamily, JournalFonts.lora);
      expect(block.textColorValue, 0xFF873F4D);
      expect(block.bold, isTrue);
      expect(block.italic, isTrue);
    });

    test('round-trips image block fields', () {
      final entry = Entry(
        id: 'image-entry',
        createdAt: DateTime.utc(2025),
        blocks: [
          ContentBlock(
            id: 'image-block',
            type: BlockType.image,
            assetId: 'asset-1',
            w: 80,
            h: 45,
            rotation: 0.5,
          ),
        ],
      );

      final block = Entry.fromJson(entry.toJson()).blocks.single;

      expect(block.type, BlockType.image);
      expect(block.assetId, 'asset-1');
      expect(block.w, 80);
      expect(block.h, 45);
      expect(block.rotation, closeTo(0.5, 0.0001));
    });

    test('round-trips sticker blocks and resolves the bundled catalog', () {
      final entry = Entry(
        id: 'sticker-entry',
        createdAt: DateTime.utc(2025),
        blocks: [
          ContentBlock(
            id: 'sticker-block',
            type: BlockType.sticker,
            stickerId: 'daisy',
            w: 28,
            h: 28,
            rotation: -0.2,
          ),
        ],
      );

      final block = Entry.fromJson(entry.toJson()).blocks.single;

      expect(block.type, BlockType.sticker);
      expect(block.stickerId, 'daisy');
      expect(StickerCatalog.byId(block.stickerId)?.label, 'Daisy');
      expect(StickerCatalog.byId('missing'), isNull);
    });

    test(
      'downscales images to the maximum side and preserves aspect ratio',
      () {
        final source = img.Image(width: 2000, height: 1000);
        final bytes = Uint8List.fromList(img.encodePng(source));

        final result = const ImageProcessor().process(bytes);
        final decoded = img.decodeImage(result.bytes)!;

        expect(result.mime, 'image/jpeg');
        expect(result.width, 1600);
        expect(result.height, 800);
        expect(decoded.width, 1600);
        expect(decoded.height, 800);
      },
    );

    test('rejects invalid image bytes', () {
      expect(
        () => const ImageProcessor().process(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
    });

    test('tolerates missing optional fields', () {
      final decoded = Entry.fromJson({
        'id': 'x',
        'createdAt': DateTime.utc(2025).toIso8601String(),
      });
      expect(decoded.title, '');
      expect(decoded.blocks, isEmpty);
      expect(decoded.music, isNull);
      expect(decoded.view, isNull);
      expect(decoded.titleFontSize, 28);
      expect(decoded.titleBold, isTrue);
      expect(decoded.titleItalic, isFalse);
      expect(decoded.blocks, isEmpty);
    });
  });

  group('JournalStore', () {
    late Directory temp;

    setUpAll(() {
      temp = Directory.systemTemp.createTempSync('journal_test');
      Hive.init(temp.path);
    });

    tearDownAll(() async {
      await Hive.close();
      temp.deleteSync(recursive: true);
    });

    Future<JournalStore> freshStore() async {
      final store = JournalStore();
      await store.init();
      // Start every run from an empty journal.
      await Hive.box('entries').clear();
      await Hive.box('assets').clear();
      await Hive.box('meta').clear();
      await Hive.box('entryCheckpoints').clear();
      await Hive.box('journalTemplates').clear();
      return store;
    }

    test(
      'repository facade round-trips documents, assets, and templates',
      () async {
        final store = await freshStore();
        final repository = HiveJournalRepository(store);
        final document = await repository.createDocument(
          title: 'Repository page',
        );
        expect(repository.documents.single.title, 'Repository page');

        final node = CanvasNode.fromBlock(
          ContentBlock(
            id: 'repo-text',
            type: BlockType.text,
            text: 'Saved through the repository',
            x: -12,
            y: 7,
            w: 40,
            h: 18,
          ),
        );
        final updated = EntryDocument(
          id: document.id,
          title: document.title,
          createdAt: document.createdAt,
          modifiedAt: DateTime.now(),
          nodes: [node],
          board: const BoardSettings(gridVisible: true),
        );
        await repository.saveDocument(updated);
        expect(repository.documents.single.nodes.single.transform.x, -12);
        expect(repository.documents.single.board.gridVisible, isTrue);

        final asset = await repository.putAsset(
          document.id,
          AssetKind.image,
          'image/png',
          [1, 2, 3],
        );
        expect(repository.readAsset(asset), [1, 2, 3]);

        final template = JournalTemplate(
          id: 'template-1',
          name: 'Starter',
          document: updated,
          createdAt: DateTime.utc(2026),
        );
        await repository.saveTemplate(template);
        expect(repository.templates.single.name, 'Starter');
        await repository.deleteTemplate(template.id);
        expect(repository.templates, isEmpty);
        await repository.deleteDocument(document.id);
        expect(repository.documents, isEmpty);
      },
    );

    test('add, update, delete and persistence', () async {
      var store = await freshStore();

      final a = await store.addEntry();
      final b = await store.addEntry();
      expect(store.entries.map((e) => e.id).toList(), [a.id, b.id]);
      expect(store.entries[0].title, '');

      await store.updateEntry(b.id, (e) => e.title = 'Second');
      expect(store.entries[1].title, 'Second');

      final assetId = await store.addAsset(
        b.id,
        AssetKind.image,
        'image/jpeg',
        [1, 2, 3],
      );
      expect(store.getAsset(assetId), Uint8List.fromList([1, 2, 3]));
      expect(store.getAssetMime(assetId), 'image/jpeg');

      // Deleting b also removes its assets.
      await store.deleteEntry(b.id);
      expect(store.entries.map((e) => e.id).toList(), [a.id]);
      expect(store.getAsset(assetId), isNull);

      // Close everything and reopen: data must come back from disk,
      // in the right order.
      await Hive.box('entries').close();
      await Hive.box('assets').close();
      await Hive.box('meta').close();
      store = await freshStore();

      expect(store.entries.map((e) => e.id).toList(), [a.id]);
      expect(store.entries.first.id, a.id);
    });

    test('persists a mutation across an immediate reopen', () async {
      var store = await freshStore();
      final entry = await store.addEntry();
      await store.updateEntry(entry.id, (entry) => entry.title = 'Persisted');

      await Hive.box('entries').close();
      await Hive.box('assets').close();
      await Hive.box('meta').close();

      store = JournalStore();
      await store.init();

      expect(store.entries.map((entry) => entry.id), [entry.id]);
      expect(store.entries.single.title, 'Persisted');
    });

    test('loads entries when order metadata is missing', () async {
      await freshStore();
      final entry = Entry(
        id: 'recovered-entry',
        createdAt: DateTime.utc(2025),
        title: 'Recovered',
      );
      await Hive.box('entries').put(entry.id, entry.toJson());

      final store = JournalStore();
      await store.init();

      expect(store.entries.map((entry) => entry.id), [entry.id]);
      expect(store.entries.single.title, 'Recovered');
    });

    test('loads nested Hive maps with dynamic keys', () async {
      final store = await freshStore();
      final entry = Entry(
        id: 'dynamic-map-entry',
        createdAt: DateTime.utc(2025),
        blocks: [
          ContentBlock(id: 'block', type: BlockType.text, text: 'Loaded'),
        ],
        view: ViewState(zoom: 2, panX: 4, panY: 5),
      );
      await Hive.box('entries').put(entry.id, <String, dynamic>{
        ...entry.toJson(),
        'blocks': [
          <dynamic, dynamic>{...entry.blocks.single.toJson()},
        ],
        'view': <dynamic, dynamic>{...entry.view!.toJson()},
      });
      await Hive.box('meta').put('entryOrder', [entry.id]);
      await Hive.box('entries').flush();
      await Hive.box('meta').flush();

      final reloaded = JournalStore();
      await reloaded.init();

      expect(reloaded.entries.single.blocks.single.text, 'Loaded');
      expect(reloaded.entries.single.view?.panY, 5);
      // Keep the local store alive until its boxes have been read.
      expect(store.isLoaded, isTrue);
    });
  });
}
