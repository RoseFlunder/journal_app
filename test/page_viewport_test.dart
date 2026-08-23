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
    expect(normalized.panY, -141.4);
  });

  testWidgets('toolbar appears after double tap and fit resets the viewport',
      (tester) async {
    ViewState? savedView;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(
          child: PageViewport(
            onViewChanged: (view) => savedView = view,
            child: ColoredBox(color: Colors.amber),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byTooltip('Fit page'), findsNothing);
    await tester.tapAt(const Offset(200, 300));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(200, 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('Fit page'), findsOneWidget);
    expect(savedView?.zoom, greaterThan(1));

    await tester.tap(find.byTooltip('Fit page'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('Fit page'), findsNothing);
    expect(savedView?.zoom, 1);
  });

  testWidgets('disabled viewport stays fixed and has no toolbar', (tester) async {
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