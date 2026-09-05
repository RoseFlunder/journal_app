import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:journal_app/app/app_dependencies.dart';
import 'package:journal_app/app/journal_app.dart';
import 'package:journal_app/models/document.dart';
import 'package:journal_app/services/journal_archive.dart';
import 'package:journal_app/services/journal_transfer_service.dart';
import 'package:journal_app/ui/features/editor/views/entry_page.dart';

import 'support/fake_journal_transfer.dart';
import 'support/hive_test_environment.dart';

void main() {
  LiveTestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late TestHiveEnvironment store;
  late FakeJournalTransfer transfer;
  late AppDependencies dependencies;
  setUpAll(() {
    temp = Directory.systemTemp.createTempSync('shared_page_widget');
    Hive.init(temp.path);
  });
  setUp(() async {
    store = await TestHiveEnvironment.fresh();
    transfer = FakeJournalTransfer()
      ..picked = JournalArchive(
        document: EntryDocument(
          id: 'original',
          title: 'A spring memory',
          createdAt: DateTime.utc(2020, 3, 2),
          modifiedAt: DateTime.utc(2020, 3, 2),
        ),
      );
    dependencies = AppDependencies(
      repositories: store.repositories,
      archiveTransfer: transfer,
    );
  });
  tearDown(() async {
    await dependencies.dispose();
    await transfer.events.close();
    await store.dispose();
  });
  tearDownAll(() async {
    await Hive.close();
    temp.deleteSync(recursive: true);
  });

  testWidgets('empty journal offers picker and confirmation before adding', (
    tester,
  ) async {
    await tester.pumpWidget(JournalApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add shared page'));
    await tester.pumpAndSettle();
    expect(
      find.text('Do you want to add this page to your journal?'),
      findsOneWidget,
    );
    expect(find.textContaining('March 2, 2020'), findsOneWidget);
    expect(store.entries, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.entries, isEmpty);
    await tester.tap(find.text('Add shared page'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add page'));
    await tester.pumpAndSettle();
    expect(store.entries.single.createdAt, DateTime.utc(2020, 3, 2));
    expect(
      tester
          .widgetList<EntryPage>(find.byType(EntryPage))
          .where((page) => page.active)
          .single
          .viewModel
          .document
          .title,
      'A spring memory',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'received page opens at its original date and duplicate event is ignored',
    (tester) async {
      await store.addEntry(title: 'Today');
      await tester.pumpWidget(JournalApp(dependencies: dependencies));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      transfer.events.add(const IncomingJournalFile(id: 'delivery'));
      transfer.events.add(const IncomingJournalFile(id: 'delivery'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add page'));
      await tester.pumpAndSettle();
      expect(store.entries.map((entry) => entry.title), [
        'A spring memory',
        'Today',
      ]);
      expect(transfer.acknowledged, ['delivery']);
      expect(
        tester
            .widgetList<EntryPage>(find.byType(EntryPage))
            .where((page) => page.active)
            .single
            .viewModel
            .document
            .title,
        'A spring memory',
      );
      expect(
        find.text('Do you want to add this page to your journal?'),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
