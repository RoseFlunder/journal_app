import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app/app_dependencies.dart';
import 'app/journal_app.dart';
import 'widgets/paper_page.dart';

export 'app/journal_app.dart' show JournalApp;

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
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.dependencies.cloudSync.onAppResumed());
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      widget.dependencies.cloudSync.onAppPaused();
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
