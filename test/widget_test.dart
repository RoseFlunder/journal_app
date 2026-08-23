import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:image/image.dart' as img;
import 'package:journal_app/main.dart';
import 'package:journal_app/models/entry.dart';
import 'package:journal_app/services/journal_store.dart';
import 'package:journal_app/editor/block_widget.dart';
import 'package:journal_app/editor/entry_canvas.dart';
import 'package:journal_app/widgets/paper_page.dart';
import 'package:journal_app/widgets/page_viewport.dart';

void main() {
  // This test exercises real file I/O (Hive) by design. The default
  // (automated) binding runs the test body in a FakeAsync zone, which
  // strands real-IO continuations and makes Hive hang. The live binding
  // runs everything on the real event loop, so plain awaits just work.
  // Cost: animations take real wall-clock time (test is a bit slower).
  LiveTestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late JournalStore store;

  setUpAll(() async {
    temp = Directory.systemTemp.createTempSync('journal_widget_test');
    Hive.init(temp.path);
  });

  tearDownAll(() async {
    await Hive.close();
    temp.deleteSync(recursive: true);
  });

  testWidgets(
    'create a page, navigate with the drawer, find it in TOC, delete it',
    (tester) async {
      store = JournalStore();
      await store.init();
      await tester.pumpWidget(JournalApp(store: store));
      await tester.pumpAndSettle();

      expect(
        tester.widget<PageView>(find.byType(PageView)).physics,
        isA<NeverScrollableScrollPhysics>(),
      );

      // Starts on the (empty) table of contents.
      expect(find.text('Journal'), findsOneWidget);
      expect(find.text('This journal is empty.'), findsOneWidget);

      // Create the first page from the FAB.
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Animated to the new entry page (no AppBar, placeholder title).
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('Untitled page'), findsOneWidget);

      // Horizontal drags belong to the entry viewport and do not change pages.
      await tester.drag(find.byType(PageView), const Offset(800, 0));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);

      // Open navigation and return to the table of contents.
      await tester.tap(find.byTooltip('Open page navigation'));
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(Drawer),
          matching: find.text('Contents'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('This journal is empty.'), findsNothing);
      // The entry now appears as a TOC row.
      expect(find.text('Untitled page'), findsOneWidget);

      // Tap the row to jump to the page.
      await tester.tap(find.text('Untitled page'));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('Untitled page'), findsOneWidget);

      // Open navigation from the entry page and return to the TOC.
      await tester.tap(find.byTooltip('Open page navigation'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(Drawer),
          matching: find.text('Contents'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete page'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Back to the empty state.
      expect(find.text('This journal is empty.'), findsOneWidget);
      expect(store.entries, isEmpty);
    },
  );

  testWidgets('M2 paper theme renders on the contents and entry pages', (
    tester,
  ) async {
    store = JournalStore();
    await store.init();
    await tester.pumpWidget(JournalApp(store: store));
    await tester.pumpAndSettle();

    expect(find.byType(PaperPage), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint && widget.painter is PaperLinesPainter,
      ),
      findsOneWidget,
    );
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.colorScheme.primary, PaperPage.ink);
    expect(tester.widget<Text>(find.text('Journal')).style?.fontFamily, 'Lora');

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.byType(PaperPage), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint && widget.painter is PaperLinesPainter,
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.text('Untitled page')).style?.fontFamily,
      'Lora',
    );
  });

  testWidgets('M4 adds, edits, resizes and deletes text blocks', (
    tester,
  ) async {
    store = JournalStore();
    await store.init();
    for (final existing in store.entries.toList()) {
      await store.deleteEntry(existing.id);
    }
    await tester.pumpWidget(JournalApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit page'));
    await tester.pump();
    await tester.tap(find.byTooltip('Add text'));
    await tester.pumpAndSettle();
    expect(find.byType(EntryCanvas), findsOneWidget);
    expect(find.byType(BlockWidget), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.byTooltip('Edit text'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'A first note');
    await tester.pump();
    expect(store.entries.single.blocks.single.text, 'A first note');

    await tester.tapAt(tester.getCenter(find.byType(EntryCanvas)));
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(BlockWidget), findsOneWidget);

    final canvasCenter = tester.getCenter(find.byType(EntryCanvas));
    await tester.dragFrom(canvasCenter, const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(store.entries.single.view?.panX, isNot(0));

    expect(find.byTooltip('Reset view'), findsOneWidget);
    await tester.tap(find.byTooltip('Reset view'));
    await tester.pump(const Duration(milliseconds: 300));

    final beforeX = store.entries.single.blocks.single.x;
    await tester.drag(
      find.byKey(ValueKey('move-${store.entries.single.blocks.single.id}')),
      const Offset(24, 0),
    );
    await tester.pump();
    expect(store.entries.single.blocks.single.x, greaterThan(beforeX));

    final beforeWidth = store.entries.single.blocks.single.w;
    await tester.drag(
      find.byKey(ValueKey('resize-${store.entries.single.blocks.single.id}')),
      const Offset(40, 20),
    );
    await tester.pump();
    expect(store.entries.single.blocks.single.w, greaterThan(beforeWidth));

    await tester.tap(find.byIcon(Icons.delete_outline).last);
    await tester.pump();
    expect(store.entries.single.blocks, isEmpty);
  });

  testWidgets('image blocks render and expose rotation controls', (tester) async {
    var rotation = 0.0;
    final block = ContentBlock(
      id: 'image-widget',
      type: BlockType.image,
      assetId: 'asset-1',
      w: 120,
      h: 80,
    );
    final bytes = Uint8List.fromList(
      img.encodePng(img.Image(width: 2, height: 1)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 240,
          height: 200,
          child: Padding(
            padding: const EdgeInsets.only(top: 60),
            child: BlockWidget(
              block: block,
              selected: true,
              editing: true,
              textEditing: false,
              imageBytes: bytes,
              onTap: () {},
              onEditText: () {},
              onMove: (_) {},
              onResize: (_) {},
              onRotate: (delta) => rotation += delta,
              onTextChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(find.byKey(const ValueKey('rotate-image-widget')), findsOneWidget);
    expect(rotation, 0);
  });

  testWidgets('image provider remains stable across rebuilds', (tester) async {
    final bytes = Uint8List.fromList(
      img.encodePng(img.Image(width: 2, height: 1)),
    );
    final provider = MemoryImage(bytes);
    var rebuild = 0;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          home: Column(
            children: [
              Text('$rebuild'),
              SizedBox(
                width: 120,
                height: 80,
                child: BlockWidget(
                  block: ContentBlock(
                    id: 'stable-image',
                    type: BlockType.image,
                    w: 120,
                    h: 80,
                  ),
                  selected: false,
                  editing: false,
                  textEditing: false,
                  imageProvider: provider,
                  onTap: () {},
                  onEditText: () {},
                  onMove: (_) {},
                  onResize: (_) {},
                  onRotate: (_) {},
                  onTextChanged: (_) {},
                ),
              ),
              ElevatedButton(
                onPressed: () => setState(() => rebuild++),
                child: const Text('rebuild'),
              ),
            ],
          ),
        ),
      ),
    );
    final before = tester.widget<Image>(find.byType(Image)).image;
    await tester.tap(find.text('rebuild'));
    await tester.pump();
    final after = tester.widget<Image>(find.byType(Image)).image;

    expect(identical(before, after), isTrue);
  });

  testWidgets('entry title is editable and loads near the top left', (
    tester,
  ) async {
    store = JournalStore();
    await store.init();
    for (final existing in store.entries.toList()) {
      await store.deleteEntry(existing.id);
    }
    await tester.pumpWidget(JournalApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    final title = find.text('Untitled page');
    expect(tester.getTopLeft(title).dx, lessThan(400));
    expect(tester.getTopLeft(title).dy, lessThan(300));

    await tester.tap(find.byTooltip('Edit page'));
    await tester.pump();
    await tester.tap(find.byTooltip('Edit title'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('entry-title')),
      'A new title',
    );
    await tester.pump();

    expect(store.entries.single.title, 'A new title');
    expect(find.byKey(const ValueKey('entry-title')), findsOneWidget);
  });

  testWidgets('entry viewport view state survives leaving and reopening', (
    tester,
  ) async {
    store = JournalStore();
    await store.init();
    for (final existing in store.entries.toList()) {
      await store.deleteEntry(existing.id);
    }
    await tester.pumpWidget(JournalApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    final entry = store.entries.single;

    await store.updateEntry(entry.id, (entry) {
      entry.view = ViewState(zoom: 2, panX: 12, panY: 18);
    });
    await tester.pump(const Duration(milliseconds: 350));
    expect(store.entries.single.view?.zoom, 2);

    await tester.tap(find.byTooltip('Open page navigation'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(Drawer), matching: find.text('Contents')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Untitled page'));
    await tester.pumpAndSettle();
    expect(find.byType(PageViewport), findsOneWidget);
    expect(store.entries.single.view?.zoom, 2);
    expect(store.entries.single.id, entry.id);
  });
}
