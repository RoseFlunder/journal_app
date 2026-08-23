import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/models/entry.dart';
import 'package:journal_app/widgets/page_viewport.dart';

void main() {
  test('viewport state normalizes invalid and out-of-range values', () {
    final normalized = ViewportMath.normalize(
      ViewState(zoom: double.nan, panX: double.infinity, panY: -500),
    );

    expect(normalized.zoom, 1);
    expect(normalized.panX, 0);
    expect(normalized.panY, -500);
  });

  testWidgets(
    'reset view is available and double tap returns to the initial view',
    (tester) async {
      ViewState? savedView;
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox.expand(
            child: PageViewport(
              initialView: ViewState(zoom: 2, panX: 30, panY: 40),
              onViewChanged: (view) => savedView = view,
              child: ColoredBox(color: Colors.amber),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byTooltip('Reset view'), findsOneWidget);
      await tester.tapAt(const Offset(200, 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byTooltip('Reset view'), findsOneWidget);

      await tester.tap(find.byTooltip('Reset view'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byTooltip('Reset view'), findsOneWidget);
      expect(savedView?.zoom, 1);
      expect(savedView?.panX, 0);
      expect(savedView?.panY, 0);

      await tester.tapAt(const Offset(200, 300));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(const Offset(200, 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(savedView?.zoom, 1);
    },
  );

  testWidgets('disabled viewport stays fixed and has no toolbar', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox.expand(
          child: PageViewport(
            interactive: false,
            child: ColoredBox(color: Colors.amber),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byTooltip('Zoom in'), findsNothing);
    expect(find.byTooltip('Zoom out'), findsNothing);
    expect(find.byTooltip('Fit page'), findsNothing);
  });
}
