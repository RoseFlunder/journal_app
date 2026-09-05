import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/models/document.dart';

import 'package:journal_app/ui/features/editor/views/editor_block.dart';

void main() {
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
