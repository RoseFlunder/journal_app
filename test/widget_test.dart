import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
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

  Future<void> createPageFromFab(
    WidgetTester tester, {
    String title = 'Untitled page',
  }) async {
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('new-page-title')), title);
    await tester.pump();
    await tester.tap(find.text('Create page'));
    await tester.pumpAndSettle();
  }

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

      // A title is required; cancelling leaves no empty/untitled entry.
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.text('Name your journal page'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Create page'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.entries, isEmpty);

      // Create the first page from the FAB.
      await createPageFromFab(tester);

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

    await createPageFromFab(tester);
    expect(find.byType(PaperPage), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint && widget.painter is PaperLinesPainter,
      ),
      findsOneWidget,
    );
    final boardPainter =
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
    expect(boardPainter.showRules, isTrue);
    expect(boardPainter.showMargin, isTrue);

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
    await createPageFromFab(tester);

    await tester.tap(find.byTooltip('Edit page'));
    await tester.pump();
    await tester.tap(find.byTooltip('Add text'));
    await tester.pumpAndSettle();
    expect(find.byType(EntryCanvas), findsOneWidget);
    expect(find.byType(BlockWidget), findsOneWidget);
    expect(find.byKey(const ValueKey('entry-title')), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    final blockId = store.entries.single.blocks.single.id;
    expect(store.entries.single.blocks.single.w, 30);
    expect(store.entries.single.blocks.single.h, 11);
    expect(store.entries.single.blocks.single.fontSize, 26);
    expect(find.byKey(ValueKey('block-text-$blockId')), findsOneWidget);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.byTooltip('Edit text'));
    await tester.pump();
    expect(find.byKey(ValueKey('block-text-$blockId')), findsNothing);
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.tap(find.byTooltip('Edit text'));
    await tester.pump();
    expect(find.byKey(ValueKey('block-text-$blockId')), findsOneWidget);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.enterText(
      find.byKey(ValueKey('block-text-$blockId')),
      'A first note',
    );
    await tester.pump();
    expect(store.entries.single.blocks.single.richTextDelta, isNotNull);
    expect(
      store.entries.single.blocks.single.richTextDelta!.whereType<Map>().any(
        (operation) => operation['insert'] == 'A first note',
      ),
      isTrue,
    );
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
    expect(store.entries.single.blocks.single.fontSize, 28);

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

    await tester.tap(find.text('A first note'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('A first note'));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('block-text-$blockId')), findsOneWidget);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.byTooltip('Edit text'));
    await tester.pump();
    expect(find.byKey(ValueKey('block-text-$blockId')), findsNothing);

    final canvasCenter = tester.getCenter(find.byType(EntryCanvas));
    await tester.dragFrom(canvasCenter, const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(store.entries.single.view?.panX, isNot(0));

    expect(find.byTooltip('Fit content'), findsOneWidget);
    await tester.tap(find.byTooltip('Fit content'));
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

  testWidgets('formatted Delta text blocks use the Quill editor', (
    tester,
  ) async {
    final block = ContentBlock(
      id: 'rich-text-widget',
      type: BlockType.text,
      text: 'Bold note',
      richTextDelta: const [
        {
          'insert': 'Bold note',
          'attributes': {'bold': true},
        },
        {'insert': '\n'},
      ],
      w: 160,
      h: 80,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 240,
          height: 160,
          child: BlockWidget(
            block: block,
            selected: true,
            editing: true,
            textEditing: true,
            onTap: () {},
            onEditText: () {},
            onMoveStart: (_) {},
            onMoveUpdate: (_) {},
            onMoveEnd: () {},
            onRotate: (_) {},
            onTextChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(QuillEditor), findsOneWidget);
  });

  testWidgets('draw mode commits one vector ink stroke', (tester) async {
    ContentBlock? drawn;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: EntryCanvas(
            workspaceSize: const Size(400, 300),
            blocks: const [],
            editing: true,
            drawMode: true,
            selectedId: null,
            textEditingId: null,
            onSelect: (_) {},
            onEditText: (_) {},
            onChanged: (_) {},
            onInkCreated: (block) => drawn = block,
            imageBytes: (_) => null,
            onOpenImage: (_) {},
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(const Offset(120, 110));
    await gesture.moveBy(const Offset(24, 12));
    await gesture.moveBy(const Offset(18, 18));
    await gesture.up();
    await tester.pump();

    expect(drawn?.type, BlockType.ink);
    expect(drawn?.inkPoints, hasLength(3));
    expect(drawn?.w, greaterThanOrEqualTo(16));
    expect(drawn?.h, greaterThanOrEqualTo(10));
  });

  testWidgets('text color picker applies preset, custom, and default colors', (
    tester,
  ) async {
    store = JournalStore();
    await store.init();
    for (final existing in store.entries.toList()) {
      await store.deleteEntry(existing.id);
    }
    await tester.pumpWidget(JournalApp(store: store));
    await tester.pumpAndSettle();
    await createPageFromFab(tester);
    await tester.tap(find.byTooltip('Edit page'));
    await tester.pump();
    await tester.tap(find.byTooltip('Add text'));
    await tester.pumpAndSettle();

    final blockId = store.entries.single.blocks.single.id;
    await tester.enterText(
      find.byKey(ValueKey('block-text-$blockId')),
      'Colorful note',
    );
    await tester.tap(find.byTooltip('Text color'));
    await tester.pumpAndSettle();
    expect(find.text('Text color'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Berry'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(store.entries.single.blocks.single.textColorValue, 0xFF873F4D);
    expect(
      tester
          .widget<TextField>(find.byKey(ValueKey('block-text-$blockId')))
          .style
          ?.color
          ?.toARGB32(),
      0xFF873F4D,
    );

    await tester.tap(find.byKey(const ValueKey('entry-title')));
    await tester.pump();
    await tester.tap(find.byTooltip('Text color'));
    await tester.pumpAndSettle();
    final dialogFields = find.byType(TextField);
    await tester.enterText(dialogFields.last, '123456');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(store.entries.single.titleTextColorValue, 0xFF123456);

    await tester.tap(find.byTooltip('Text color'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Default ink'));
    await tester.pumpAndSettle();
    expect(store.entries.single.titleTextColorValue, isNull);
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

  testWidgets('entry title is editable and centered at the top of the page', (
    tester,
  ) async {
    store = JournalStore();
    await store.init();
    for (final existing in store.entries.toList()) {
      await store.deleteEntry(existing.id);
    }
    await tester.pumpWidget(JournalApp(store: store));
    await tester.pumpAndSettle();
    await createPageFromFab(tester);

    final title = find.text('Untitled page');
    final titleRect = tester.getRect(title);
    expect(titleRect.center.dx, closeTo(400, 2));
    expect(tester.getTopLeft(title).dy, lessThan(300));

    await tester.tap(find.byTooltip('Edit page'));
    await tester.pump();
    expect(find.byTooltip('Edit title'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('entry-title')),
      'A new title',
    );
    await tester.pump();

    // Formatting is contextual: focus the title before changing its style.
    await tester.tap(find.byKey(const ValueKey('entry-title')));
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
    await createPageFromFab(tester);
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

  testWidgets('rotate handle can be hidden for mobile presentation', (
    tester,
  ) async {
    final block = ContentBlock(
      id: 'platform-rotation',
      type: BlockType.text,
      text: 'Rotate me',
      w: 30,
      h: 20,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 240,
          height: 200,
          child: BlockWidget(
            block: block,
            selected: true,
            editing: true,
            textEditing: false,
            showRotateHandle: false,
            onTap: () {},
            onEditText: () {},
            onMoveStart: (_) {},
            onMoveUpdate: (_) {},
            onMoveEnd: () {},
            onRotate: (_) {},
            onTextChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('rotate-platform-rotation')),
      findsNothing,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 240,
          height: 200,
          child: BlockWidget(
            block: block,
            selected: true,
            editing: true,
            textEditing: false,
            showRotateHandle: true,
            onTap: () {},
            onEditText: () {},
            onMoveStart: (_) {},
            onMoveUpdate: (_) {},
            onMoveEnd: () {},
            onRotate: (_) {},
            onTextChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('rotate-platform-rotation')),
      findsOneWidget,
    );
  });

  testWidgets(
    'two fingers on separate selected blocks rotate the selection once',
    (tester) async {
      final first = ContentBlock(
        id: 'rotation-first',
        type: BlockType.text,
        text: 'First',
        x: 10,
        y: 10,
        w: 20,
        h: 10,
      );
      final second = ContentBlock(
        id: 'rotation-second',
        type: BlockType.text,
        text: 'Second',
        x: 50,
        y: 10,
        w: 20,
        h: 10,
      );
      final deltas = <double>[];
      var starts = 0;
      var ends = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: EntryCanvas(
            workspaceSize: const Size(800, 400),
            blocks: [first, second],
            editing: true,
            selectedId: first.id,
            selectedIds: {first.id, second.id},
            textEditingId: null,
            onSelect: (_) {},
            onEditText: (_) {},
            onChanged: (_) {},
            onRotateSelection: deltas.add,
            onInteractionStart: () => starts++,
            onInteractionEnd: () => ends++,
            imageBytes: (_) => null,
            onOpenImage: (_) {},
          ),
        ),
      );
      await tester.pump();

      final oneFinger = await tester.startGesture(
        const Offset(200, 150),
        pointer: 3,
      );
      await oneFinger.moveBy(const Offset(0, 40));
      await tester.pump();
      expect(deltas, isEmpty);
      await oneFinger.up();

      final outsideFirst = await tester.startGesture(
        const Offset(40, 40),
        pointer: 4,
      );
      final outsideSecond = await tester.startGesture(
        const Offset(760, 360),
        pointer: 5,
      );
      await outsideSecond.moveBy(const Offset(0, -40));
      await tester.pump();
      expect(deltas, isEmpty);
      await outsideSecond.up();
      await outsideFirst.up();
      starts = 0;
      ends = 0;

      final firstFinger = await tester.startGesture(
        const Offset(200, 150),
        pointer: 1,
      );
      final secondFinger = await tester.startGesture(
        const Offset(600, 150),
        pointer: 2,
      );
      await secondFinger.moveBy(const Offset(0, 100));
      await tester.pump();

      expect(deltas, isNotEmpty);
      expect(starts, 1);
      expect(first.x, 10);
      expect(second.x, 50);

      await secondFinger.up();
      await firstFinger.up();
      await tester.pump();
      expect(ends, 1);
    },
  );

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

  testWidgets('resize handle tracks multi-event touch at every canvas scale', (
    tester,
  ) async {
    Future<void> verifyAtScale(double transformScale) async {
      final block = ContentBlock(
        id: 'scaled-resize-$transformScale',
        type: BlockType.text,
        text: 'Resize me',
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
                  key: ValueKey('resize-$transformScale'),
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

      final resizeHandle = find.byKey(ValueKey('resize-${block.id}'));
      final beforeHandleCenter = tester.getCenter(resizeHandle);
      final beforeSize = Size(block.w, block.h);
      final gesture = await tester.startGesture(beforeHandleCenter);

      await gesture.moveBy(const Offset(18, 12));
      await tester.pump();
      expect(
        tester.getCenter(resizeHandle) - beforeHandleCenter,
        offsetMoreOrLessEquals(const Offset(18, 12), epsilon: 0.01),
      );

      await gesture.moveBy(const Offset(22, -4));
      await tester.pump();
      expect(
        tester.getCenter(resizeHandle) - beforeHandleCenter,
        offsetMoreOrLessEquals(const Offset(40, 8), epsilon: 0.01),
      );
      expect(
        Offset(block.w - beforeSize.width, block.h - beforeSize.height),
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

  testWidgets('viewport resize stays stable for rotated blocks', (
    tester,
  ) async {
    Future<void> verifyAtZoom(double zoom) async {
      final block = ContentBlock(
        id: 'viewport-resize-$zoom',
        type: BlockType.text,
        text: 'Rotate and resize',
        x: -10,
        y: -8,
        w: 30,
        h: 20,
        rotation: math.pi / 6,
      );
      var resizeActive = false;

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 800,
            height: 600,
            child: StatefulBuilder(
              builder: (context, setState) => PageViewport(
                canvasSize: const Size(400, 300),
                fitSize: const Size(400, 300),
                initialView: ViewState(zoom: zoom),
                gesturesEnabled: !resizeActive,
                child: EntryCanvas(
                  workspaceSize: const Size(400, 300),
                  blocks: [block],
                  editing: true,
                  selectedId: block.id,
                  textEditingId: null,
                  onSelect: (_) {},
                  onEditText: (_) {},
                  onResizeActiveChanged: (active) =>
                      setState(() => resizeActive = active),
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
      await tester.pump();

      final handle = find.byKey(ValueKey('resize-${block.id}'));
      final beforeHandleCenter = tester.getCenter(handle);
      final beforeCenter = Offset(block.x + block.w / 2, block.y + block.h / 2);
      final beforeHalf = Offset(block.w / 2, block.h / 2);
      final beforeOpposite =
          beforeCenter -
          Offset(
            beforeHalf.dx * math.cos(block.rotation) -
                beforeHalf.dy * math.sin(block.rotation),
            beforeHalf.dx * math.sin(block.rotation) +
                beforeHalf.dy * math.cos(block.rotation),
          );
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final beforeScale = viewer.transformationController!.value
          .getMaxScaleOnAxis();
      final beforeTranslation = viewer.transformationController!.value
          .getTranslation();
      final gesture = await tester.startGesture(beforeHandleCenter);

      await gesture.moveBy(const Offset(18, 12));
      await tester.pump();
      expect(resizeActive, isTrue);
      expect(
        tester.getCenter(handle) - beforeHandleCenter,
        offsetMoreOrLessEquals(const Offset(18, 12), epsilon: 0.1),
      );
      expect(
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .panEnabled,
        isFalse,
      );

      await gesture.moveBy(const Offset(22, -4));
      await tester.pump();
      expect(
        tester.getCenter(handle) - beforeHandleCenter,
        offsetMoreOrLessEquals(const Offset(40, 8), epsilon: 0.1),
      );
      final afterCenter = Offset(block.x + block.w / 2, block.y + block.h / 2);
      final afterHalf = Offset(block.w / 2, block.h / 2);
      final afterOpposite =
          afterCenter -
          Offset(
            afterHalf.dx * math.cos(block.rotation) -
                afterHalf.dy * math.sin(block.rotation),
            afterHalf.dx * math.sin(block.rotation) +
                afterHalf.dy * math.cos(block.rotation),
          );
      expect(afterOpposite.dx, closeTo(beforeOpposite.dx, 0.001));
      expect(afterOpposite.dy, closeTo(beforeOpposite.dy, 0.001));
      await gesture.up();
      await tester.pump();

      final afterViewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final afterTransform = afterViewer.transformationController!.value;
      final afterTranslation = afterTransform.getTranslation();
      expect(resizeActive, isFalse);
      expect(afterTransform.getMaxScaleOnAxis(), closeTo(beforeScale, 0.001));
      expect(afterTranslation.x, closeTo(beforeTranslation.x, 0.01));
      expect(afterTranslation.y, closeTo(beforeTranslation.y, 0.01));
    }

    await verifyAtZoom(0.5);
    await verifyAtZoom(1.5);
  });

  testWidgets('visual resize preserves aspect ratio and clamps minimum size', (
    tester,
  ) async {
    for (final type in [BlockType.image, BlockType.sticker]) {
      final block = ContentBlock(
        id: 'visual-resize-${type.name}',
        type: type,
        w: 30,
        h: 20,
        stickerId: type == BlockType.sticker ? 'daisy' : null,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 800,
            height: 600,
            child: EntryCanvas(
              workspaceSize: const Size(400, 300),
              blocks: [block],
              editing: true,
              selectedId: block.id,
              textEditingId: null,
              onSelect: (_) {},
              onEditText: (_) {},
              onChanged: (_) {},
              imageBytes: (_) => null,
              onOpenImage: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      final handle = find.byKey(ValueKey('resize-${block.id}'));
      final beforeCenter = Offset(block.x + block.w / 2, block.y + block.h / 2);
      final beforeOpposite = beforeCenter - Offset(block.w / 2, block.h / 2);
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await gesture.moveBy(const Offset(-500, -300));
      await tester.pump();
      await gesture.up();

      expect(block.w, greaterThanOrEqualTo(EntryCanvas.minWidth));
      expect(block.h, greaterThanOrEqualTo(EntryCanvas.minHeight));
      expect(block.h / block.w, closeTo(2 / 3, 0.001));
      final afterCenter = Offset(block.x + block.w / 2, block.y + block.h / 2);
      final afterOpposite = afterCenter - Offset(block.w / 2, block.h / 2);
      expect(afterOpposite.dx, closeTo(beforeOpposite.dx, 0.001));
      expect(afterOpposite.dy, closeTo(beforeOpposite.dy, 0.001));
    }
  });

  testWidgets('vertical visual resize preserves width-to-height ratio', (
    tester,
  ) async {
    final block = ContentBlock(
      id: 'vertical-visual-resize',
      type: BlockType.image,
      x: 4,
      y: 4,
      w: 30,
      h: 20,
      assetId: 'asset-1',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: EntryCanvas(
            workspaceSize: const Size(400, 300),
            blocks: [block],
            editing: true,
            selectedId: block.id,
            textEditingId: null,
            onSelect: (_) {},
            onEditText: (_) {},
            onChanged: (_) {},
            imageBytes: (_) => null,
            onOpenImage: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    final handle = find.byKey(ValueKey('resize-${block.id}-bottom'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    await gesture.up();

    expect(block.h, closeTo(23, 0.01));
    expect(block.w, closeTo(34.5, 0.01));
    expect(block.y, closeTo(4, 0.01));
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
