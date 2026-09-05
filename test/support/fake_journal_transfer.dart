import 'dart:async';

import 'package:journal_app/services/journal_archive.dart';
import 'package:journal_app/services/journal_transfer_service.dart';

class FakeJournalTransfer implements JournalTransferGateway {
  final events = StreamController<IncomingJournalFile>.broadcast(sync: true);
  JournalArchive? picked;
  Object? readError;
  final acknowledged = <String>[];
  final shared = <JournalArchive>[];
  final saved = <JournalArchive>[];
  JournalShareResult shareResult = JournalShareResult.dismissed;
  @override
  Stream<IncomingJournalFile> get incomingFiles => events.stream;
  @override
  Future<void> acknowledgeIncoming(String id) async {
    acknowledged.add(id);
  }

  @override
  Future<JournalArchive?> pickArchive() async {
    if (readError != null) throw readError!;
    return picked;
  }

  @override
  Future<JournalArchive> readIncoming(IncomingJournalFile file) async {
    if (readError != null) throw readError!;
    return picked!;
  }

  @override
  Future<JournalShareResult> shareArchive(JournalArchive archive) async {
    shared.add(archive);
    return shareResult;
  }

  @override
  Future<bool> saveArchive(JournalArchive archive) async {
    saved.add(archive);
    return true;
  }
}
