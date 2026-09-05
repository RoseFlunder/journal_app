import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/models/document.dart';
import 'package:journal_app/services/journal_archive.dart';
import 'package:journal_app/services/journal_transfer_service.dart';
import 'package:journal_app/services/repositories.dart';
import 'package:journal_app/ui/features/journal/view_models/shared_page_view_model.dart';

import 'support/fake_journal_transfer.dart';

void main() {
  late FakeJournalTransfer transfer;
  late _Archives archives;
  late SharedPageViewModel model;
  setUp(() {
    transfer = FakeJournalTransfer()
      ..picked = JournalArchive(
        document: EntryDocument(
          id: 'source',
          title: 'Spring',
          createdAt: DateTime.utc(2020),
          modifiedAt: DateTime.utc(2020),
        ),
      );
    archives = _Archives();
    model = SharedPageViewModel(archives: archives, transfer: transfer);
  });
  tearDown(() async {
    model.dispose();
    await transfer.events.close();
  });

  test('picker cancellation writes nothing', () async {
    transfer.picked = null;
    await model.pickPage();
    expect(archives.added, isEmpty);
    expect(model.busy, isFalse);
  });
  test('waits for confirmation and cancellation writes nothing', () async {
    final pending = _until(model, () => model.pendingPage != null);
    final operation = model.pickPage();
    await pending;
    expect(model.pendingPage!.createdAt, DateTime.utc(2020));
    expect(archives.added, isEmpty);
    model.confirm(false);
    await operation;
    expect(archives.added, isEmpty);
  });
  test('intentional repeat additions make independent copies', () async {
    for (var i = 0; i < 2; i++) {
      final pending = _until(model, () => model.pendingPage != null);
      final operation = model.pickPage();
      await pending;
      model.confirm(true);
      await operation;
      expect(model.takeAddedPageId(), 'copy-$i');
    }
    expect(archives.added.length, 2);
  });
  test(
    'queues arrivals, deduplicates a delivery and acknowledges cancellation',
    () async {
      model.start();
      final pending = _until(model, () => model.pendingPage != null);
      transfer.events.add(const IncomingJournalFile(id: 'first'));
      transfer.events.add(const IncomingJournalFile(id: 'first'));
      transfer.events.add(const IncomingJournalFile(id: 'second'));
      await pending;
      model.confirm(true);
      final second = _until(
        model,
        () => transfer.acknowledged.length == 1 && model.pendingPage != null,
      );
      await second;
      final idle = _until(model, () => !model.busy);
      model.confirm(false);
      await idle;
      expect(archives.added.length, 1);
      expect(transfer.acknowledged, ['first', 'second']);
    },
  );
  test('invalid file never requests confirmation', () async {
    transfer.readError = const FormatException('damaged');
    await model.pickPage();
    expect(model.pendingPage, isNull);
    expect(archives.added, isEmpty);
    expect(model.takeError(), contains('damaged'));
  });
  test('failed addition reports an error and releases the queue', () async {
    archives.fail = true;
    final pending = _until(model, () => model.pendingPage != null);
    final operation = model.pickPage();
    await pending;
    model.confirm(true);
    await operation;
    expect(model.takeAddedPageId(), isNull);
    expect(model.takeError(), contains('Could not add'));
    expect(model.busy, isFalse);
  });
}

Future<void> _until(SharedPageViewModel model, bool Function() condition) {
  if (condition()) return Future.value();
  final done = Completer<void>();
  void changed() {
    if (condition()) {
      model.removeListener(changed);
      done.complete();
    }
  }

  model.addListener(changed);
  return done.future.timeout(const Duration(seconds: 5));
}

class _Archives implements ArchiveRepository {
  final added = <EntryDocument>[];
  bool fail = false;
  @override
  JournalArchive? archiveForDocument(String id) => null;
  @override
  Future<EntryDocument> importArchive(JournalArchive archive) async {
    if (fail) throw StateError('disk full');
    final copy = EntryDocument(
      id: 'copy-${added.length}',
      title: archive.document.title,
      createdAt: archive.document.createdAt,
      modifiedAt: DateTime.now(),
    );
    added.add(copy);
    return copy;
  }
}
