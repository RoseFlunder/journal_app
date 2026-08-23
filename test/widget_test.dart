import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:journal_app/main.dart';
import 'package:journal_app/services/journal_store.dart';
import 'package:journal_app/widgets/paper_page.dart';

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
}
