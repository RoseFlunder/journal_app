import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bundled welcome collection contains 50 complete alternatives', () {
    final source = File('assets/content/welcome_messages.json')
        .readAsStringSync();
    final messages = jsonDecode(source) as List<dynamic>;

    expect(messages, hasLength(50));
    for (final value in messages) {
      final message = value as Map<String, dynamic>;
      expect((message['message'] as String).trim(), isNotEmpty);
      expect((message['reflection'] as String).trim(), isNotEmpty);
    }
  });
}
