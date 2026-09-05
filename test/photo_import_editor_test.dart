import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:journal_app/services/photo_frame.dart';
import 'package:journal_app/ui/features/editor/views/photo_import_editor.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

void main() {
  LiveTestWidgetsFlutterBinding.ensureInitialized();

  Uint8List photo() => Uint8List.fromList(
    img.encodePng(
      img.Image(width: 100, height: 60)..clear(img.ColorRgb8(160, 80, 40)),
    ),
  );

  test('frames preserve the photo and are included in the exported pixels', () {
    final bytes = photo();
    expect(applyPhotoFrame((bytes, PhotoFrame.none)), same(bytes));
    final framed = img.decodePng(applyPhotoFrame((bytes, PhotoFrame.white)))!;
    expect(framed.width, 106);
    expect(framed.height, 66);
    expect(framed.getPixel(0, 0).r, 255);
    expect(framed.getPixel(3, 3).r, 160);
  });

  testWidgets(
    'previews a frame and returns exactly that image on confirmation',
    (tester) async {
      Uint8List? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.push<Uint8List>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PhotoImportEditor(bytes: photo()),
                    ),
                  );
                },
                child: const Text('Import'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      await tester.tap(find.byKey(const ValueKey('photo-frame-white')));
      await tester.pumpAndSettle();
      final preview =
          tester
                  .widget<Image>(find.byKey(const ValueKey('photo-preview')))
                  .image
              as MemoryImage;
      expect(img.decodePng(preview.bytes)!.width, 106);
      await tester.tap(find.text('Add to page'));
      await tester.pumpAndSettle();
      expect(result, orderedEquals(preview.bytes));
    },
  );

  testWidgets('library filters preview and export before adding to the page', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: PhotoImportEditor(bytes: photo())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    expect(find.byType(FilterEditor), findsOneWidget);
    await tester.tap(find.text('Clarendon'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(FilterEditor), findsNothing);
    final preview =
        tester.widget<Image>(find.byKey(const ValueKey('photo-preview'))).image
            as MemoryImage;
    expect(preview.bytes, isNot(orderedEquals(photo())));
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    final reset =
        tester.widget<Image>(find.byKey(const ValueKey('photo-preview'))).image
            as MemoryImage;
    expect(reset.bytes, orderedEquals(photo()));
  });

  testWidgets('back cancels the import without returning image bytes', (
    tester,
  ) async {
    Uint8List? result;
    bool closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.push<Uint8List>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PhotoImportEditor(bytes: photo()),
                  ),
                );
                closed = true;
              },
              child: const Text('Import'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isNull);
  });
}
