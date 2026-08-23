import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:journal_app/models/entry.dart';
import 'package:journal_app/services/journal_store.dart';

void main() {
  group('Entry JSON', () {
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
          ),
        ],
        music: 'asset1',
        view: ViewState(zoom: 1.5, panX: 2, panY: -3),
      );
      final decoded = Entry.fromJson(entry.toJson());

      expect(decoded.id, 'abc');
      expect(decoded.title, 'Hello');
      expect(decoded.createdAt, DateTime.utc(2025, 8, 22, 12, 30));
      expect(decoded.music, 'asset1');
      expect(decoded.view?.zoom, 1.5);
      expect(decoded.view?.panY, -3);
      final block = decoded.blocks.single;
      expect(block.id, 'b1');
      expect(block.type, BlockType.text);
      expect(block.text, 'hi');
      expect(block.w, 30);
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
      return store;
    }

    test('add, update, delete and persistence', () async {
      var store = await freshStore();

      final a = store.addEntry();
      final b = store.addEntry();
      expect(store.entries.map((e) => e.id).toList(), [a.id, b.id]);
      expect(store.entries[0].title, '');

      store.updateEntry(b.id, (e) => e.title = 'Second');
      expect(store.entries[1].title, 'Second');

      final assetId =
          await store.addAsset(b.id, AssetKind.image, 'image/jpeg', [1, 2, 3]);
      expect(store.getAsset(assetId), Uint8List.fromList([1, 2, 3]));
      expect(store.getAssetMime(assetId), 'image/jpeg');

      // Deleting b also removes its assets.
      store.deleteEntry(b.id);
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
  });
}
