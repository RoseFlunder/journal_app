import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/models/entry.dart';
import 'package:journal_app/widgets/page_viewport.dart';

void main() {
  test('content fit zoom respects padding and opening cap', () {
    final zoom = ViewportMath.contentFitZoom(
      viewport: const Size(800, 600),
      pageRect: const Rect.fromLTWH(4000, 4500, 1000, 1414),
      contentRect: const Rect.fromLTWH(4220, 4518, 752, 92),
      minZoom: 0.5,
      maxZoom: 2,
    );

    expect(zoom, 2);
  });

  test('rotated content bounds include the full axis-aligned footprint', () {
    final bounds = ViewportMath.rotatedRectBounds(
      const Rect.fromLTWH(10, 20, 30, 40),
      1.5707963267948966,
    );

    expect(bounds.width, closeTo(40, 0.001));
    expect(bounds.height, closeTo(30, 0.001));
    expect(bounds.center, const Offset(25, 40));
  });

  test('viewport state normalizes invalid and out-of-range values', () {
    final normalized = ViewportMath.normalize(
      ViewState(zoom: double.nan, panX: double.infinity, panY: -500),
    );

    expect(normalized.zoom, 1);
    expect(normalized.panX, 0);
    expect(normalized.panY, -500);
  });

  test('world camera keeps large finite pans without artificial bounds', () {
    final normalized = ViewportMath.normalize(
      ViewState(zoom: 1, panX: 25000, panY: -40000),
    );

    expect(normalized.panX, 25000);
    expect(normalized.panY, -40000);
  });

  test('camera controller round-trips persisted page-relative view state', () {
    final camera = CameraController();
    addTearDown(camera.dispose);

    camera.configure(
      viewport: const Size(800, 600),
      pageRect: const Rect.fromLTWH(0, 0, 1000, 1414),
      initialView: const ViewState(zoom: 1.5, panX: 12, panY: -8),
      fitContentOnFirstOpen: false,
    );

    expect(camera.zoom, closeTo(1.5, 0.001));
    expect(camera.viewState.zoom, closeTo(1.5, 0.001));
    expect(camera.viewState.panX, closeTo(12, 0.001));
    expect(camera.viewState.panY, closeTo(-8, 0.001));

    camera.fitPage();
    expect(camera.viewState.zoom, closeTo(1, 0.001));
    expect(camera.viewState.panX, closeTo(0, 0.001));
    expect(camera.viewState.panY, closeTo(0, 0.001));
  });

  testWidgets(
    'fit content is available and double tap returns to the content fit',
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

      expect(find.byTooltip('Fit content'), findsOneWidget);
      await tester.tapAt(const Offset(200, 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byTooltip('Fit content'), findsOneWidget);

      await tester.tap(find.byTooltip('Fit content'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byTooltip('Fit page'), findsOneWidget);
      expect(savedView?.zoom, closeTo(0.92, 0.02));
      expect(savedView?.panX, closeTo(0, 0.01));
      expect(savedView?.panY, closeTo(0, 0.01));

      await tester.tapAt(const Offset(200, 300));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(const Offset(200, 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(savedView?.zoom, closeTo(0.92, 0.02));
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

  testWidgets('interactive limits scale with the page fit scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 600,
          child: PageViewport(child: ColoredBox(color: Colors.amber)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(viewer.minScale, closeTo(0.5 * (600 / 1414), 0.001));
    expect(viewer.maxScale, closeTo(3 * (600 / 1414), 0.001));
  });

  testWidgets('finite A4 page opens with the complete page fitted', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: PageViewport(
            canvasSize: PageViewport.pageSize,
            pageRect: const Rect.fromLTWH(0, 0, 1000, 1414),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final transform = viewer.transformationController!.value;
    final pageScale = 600 / 1414;
    final expectedScale = pageScale * ((552 / 1414) / pageScale);
    final translation = transform.getTranslation();

    expect(transform.getMaxScaleOnAxis(), closeTo(expectedScale, 0.001));
    expect(translation.x, closeTo((800 - 1000 * expectedScale) / 2, 0.001));
    expect(translation.y, closeTo((600 - 1414 * expectedScale) / 2, 0.001));
  });

  testWidgets('Windows wheel pans without zooming unless Ctrl is pressed', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: PageViewport(
            initialView: const ViewState(zoom: 1),
            child: const ColoredBox(color: Colors.amber),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    InteractiveViewer viewer() => tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );

    final initial = viewer().transformationController!.value;
    final initialScale = initial.getMaxScaleOnAxis();
    final initialTranslation = initial.getTranslation();

    await tester.sendEventToBinding(
      const PointerScrollEvent(
        kind: PointerDeviceKind.mouse,
        position: Offset(400, 300),
        scrollDelta: Offset(0, 20),
      ),
    );
    await tester.pump();

    final afterWheel = viewer().transformationController!.value;
    expect(afterWheel.getMaxScaleOnAxis(), closeTo(initialScale, 0.001));
    expect(afterWheel.getTranslation().y, isNot(initialTranslation.y));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        kind: PointerDeviceKind.mouse,
        position: Offset(400, 300),
        scrollDelta: Offset(0, -20),
      ),
    );
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);

    final afterCtrlWheel = viewer().transformationController!.value;
    expect(afterCtrlWheel.getMaxScaleOnAxis(), greaterThan(initialScale));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows primary-button drag pans freely in both axes', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: PageViewport(
            initialView: const ViewState(zoom: 1),
            child: const ColoredBox(color: Colors.amber),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final before = viewer.transformationController!.value.getTranslation();
    final gesture = await tester.startGesture(
      const Offset(400, 300),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(80, 60));
    await gesture.up();
    await tester.pump();

    final after = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!
        .value
        .getTranslation();
    expect(after.y, isNot(closeTo(before.y, 0.001)));
    expect(after.x, isNot(closeTo(before.x, 0.001)));
    debugDefaultTargetPlatformOverride = null;
  });
}
