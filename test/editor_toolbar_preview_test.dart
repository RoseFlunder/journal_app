import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/ui/features/editor/views/editor_toolbar_view.dart';

void main() {
  testWidgets('page preview action is contextual and shows selected state', (
    tester,
  ) async {
    var uses = 0;

    Widget toolbar({VoidCallback? onUseAsPreview, bool selected = false}) =>
        MaterialApp(
          home: Scaffold(
            body: EditorToolbarView(
              editing: true,
              hasSelection: onUseAsPreview != null,
              textEditing: false,
              onToggleEditing: () {},
              onAddText: () {},
              onAddImage: () {},
              onAddSticker: () {},
              onMore: () {},
              onEditText: () {},
              textFormattingAvailable: false,
              textSelection: false,
              onDecreaseFontSize: null,
              onIncreaseFontSize: null,
              fontFamily: null,
              onFontFamilyChanged: (_) {},
              textColorValue: null,
              onTextColorChanged: (_) {},
              onToggleBold: () {},
              onToggleItalic: () {},
              bold: false,
              italic: false,
              onDelete: () {},
              onBringToFront: () {},
              onUseAsPreview: onUseAsPreview,
              previewSelected: selected,
            ),
          ),
        );

    await tester.pumpWidget(toolbar());
    expect(find.byTooltip('Use as page preview'), findsNothing);

    await tester.pumpWidget(toolbar(onUseAsPreview: () => uses++));
    await tester.tap(find.byTooltip('Use as page preview'));
    expect(uses, 1);

    await tester.pumpWidget(
      toolbar(onUseAsPreview: () => uses++, selected: true),
    );
    expect(find.byTooltip('Selected as page preview'), findsOneWidget);
  });
}
