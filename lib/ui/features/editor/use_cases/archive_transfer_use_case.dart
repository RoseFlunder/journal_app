import '../../../../services/journal_archive.dart';
import '../../../../services/journal_transfer_service.dart';
import '../../../../services/repositories.dart';

class ArchiveTransferUseCase {
  const ArchiveTransferUseCase({
    required this.archives,
    required this.transfer,
  });
  final ArchiveRepository archives;
  final JournalTransferGateway transfer;

  JournalArchive prepare(String documentId) {
    final archive = archives.archiveForDocument(documentId);
    if (archive == null) throw StateError('The page no longer exists.');
    archive.validate();
    return archive;
  }

  Future<JournalShareResult> share(JournalArchive archive) =>
      transfer.shareArchive(archive);
  Future<bool> save(JournalArchive archive) => transfer.saveArchive(archive);
}
