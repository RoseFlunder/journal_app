import 'package:flutter/material.dart';

import '../services/audio_playback.dart';
import '../services/image_source.dart';
import '../services/journal_transfer_service.dart';
import '../services/repositories.dart';
import '../ui/features/editor/view_models/entry_editor_view_model.dart';
import '../ui/features/journal/view_models/journal_view_model.dart';
import '../ui/features/journal/views/journal_screen.dart';
import '../ui/features/music/view_models/page_music_controller.dart';
import '../widgets/paper_page.dart';
import 'app_dependencies.dart';

/// Material shell and composition-owned feature wiring for the journal app.
class JournalApp extends StatelessWidget {
  JournalApp({
    super.key,
    JournalRepositories? repositories,
    AppDependencies? dependencies,
    MusicCatalogRepository? musicCatalog,
    AudioPlaybackFactory? audioPlaybackFactory,
    ImageSourceService? imageSource,
    ImageProcessor? imageProcessor,
    JournalTransferService? archiveTransfer,
    EntryEditorViewModelFactory? editorViewModelFactory,
  }) : assert(
         repositories != null || dependencies != null,
         'Provide AppDependencies or JournalRepositories.',
       ),
       repositories = repositories ?? dependencies!.repositories,
       musicCatalog =
           musicCatalog ??
           dependencies?.musicCatalog ??
           const DisabledMusicCatalogRepository(),
       audioPlaybackFactory =
           audioPlaybackFactory ??
           dependencies?.audioPlaybackFactory ??
           _disabledAudioFactory,
       imageSource =
           imageSource ?? dependencies?.imageSource ?? PlatformImageSource(),
       imageProcessor =
           imageProcessor ?? dependencies?.imageProcessor ?? const ImageProcessor(),
       archiveTransfer =
           archiveTransfer ??
           dependencies?.archiveTransfer ??
           const JournalTransferService(),
       editorViewModelFactory = editorViewModelFactory ??
           dependencies?.editorViewModelFactory ??
           ((document) => EntryEditorViewModel(
             document: document,
             documentRepository: (repositories ?? dependencies!.repositories)
                 .documentRepository,
             checkpointRepository: (repositories ?? dependencies!.repositories)
                 .checkpointRepository,
             assetRepository: (repositories ?? dependencies!.repositories)
                 .assetRepository,
             templateRepository: (repositories ?? dependencies!.repositories)
                 .templateRepository,
             preferenceRepository: (repositories ?? dependencies!.repositories)
                 .preferenceRepository,
             persistenceRepository: (repositories ?? dependencies!.repositories)
                 .persistence,
             archiveRepository: (repositories ?? dependencies!.repositories)
                 .archiveRepository,
             musicCatalog:
                 musicCatalog ??
                 dependencies?.musicCatalog ??
                 const DisabledMusicCatalogRepository(),
             audioPlaybackFactory:
                 audioPlaybackFactory ??
                 dependencies?.audioPlaybackFactory ??
                 _disabledAudioFactory,
           ));

  final JournalRepositories repositories;
  final MusicCatalogRepository musicCatalog;
  final AudioPlaybackFactory audioPlaybackFactory;
  final ImageSourceService imageSource;
  final ImageProcessor imageProcessor;
  final JournalTransferService archiveTransfer;
  final EntryEditorViewModelFactory editorViewModelFactory;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cozy Bloom Journal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFE8E1D2),
        colorScheme: ColorScheme.light(
          primary: PaperPage.ink,
          onPrimary: const Color(0xFFFFFBF4),
          secondary: PaperPage.margin,
          onSecondary: Colors.white,
          surface: const Color(0xFFFFFBF4),
          onSurface: PaperPage.ink,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFFFBF4),
          foregroundColor: PaperPage.ink,
          elevation: 0,
        ),
        textTheme: ThemeData.light().textTheme.copyWith(
          bodyLarge: const TextStyle(
            fontFamily: 'Caveat',
            fontSize: 21,
            color: PaperPage.ink,
          ),
          bodyMedium: const TextStyle(
            fontFamily: 'Caveat',
            fontSize: 19,
            color: PaperPage.ink,
          ),
          bodySmall: const TextStyle(
            fontFamily: 'Lora',
            fontSize: 12,
            color: PaperPage.ink,
          ),
          titleMedium: const TextStyle(
            fontFamily: 'Lora',
            fontWeight: FontWeight.w700,
            color: PaperPage.ink,
          ),
          headlineSmall: const TextStyle(
            fontFamily: 'Lora',
            fontWeight: FontWeight.w700,
            color: PaperPage.ink,
          ),
        ),
      ),
      home: _ConfiguredJournalScreen(
        repositories: repositories,
        musicCatalog: musicCatalog,
        audioPlaybackFactory: audioPlaybackFactory,
        imageSource: imageSource,
        imageProcessor: imageProcessor,
        archiveTransfer: archiveTransfer,
        editorViewModelFactory: editorViewModelFactory,
      ),
    );
  }
}

/// Composition-owned feature model construction. The journal shell receives
/// configured models and services rather than constructing repository clients
/// inside its view tree.
class _ConfiguredJournalScreen extends StatefulWidget {
  const _ConfiguredJournalScreen({
    required this.repositories,
    required this.musicCatalog,
    required this.audioPlaybackFactory,
    required this.imageSource,
    required this.imageProcessor,
    required this.archiveTransfer,
    required this.editorViewModelFactory,
  });

  final JournalRepositories repositories;
  final MusicCatalogRepository musicCatalog;
  final AudioPlaybackFactory audioPlaybackFactory;
  final ImageSourceService imageSource;
  final ImageProcessor imageProcessor;
  final JournalTransferService archiveTransfer;
  final EntryEditorViewModelFactory editorViewModelFactory;

  @override
  State<_ConfiguredJournalScreen> createState() =>
      _ConfiguredJournalScreenState();
}

class _ConfiguredJournalScreenState extends State<_ConfiguredJournalScreen> {
  late final JournalViewModel _journal = JournalViewModel(
    repository: widget.repositories.documentRepository,
    assetRepository: widget.repositories.assetRepository,
  );
  late final PageMusicController _music = PageMusicController(
    catalog: widget.musicCatalog,
    playback: widget.audioPlaybackFactory(),
    persistResolvedTrack: _journal.persistResolvedTrack,
  );

  @override
  Widget build(BuildContext context) => JournalScreen(
    journal: _journal,
    music: _music,
    editorViewModelFactory: widget.editorViewModelFactory,
    imageSource: widget.imageSource,
    imageProcessor: widget.imageProcessor,
    archiveTransfer: widget.archiveTransfer,
  );
}

AudioPlaybackService _disabledAudioFactory() =>
    const DisabledAudioPlaybackService();
