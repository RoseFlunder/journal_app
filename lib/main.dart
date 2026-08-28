import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app/app_dependencies.dart';
import 'services/image_source.dart';
import 'services/journal_transfer_service.dart';
import 'services/audio_playback.dart';
import 'ui/features/journal/views/journal_screen.dart';
import 'ui/features/journal/view_models/journal_view_model.dart';
import 'ui/features/editor/view_models/entry_editor_view_model.dart';
import 'ui/features/music/view_models/page_music_controller.dart';
import 'services/repositories.dart';
import 'widgets/paper_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CozyBloomBootstrap());
}

/// Boots storage behind the branded loading screen so desktop and web do not
/// show an empty/black window while Hive opens.
class CozyBloomBootstrap extends StatefulWidget {
  const CozyBloomBootstrap({super.key});

  @override
  State<CozyBloomBootstrap> createState() => _CozyBloomBootstrapState();
}

class _CozyBloomBootstrapState extends State<CozyBloomBootstrap> {
  AppDependencies? _dependencies;
  Object? _error;
  bool _hiveInitialized = false;
  DateTime? _startedAt;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    _startedAt = DateTime.now();
    setState(() => _error = null);
    try {
      if (!_hiveInitialized) {
        await Hive.initFlutter();
        _hiveInitialized = true;
      }
      final dependencies = AppDependencies.hive();
      await dependencies.init();
      final elapsed = DateTime.now().difference(_startedAt!);
      const minimum = Duration(milliseconds: 3500);
      if (elapsed < minimum) await Future<void>.delayed(minimum - elapsed);
      if (!mounted) return;
      setState(() => _dependencies = dependencies);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = _dependencies;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: dependencies == null
          ? CozyBloomSplash(error: _error, onRetry: _boot)
          : _JournalLifecycle(
              key: ValueKey(dependencies),
              dependencies: dependencies,
            ),
    );
  }
}

class CozyBloomSplash extends StatelessWidget {
  const CozyBloomSplash({super.key, this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Cozy Bloom Journal',
    theme: ThemeData(
      scaffoldBackgroundColor: const Color(0xFFFBF3E6),
      colorScheme: ColorScheme.light(
        primary: PaperPage.sage,
        onPrimary: PaperPage.ink,
        surface: const Color(0xFFFBF3E6),
        onSurface: PaperPage.ink,
      ),
    ),
    home: Scaffold(
      backgroundColor: const Color(0xFFFBF3E6),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: const Duration(seconds: 2),
                  curve: Curves.easeIn,
                  builder: (context, opacity, child) =>
                      Opacity(opacity: opacity, child: child),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Image.asset(
                      'assets/branding/cozy_bloom_wordmark.png',
                      width: double.infinity,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                if (error == null)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: PaperPage.sage,
                    ),
                  )
                else ...[
                  const Text(
                    'Could not open your journal.',
                    style: TextStyle(fontFamily: 'Lora', color: PaperPage.ink),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonal(
                    onPressed: onRetry,
                    child: const Text('Retry'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _JournalLifecycle extends StatefulWidget {
  const _JournalLifecycle({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<_JournalLifecycle> createState() => _JournalLifecycleState();
}

class _JournalLifecycleState extends State<_JournalLifecycle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(
      widget.dependencies.dispose().catchError((Object error, StackTrace stackTrace) {
        debugPrint('Could not close journal storage: $error');
      }),
    );
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_flushStore());
    }
  }

  Future<void> _flushStore() async {
    try {
      await widget.dependencies.flush();
    } catch (error) {
      debugPrint('Could not flush journal storage: $error');
    }
  }

  @override
  Widget build(BuildContext context) => JournalApp(
    dependencies: widget.dependencies,
  );
}

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
       imageProcessor = imageProcessor ?? dependencies?.imageProcessor ?? const ImageProcessor(),
       archiveTransfer = archiveTransfer ?? dependencies?.archiveTransfer ?? const JournalTransferService(),
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
