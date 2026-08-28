import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('feature code imports only capability contracts from services', () {
    final forbidden = <String>[
      'journal_store.dart',
      'hive_journal_data_source.dart',
      'hive_repositories.dart',
      'storage_records.dart',
      'models/entry.dart',
    ];
    final files = Directory('lib/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in files) {
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(matches(RegExp(r'''import\s+['"](?:package:hive|package:hive_flutter)/'''))),
        reason: '${file.path} must not depend on Hive directly',
      );
      for (final name in forbidden) {
        expect(
          source,
          isNot(contains(name)),
          reason: '${file.path} must not depend on $name',
        );
      }
    }
  });

  test('feature views do not import repository or storage implementations', () {
    final files = Directory('lib/ui/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (file) =>
              file.path.contains('${Platform.pathSeparator}views${Platform.pathSeparator}') &&
              file.path.endsWith('.dart'),
        );

    for (final file in files) {
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(matches(RegExp(r'''import\s+['"].*services/(?:repositories|hive_)'''))),
        reason: '${file.path} must depend on configured feature state',
      );
    }
  });

  test('data services do not depend on feature views', () {
    final files = Directory('lib/services')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in files) {
      expect(
        file.readAsStringSync(),
        isNot(contains('ui/features/')),
        reason: '${file.path} must not depend on feature views',
      );
    }
  });
}
