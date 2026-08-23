import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'screens/journal_screen.dart';
import 'services/journal_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  final store = JournalStore();
  await store.init();
  runApp(JournalApp(store: store));
}

class JournalApp extends StatelessWidget {
  const JournalApp({super.key, required this.store});

  final JournalStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Journal',
      debugShowCheckedModeBanner: false,
      // M1 is functionally plain; the paper look lands in M2. A warm seed
      // keeps the skeleton from feeling cold in the meantime.
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8B7355),
        ),
      ),
      home: JournalScreen(store: store),
    );
  }
}
