import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'screens/journal_screen.dart';
import 'services/journal_store.dart';
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
  JournalStore? _store;
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
      final store = JournalStore();
      await store.init();
      final elapsed = DateTime.now().difference(_startedAt!);
      const minimum = Duration(seconds: 2);
      if (elapsed < minimum) await Future<void>.delayed(minimum - elapsed);
      if (!mounted) return;
      setState(() => _store = store);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: store == null
          ? CozyBloomSplash(error: _error, onRetry: _boot)
          : _JournalLifecycle(key: ValueKey(store), store: store),
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
                Image.asset(
                  'assets/branding/cozy_bloom_wordmark.png',
                  width: double.infinity,
                  fit: BoxFit.contain,
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
  const _JournalLifecycle({super.key, required this.store});

  final JournalStore store;

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
      await widget.store.flush();
    } catch (error) {
      debugPrint('Could not flush journal storage: $error');
    }
  }

  @override
  Widget build(BuildContext context) => JournalApp(store: widget.store);
}

class JournalApp extends StatelessWidget {
  const JournalApp({super.key, required this.store});

  final JournalStore store;

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
      home: JournalScreen(store: store),
    );
  }
}
