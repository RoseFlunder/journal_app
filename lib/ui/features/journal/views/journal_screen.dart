import '../../../../screens/journal_screen.dart' as legacy;

/// Feature-owned journal shell boundary during the screen extraction.
class JournalScreen extends legacy.JournalScreen {
  const JournalScreen({
    super.key,
    required super.repositories,
    required super.musicCatalog,
    required super.audioPlaybackFactory,
    required super.editorViewModelFactory,
  });
}
