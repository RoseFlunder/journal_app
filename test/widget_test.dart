import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:image/image.dart' as img;
import 'package:journal_app/main.dart';
import 'package:journal_app/models/entry.dart';
import 'package:journal_app/models/sticker.dart';
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
    'create a page, navigate with home/back controls, find it in TOC, delete it',
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
      expect(find.text('Cozy Bloom Journal'), findsNWidgets(2));
      expect(find.text('This journal is empty.'), findsOneWidget);
      expect(find.byTooltip('New page'), findsNothing);
      expect(find.byTooltip('Home'), findsNothing);
      expect(find.byTooltip('Previous page'), findsNothing);
      expect(find.byTooltip('Next page'), findsNothing);

      // Create the first page from the FAB.
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Animated to the new entry page (no AppBar, placeholder title).
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('Untitled page'), findsOneWidget);
      expect(find.byTooltip('Edit title'), findsNothing);
      expect(find.byTooltip('Home'), findsOneWidget);
      final home = find.byTooltip('Home');
      final topInset = MediaQuery.paddingOf(tester.element(home)).top;
      expect(tester.getTopLeft(home).dy, greaterThanOrEqualTo(topInset + 12));
      expect(find.byType(Divider), findsNothing);
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byIcon(Icons.chevron_left),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byIcon(Icons.chevron_right),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .getRect(find.text('Untitled page'))
            .overlaps(tester.getRect(find.byTooltip('Home'))),
        isFalse,
      );
      expect(find.byTooltip('Previous page (PageUp / ←)'), findsNothing);
      expect(find.byTooltip('Next page (PageDown / →)'), findsNothing);

      // Horizontal drags belong to the entry viewport and do not change pages.
      await tester.drag(find.byType(PageView), const Offset(800, 0));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);

      // Home returns to the landing page.
      await tester.tap(find.byTooltip('Home'));
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

      // System back returns to the landing page.
      await tester.binding.handlePopRoute();
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

  testWidgets('edge navigation controls follow page boundaries', (
    tester,
  ) async {
    store = JournalStore();
    await store.init();
    for (final existing in store.entries.toList()) {
      await store.deleteEntry(existing.id);
    }
    await store.addEntry();
    await store.addEntry();
    await store.addEntry();
    await tester.pumpWidget(JournalApp(store: store));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Previous page'), findsNothing);
    expect(find.byTooltip('Next page'), findsNothing);

    await tester.tap(find.text('Untitled page').first);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byIcon(Icons.chevron_left),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byIcon(Icons.chevron_right),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byIcon(Icons.chevron_left),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byIcon(Icons.chevron_right),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
  });

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
    final contentsPainter =
        tester
                .widget<CustomPaint>(
                  find.byWidgetPredicate(
                    (widget) =>
                        widget is CustomPaint &&
                        widget.painter is PaperLinesPainter,
                  ),
                )
                .painter!
            as PaperLinesPainter;
    expect(contentsPainter.showRules, isFalse);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.colorScheme.primary, PaperPage.ink);
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byType(AppBar),
              matching: find.text('Cozy Bloom Journal'),
            ),
          )
          .style
          ?.fontFamily,
      'Lora',
    );

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
    final entryPainter =
        tester
                .widget<CustomPaint>(
                  find.byWidgetPredicate(
                    (widget) =>
                        widget is CustomPaint &&
                        widget.painter is PaperLinesPainter,
                  ),
                )
                .painter!
            as PaperLinesPainter;
    expect(entryPainter.showRules, isTrue);

    expect(
      tester.widget<Text>(find.text('Untitled page')).style?.fontFamily,
      'Lora',
    );
  });

  testWidgets('workspace paper is plain while finite pages are ruled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PaperPage(finite: false, child: SizedBox.expand()),
      ),
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint && widget.painter is PaperLinesPainter,
      ),
      findsNothing,
    );

    await tester.pumpWidget(
      const MaterialApp(home: PaperPage(child: SizedBox.expand())),
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint && widget.painter is PaperLinesPainter,
      ),
      findsOneWidget,
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
    expect(find.byKey(const ValueKey('entry-title')), findsOneWidget);

    await tester.tap(find.byTooltip('Edit text'));
    await tester.pump();
    expect(find.byType(TextField), findsNWidgets(2));
    final blockId = store.entries.single.blocks.single.id;
    await tester.enterText(
      find.byKey(ValueKey('block-text-$blockId')),
      'A first note',
    );
    await tester.pump();
    expect(store.entries.single.blocks.single.text, 'A first note');
    await tester.tap(find.byTooltip('Choose font'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lora'));
    await tester.pump();
    expect(store.entries.single.blocks.single.fontFamily, JournalFonts.lora);
    expect(
      tester
          .widget<TextField>(find.byKey(ValueKey('block-text-$blockId')))
          .style
          ?.fontFamily,
      JournalFonts.lora,
    );
    await tester.tap(find.byTooltip('Choose font'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Default'));
    await tester.pump();
    expect(store.entries.single.blocks.single.fontFamily, isNull);
    await tester.tap(find.byTooltip('Toggle bold'));
    await tester.pump();
    await tester.tap(find.byTooltip('Toggle italic'));
    await tester.pump();
    await tester.tap(find.byTooltip('Increase font size'));
    await tester.pump();
    expect(store.entries.single.blocks.single.bold, isTrue);
    expect(store.entries.single.blocks.single.italic, isTrue);
    expect(store.entries.single.blocks.single.fontSize, 23);

    await tester.tap(find.byKey(const ValueKey('entry-title')));
    await tester.pump();
    await tester.tap(find.byTooltip('Choose font'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Caveat'));
    await tester.pump();
    expect(store.entries.single.titleFontFamily, JournalFonts.caveat);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('entry-title')))
          .style
          ?.fontFamily,
      JournalFonts.caveat,
    );
    await tester.tap(find.byTooltip('Choose font'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Default'));
    await tester.pump();
    expect(store.entries.single.titleFontFamily, isNull);

    await tester.tapAt(tester.getCenter(find.byType(EntryCanvas)));
    await tester.pump();
    expect(find.byKey(ValueKey('block-text-$blockId')), findsNothing);
    expect(find.byKey(const ValueKey('entry-title')), findsOneWidget);
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

  testWidgets('image blocks render and expose rotation controls', (
    tester,
  ) async {
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
              onMoveStart: (_) {},
              onMoveUpdate: (_) {},
              onMoveEnd: () {},
              onResize: (_, _) {},
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
                  onMoveStart: (_) {},
                  onMoveUpdate: (_) {},
                  onMoveEnd: () {},
                  onResize: (_, _) {},
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

  testWidgets('bundled sticker blocks render and expose transform controls', (
    tester,
  ) async {
    final definition = StickerCatalog.byId('daisy')!;
    final block = ContentBlock(
      id: 'sticker-widget',
      type: BlockType.sticker,
      stickerId: definition.id,
      w: definition.defaultSize.width,
      h: definition.defaultSize.height,
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
              imageProvider: AssetImage(definition.assetPath),
              onTap: () {},
              onEditText: () {},
              onMoveStart: (_) {},
              onMoveUpdate: (_) {},
              onMoveEnd: () {},
              onResize: (_, _) {},
              onRotate: (_) {},
              onTextChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(find.byKey(const ValueKey('rotate-sticker-widget')), findsOneWidget);
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
    expect(find.byTooltip('Edit title'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('entry-title')),
      'A new title',
    );
    await tester.pump();

    expect(store.entries.single.title, 'A new title');
    expect(find.byKey(const ValueKey('entry-title')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('entry-title')))
          .style
          ?.fontSize,
      28,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('entry-title')))
          .style
          ?.fontWeight,
      FontWeight.bold,
    );
    await tester.tap(find.byTooltip('Toggle italic'));
    await tester.pump();
    expect(store.entries.single.titleItalic, isTrue);
    await tester.tap(find.byTooltip('Decrease font size'));
    await tester.pump();
    expect(store.entries.single.titleFontSize, 26);
    for (var i = 0; i < 20; i++) {
      await tester.tap(find.byTooltip('Increase font size'));
      await tester.pump();
    }
    expect(store.entries.single.titleFontSize, 48);
    for (var i = 0; i < 30; i++) {
      await tester.tap(find.byTooltip('Decrease font size'));
      await tester.pump();
    }
    expect(store.entries.single.titleFontSize, 12);
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

    await tester.tap(find.byTooltip('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Untitled page'));
    await tester.pumpAndSettle();
    expect(find.byType(PageViewport), findsOneWidget);
    expect(store.entries.single.view?.zoom, 2);
    expect(store.entries.single.id, entry.id);
  });
  testWidgets('read-mode entry controls fade but editing keeps them visible', (
    tester,
  ) async {
    store = JournalStore();
    await store.init();
    for (final existing in store.entries.toList()) {
      await store.deleteEntry(existing.id);
    }
    await store.addEntry();
    await tester.pumpWidget(JournalApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Untitled page'));
    await tester.pumpAndSettle();

    double homeOpacity() {
      final chrome = find.ancestor(
        of: find.byTooltip('Home'),
        matching: find.byType(AnimatedOpacity),
      );
      return tester.widget<AnimatedOpacity>(chrome.first).opacity;
    }

    expect(homeOpacity(), 1);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 250));
    expect(homeOpacity(), 0);

    await tester.tapAt(const Offset(500, 300));
    await tester.pump(const Duration(milliseconds: 250));
    expect(homeOpacity(), 1);

    await tester.tap(find.byTooltip('Edit page'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(homeOpacity(), 1);
    expect(find.byTooltip('Finish editing'), findsOneWidget);

    await tester.tap(find.byTooltip('Finish editing'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 250));
    expect(homeOpacity(), 0);
  });

  testWidgets('block drag tracks multi-event touch at every canvas scale', (
    tester,
  ) async {
    Future<void> verifyAtScale(double transformScale) async {
      final block = ContentBlock(
        id: 'scaled-drag-$transformScale',
        type: BlockType.text,
        text: 'Drag me',
        x: 4,
        y: 4,
        w: 30,
        h: 20,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 800,
            height: 600,
            child: Transform.scale(
              alignment: Alignment.topLeft,
              scale: transformScale,
              child: StatefulBuilder(
                builder: (context, setState) => EntryCanvas(
                  key: ValueKey(transformScale),
                  workspaceSize: const Size(400, 300),
                  blocks: [block],
                  editing: true,
                  selectedId: block.id,
                  textEditingId: null,
                  onSelect: (_) {},
                  onEditText: (_) {},
                  onChanged: (_) => setState(() {}),
                  imageBytes: (_) => null,
                  onOpenImage: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final blockFinder = find.byType(BlockWidget);
      final beforeCenter = tester.getCenter(blockFinder);
      final beforePosition = Offset(block.x, block.y);
      final gesture = await tester.startGesture(beforeCenter);

      await gesture.moveBy(const Offset(18, 12));
      await tester.pump();
      expect(
        tester.getCenter(blockFinder) - beforeCenter,
        offsetMoreOrLessEquals(const Offset(18, 12), epsilon: 0.01),
      );

      await gesture.moveBy(const Offset(22, -4));
      await tester.pump();
      expect(
        tester.getCenter(blockFinder) - beforeCenter,
        offsetMoreOrLessEquals(const Offset(40, 8), epsilon: 0.01),
      );
      expect(
        Offset(block.x, block.y) - beforePosition,
        offsetMoreOrLessEquals(
          Offset(
            40 / (PageViewport.modelToRenderScale * transformScale),
            8 / (PageViewport.modelToRenderScale * transformScale),
          ),
          epsilon: 0.01,
        ),
      );
      await gesture.up();
    }

    await verifyAtScale(0.5);
    await verifyAtScale(1.5);
  });

  testWidgets('selected block border uses the same anchored drag path', (
    tester,
  ) async {
    final block = ContentBlock(
      id: 'border-drag',
      type: BlockType.text,
      text: 'Drag my border',
      x: 4,
      y: 4,
      w: 30,
      h: 20,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Transform.scale(
          alignment: Alignment.topLeft,
          scale: 0.5,
          child: StatefulBuilder(
            builder: (context, setState) => EntryCanvas(
              workspaceSize: const Size(400, 300),
              blocks: [block],
              editing: true,
              selectedId: block.id,
              textEditingId: null,
              onSelect: (_) {},
              onEditText: (_) {},
              onChanged: (_) => setState(() {}),
              imageBytes: (_) => null,
              onOpenImage: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final blockFinder = find.byType(BlockWidget);
    final beforeCenter = tester.getCenter(blockFinder);
    final moveEdge = find.byKey(const ValueKey('move-border-drag'));
    final gesture = await tester.startGesture(tester.getCenter(moveEdge));
    await gesture.moveBy(const Offset(24, 10));
    await tester.pump();
    expect(
      tester.getCenter(blockFinder) - beforeCenter,
      offsetMoreOrLessEquals(const Offset(24, 10), epsilon: 0.01),
    );
    await gesture.up();
  });
  testWidgets('splash wordmark fades in and is capped at 600 pixels', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(CozyBloomSplash(onRetry: () {}));
    await tester.pump();

    final image = find.byType(Image);
    expect(tester.getSize(image).width, closeTo(600, 0.1));
    final opacityFinder = find.ancestor(
      of: image,
      matching: find.byType(Opacity),
    );
    expect(tester.widget<Opacity>(opacityFinder.first).opacity, lessThan(1));

    await tester.pump(const Duration(seconds: 2));
    expect(
      tester.widget<Opacity>(opacityFinder.first).opacity,
      closeTo(1, 0.01),
    );
  });
}
