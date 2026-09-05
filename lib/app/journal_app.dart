import 'package:flutter/material.dart';

import '../ui/features/journal/view_models/journal_view_model.dart';
import '../ui/features/journal/view_models/shared_page_view_model.dart';
import '../ui/features/journal/views/journal_screen.dart';
import '../ui/features/music/view_models/page_music_controller.dart';
import '../ui/features/journal/view_models/cloud_sync_view_model.dart';
import '../widgets/paper_page.dart';
import 'app_dependencies.dart';

/// Material shell and composition-owned feature wiring for the journal app.
class JournalApp extends StatelessWidget {
  const JournalApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

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
      home: _ConfiguredJournalScreen(dependencies: dependencies),
    );
  }
}

/// Composition-owned feature model construction. The journal shell receives
/// configured models and services rather than constructing repository clients
/// inside its view tree.
class _ConfiguredJournalScreen extends StatefulWidget {
  const _ConfiguredJournalScreen({required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<_ConfiguredJournalScreen> createState() =>
      _ConfiguredJournalScreenState();
}

class _ConfiguredJournalScreenState extends State<_ConfiguredJournalScreen> {
  late final JournalViewModel _journal = JournalViewModel(
    repository: widget.dependencies.repositories.documentRepository,
    assetRepository: widget.dependencies.repositories.assetRepository,
  );
  late final SharedPageViewModel _sharedPages = SharedPageViewModel(
    archives: widget.dependencies.repositories.archiveRepository,
    transfer: widget.dependencies.archiveTransfer,
  );
  late final PageMusicController _music = PageMusicController(
    catalog: widget.dependencies.musicCatalog,
    playback: widget.dependencies.audioPlaybackFactory(),
    persistResolvedTrack: _journal.persistResolvedTrack,
  );
  late final CloudSyncViewModel _cloudSync = CloudSyncViewModel(
    coordinator: widget.dependencies.cloudSync,
  );

  @override
  Widget build(BuildContext context) => JournalScreen(
    journal: _journal,
    sharedPages: _sharedPages,
    music: _music,
    cloudSync: _cloudSync,
    editorViewModelFactory: widget.dependencies.editorViewModelFactory,
    imageSource: widget.dependencies.imageSource,
  );

  @override
  void dispose() {
    _cloudSync.dispose();
    _sharedPages.dispose();
    super.dispose();
  }
}
