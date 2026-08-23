import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:journal_app/main.dart';
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
    'create a page, jump to it, swipe back, find it in TOC, delete it',
    (tester) async {
      store = JournalStore();
      await store.init();
      await tester.pumpWidget(JournalApp(store: store));
      await tester.pumpAndSettle();

      // Starts on the (empty) table of contents.
      expect(find.text('Journal'), findsOneWidget);
      expect(find.text('This journal is empty.'), findsOneWidget);

      // Create the first page from the FAB.
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Animated to the new entry page (no AppBar, placeholder title).
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('Untitled page'), findsOneWidget);

      // Swipe right (previous page) back to the table of contents.
      await tester.drag(find.byType(PageView), const Offset(800, 0));
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

      // Swipe back to the TOC and delete the page.
      await tester.drag(find.byType(PageView), const Offset(800, 0));
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

  testWidgets('M4 adds, edits, resizes and deletes text blocks', (tester) async {
    store = JournalStore();
    await store.init();
    for (final existing in store.entries.toList()) {
      store.deleteEntry(existing.id);
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

  testWidgets('entry viewport view state survives leaving and reopening',
      (tester) async {
    store = JournalStore();
    await store.init();
    for (final existing in store.entries.toList()) {
      store.deleteEntry(existing.id);
    }
    await tester.pumpWidget(JournalApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    final entry = store.entries.single;

    await tester.tapAt(const Offset(200, 300));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(200, 300));
    await tester.pump(const Duration(milliseconds: 350));
    expect(store.entries.single.view?.zoom, 2);

    await tester.drag(find.byType(PageView), const Offset(800, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Untitled page'));
    await tester.pumpAndSettle();
    expect(find.byType(PageViewport), findsOneWidget);
    expect(store.entries.single.view?.zoom, 2);
    expect(store.entries.single.id, entry.id);
  });
}
