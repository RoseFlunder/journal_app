import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'screens/journal_screen.dart';
import 'services/journal_store.dart';
import 'widgets/paper_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  final store = JournalStore();
  await store.init();
  runApp(_JournalLifecycle(store: store));
}

class _JournalLifecycle extends StatefulWidget {
  const _JournalLifecycle({required this.store});

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
      title: 'Journal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFE4D7BF),
        colorScheme: ColorScheme.light(
          primary: PaperPage.ink,
          onPrimary: const Color(0xFFF4EDDC),
          secondary: PaperPage.margin,
          onSecondary: Colors.white,
          surface: PaperPage.paper,
          onSurface: PaperPage.ink,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: PaperPage.paper,
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
