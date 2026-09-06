import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/models/canvas.dart';
import 'package:journal_app/ui/features/editor/view_models/editor_tool_state.dart';
import 'package:journal_app/ui/features/editor/views/editor_ink_settings_view.dart';

void main() {
  testWidgets('brush gallery lists and selects every polished stroke type', (
    tester,
  ) async {
    final previews = <InkSettings>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorInkSettingsView(
            initial: const InkSettings(width: 3.4, opacity: .7),
            onPreview: previews.add,
            onPickColor: (_, _) async => null,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ink-stroke-selector')));
    await tester.pumpAndSettle();

    expect(find.byType(InkStrokePreview), findsNWidgets(5));
    for (final type in InkStrokeType.values) {
      final option = find.byKey(ValueKey('ink-stroke-option-${type.name}'));
      await tester.scrollUntilVisible(
        option,
        240,
        scrollable: find.byType(Scrollable).last,
      );
      expect(option, findsOneWidget);
    }

    await tester.tap(
      find.byKey(const ValueKey('ink-stroke-option-highlighter')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Highlighter'), findsOneWidget);
    expect(previews, hasLength(1));
    expect(previews.single.strokeType, InkStrokeType.highlighter);
    expect(previews.single.width, 3.4);
    expect(previews.single.opacity, .7);
  });

  testWidgets('selecting a brush closes the gallery after a preview change', (
    tester,
  ) async {
    final previews = <InkSettings>[];
    const initial = InkSettings(strokeType: InkStrokeType.brush);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorInkSettingsView(
            initial: initial,
            onPreview: previews.add,
            onPickColor: (_, _) async => null,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ink-stroke-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ink-stroke-option-marker')));
    await tester.pumpAndSettle();
    expect(previews.single.strokeType, InkStrokeType.marker);
    expect(
      find.byKey(const ValueKey('ink-stroke-option-marker')),
      findsNothing,
    );
  });

  testWidgets('ink settings keeps Apply above the bottom inset', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(360, 640));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(padding: const EdgeInsets.only(bottom: 32)),
              child: Center(
                child: ElevatedButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => const EditorInkSettingsView(
                      initial: InkSettings(),
                      onPreview: _ignoreSettings,
                      onPickColor: _ignoreColor,
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final apply = tester.getRect(find.text('Apply'));
    expect(apply.bottom, lessThanOrEqualTo(608));
    expect(tester.takeException(), isNull);
  });
}

void _ignoreSettings(InkSettings _) {}

Future<InkSettings?> _ignoreColor(
  BuildContext context,
  InkSettings settings,
) async => null;
