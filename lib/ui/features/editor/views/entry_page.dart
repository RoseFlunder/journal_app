import '../../../../services/image_source.dart';
import '../../../../services/journal_transfer_service.dart';
import '../../../../screens/entry_page.dart' as legacy;

/// Feature-owned entry-page boundary.
///
/// The rendering implementation is still delegated to the legacy screen
/// during the incremental extraction, but callers no longer import or export
/// the legacy screen directly.
class EntryPage extends legacy.EntryPage {
  const EntryPage({
    super.key,
    required super.document,
    required super.editorViewModelFactory,
    super.onDocumentPreviewChanged,
    required super.onDocumentChanged,
    required super.onEditingChanged,
    required super.active,
    required super.musicCatalog,
    required super.audioPlaybackFactory,
    required super.musicController,
    super.controlsVisible,
    super.imageSource,
    super.imageProcessor = const ImageProcessor(),
    super.archiveService = const JournalTransferService(),
  });
}
