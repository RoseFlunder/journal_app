import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/models/document.dart';
import 'package:journal_app/ui/features/editor/view_models/image_filter_preset.dart';
import 'package:journal_app/ui/features/editor/views/editor_block.dart';
import 'package:journal_app/ui/features/editor/views/editor_image_editor_view.dart';

void main() {
  test('image filter presets expose the defined non-destructive values', () {
    expect(ImageFilterPreset.values, hasLength(6));
    expect(ImageFilterPreset.original.saturation, 1);
    expect(ImageFilterPreset.soft.brightness, 0.08);
    expect(ImageFilterPreset.warm.warmth, 0.35);
    expect(ImageFilterPreset.cool.warmth, -0.35);
    expect(ImageFilterPreset.vintage.saturation, 0.72);
    expect(ImageFilterPreset.mono.saturation, 0);
  });

  testWidgets('image filters preview and manual adjustments clear the preset', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    CanvasNode? preview;
    await _pumpEditor(
      tester,
      node: _imageNode(),
      onPreview: (node) => preview = node,
    );

    final warm = find.byKey(const ValueKey('image-filter-warm'));
    expect(warm, findsOneWidget);
    await tester.tap(warm);
    await tester.pump();
    expect(preview?.warmth, closeTo(0.35, 0.001));
    expect(tester.widget<ChoiceChip>(warm).selected, isTrue);

    final brightness = find.byKey(const ValueKey('image-brightness'));
    await tester.scrollUntilVisible(
      brightness,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    tester.widget<Slider>(brightness).onChanged!(0.2);
    await tester.pump();
    expect(preview, isNotNull);
    await tester.scrollUntilVisible(
      warm,
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.widget<ChoiceChip>(warm).selected, isFalse);
  });

  testWidgets('original resets filter values without changing the border', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    CanvasNode? preview;
    await _pumpEditor(
      tester,
      node: _imageNode(
        payload: const {
          'brightness': 0.2,
          'contrast': 0.1,
          'saturation': 0.6,
          'warmth': 0.4,
          'frameWidth': 3.0,
        },
      ),
      onPreview: (node) => preview = node,
    );

    await tester.tap(find.byKey(const ValueKey('image-filter-original')));
    await tester.pump();
    expect(preview?.brightness, 0);
    expect(preview?.contrast, 0);
    expect(preview?.saturation, 1);
    expect(preview?.warmth, 0);
    expect(preview?.frameWidth, 3);
  });

  testWidgets('border presets, width slider, and color callback preview', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    CanvasNode? preview;
    var colorCalls = 0;
    await _pumpEditor(
      tester,
      node: _imageNode(),
      onPreview: (node) => preview = node,
      onPickFrameColor: (context, current) async {
        colorCalls++;
        expect(current, isNull);
        return 0xFF873F4D;
      },
    );

    final thin = find.byKey(const ValueKey('image-border-thin'));
    await tester.scrollUntilVisible(
      thin,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    tester.widget<ChoiceChip>(thin).onSelected!(true);
    await tester.pump();
    expect(preview?.frameWidth, 1.5);

    final frameColor = find.byKey(const ValueKey('image-frame-color'));
    tester.widget<ListTile>(frameColor).onTap!();
    await tester.pump();
    expect(colorCalls, 1);
    expect(preview?.frameColorValue, 0xFF873F4D);

    final width = find.byKey(const ValueKey('image-frame-width'));
    await tester.scrollUntilVisible(
      width,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    tester.widget<Slider>(width).onChanged!(5);
    await tester.pump();
    expect(preview?.frameWidth, greaterThan(1.5));

    final none = find.byKey(const ValueKey('image-border-none'));
    await tester.scrollUntilVisible(
      none,
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    tester.widget<ChoiceChip>(none).onSelected!(true);
    await tester.pump();
    expect(preview?.frameWidth, 0);
    expect(preview?.frameColorValue, isNull);
  });

  testWidgets(
    'stickers keep the existing editor without image appearance tools',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpEditor(tester, node: _imageNode(type: BlockType.sticker));

      expect(find.text('Filters'), findsNothing);
      expect(find.text('Border'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Mask'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Mask'), findsOneWidget);
    },
  );

  testWidgets('renderer applies the filter matrix and solid frame', (
    tester,
  ) async {
    final node = _imageNode(
      payload: const {
        'saturation': 0.0,
        'frameWidth': 3.0,
        'frameColorValue': 0xFF873F4D,
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 200,
          height: 200,
          child: BlockWidget(
            block: node,
            selected: false,
            editing: false,
            textEditing: false,
            imageBytes: Uint8List.fromList([1]),
            onTap: () {},
            onEditText: () {},
            onMoveStart: (_) {},
            onMoveUpdate: (_) {},
            onMoveEnd: () {},
            onRotate: (_) {},
            onTextChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ColorFiltered), findsOneWidget);
    final frame = find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).border != null,
    );
    expect(frame, findsOneWidget);
    final decoration =
        tester.widget<DecoratedBox>(frame).decoration as BoxDecoration;
    expect(decoration.border!.top.width, 3);
    expect(decoration.border!.top.color, const Color(0xFF873F4D));
  });

  testWidgets('apply and cancel return distinct modal results', (tester) async {
    late BuildContext hostContext;
    Future<bool?>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            hostContext = context;
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
      ),
    );

    result = showModalBottomSheet<bool>(
      context: hostContext,
      isScrollControlled: true,
      builder: (context) => EditorImageEditorView(
        node: _imageNode(),
        onPreview: (_) {},
        onPickFrameColor: (_, _) async => null,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('image-editor-apply')));
    await tester.pumpAndSettle();
    expect(await result, isTrue);

    result = showModalBottomSheet<bool>(
      context: hostContext,
      isScrollControlled: true,
      builder: (context) => EditorImageEditorView(
        node: _imageNode(),
        onPreview: (_) {},
        onPickFrameColor: (_, _) async => null,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('image-editor-cancel')));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  required CanvasNode node,
  ValueChanged<CanvasNode>? onPreview,
  Future<int?> Function(BuildContext, int?)? onPickFrameColor,
}) async {
  late BuildContext hostContext;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          hostContext = context;
          return const Scaffold(body: SizedBox.shrink());
        },
      ),
    ),
  );
  await tester.pump();
  unawaited(
    showModalBottomSheet<void>(
      context: hostContext,
      backgroundColor: Colors.white,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => EditorImageEditorView(
        node: node,
        onPreview: onPreview ?? (_) {},
        onPickFrameColor: onPickFrameColor ?? (_, _) async => null,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

CanvasNode _imageNode({
  BlockType type = BlockType.image,
  Map<String, dynamic> payload = const {'assetId': 'asset-1'},
}) => CanvasNode(
  id: 'image-1',
  type: type,
  transform: const Transform2D(x: 0, y: 0, width: 100, height: 100),
  payload: payload,
);
