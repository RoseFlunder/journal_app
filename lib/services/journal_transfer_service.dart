import 'package:file_picker/file_picker.dart';

import 'journal_archive.dart';

/// Platform-facing archive transfer service.
///
/// File selection and byte transport are kept out of the editor view. Archive
/// validation and document persistence remain separate responsibilities.
class JournalTransferService {
  const JournalTransferService();

  Future<bool> exportArchive(
    JournalArchive archive, {
    required String fileName,
  }) async {
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: archive.encode(),
      mimeType: 'application/x-cozyjournal',
      dialogTitle: 'Export journal backup',
      type: FileType.custom,
      allowedExtensions: ['cozyjournal'],
    );
    return uri != null;
  }

  Future<JournalArchive?> importArchive() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['cozyjournal'],
    );
    if (picked.isEmpty) return null;
    final bytes = await picked.single.readAsBytes();
    return JournalArchive.decode(bytes);
  }
}
