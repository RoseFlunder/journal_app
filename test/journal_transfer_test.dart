import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/models/document.dart';
import 'package:journal_app/services/journal_archive.dart';
import 'package:journal_app/services/journal_transfer_service.dart';

void main() {
  JournalArchive archive(String title) => JournalArchive(
    document: EntryDocument(
      id: 'page',
      title: title,
      createdAt: DateTime.utc(2020, 3, 2),
      modifiedAt: DateTime.utc(2020, 3, 2),
    ),
  );
  test('filenames preserve date and safely handle paths and empty titles', () {
    expect(
      JournalTransferService.fileName(archive('../a\\b:*?. ')),
      '2020-03-02 .._a_b___.cozyjournal',
    );
    expect(
      JournalTransferService.fileName(archive('...')),
      '2020-03-02 Journal page.cozyjournal',
    );
    expect(
      JournalTransferService.fileName(archive('x' * 1000)).length,
      lessThan(120),
    );
  });
  test('bounded stream reader decodes a chunked archive', () async {
    final bytes = archive('Title').encode();
    final decoded = await JournalTransferService.readArchiveStream(
      Stream.fromIterable([bytes.sublist(0, 10), bytes.sublist(10)]),
    );
    expect(decoded.document.title, 'Title');
  });
  test(
    'bounded reader rejects oversized chunks before allocating a buffer',
    () async {
      await expectLater(
        JournalTransferService.readArchiveStream(
          Stream.value(_OversizedChunk()),
        ),
        throwsFormatException,
      );
    },
  );
}

class _OversizedChunk extends ListBase<int> {
  @override
  int get length => JournalTransferService.maxFileBytes + 1;
  @override
  set length(int value) => throw UnsupportedError('length');
  @override
  int operator [](int index) =>
      throw StateError('must not read oversized chunk');
  @override
  void operator []=(int index, int value) => throw UnsupportedError('write');
}
