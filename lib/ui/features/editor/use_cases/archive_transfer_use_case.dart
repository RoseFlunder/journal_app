import '../../../../models/document.dart';
import '../../../../services/journal_transfer_service.dart';
import '../../../../services/repositories.dart';

/// Keeps archive coordination out of the page widget while leaving file
/// picking in the platform-facing transfer service.
class ArchiveTransferUseCase {
  const ArchiveTransferUseCase({
    required this.archives,
    required this.transfer,
  });

  final ArchiveRepository archives;
  final JournalTransferGateway transfer;

  Future<bool> exportDocument({
    required String documentId,
    required String fileName,
  }) async {
    final archive = archives.archiveForDocument(documentId);
    if (archive == null) return false;
    return transfer.exportArchive(archive, fileName: fileName);
  }

  Future<EntryDocument?> importDocument() async {
    final archive = await transfer.importArchive();
    if (archive == null) return null;
    return archives.importArchive(archive);
  }
}
