import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:image/image.dart' as img;
import 'package:journal_app/app/app_dependencies.dart';
import 'package:journal_app/main.dart';
import 'package:journal_app/services/image_source.dart';
import 'package:journal_app/ui/features/editor/views/photo_import_editor.dart';

import 'support/hive_test_environment.dart';

void main() {
  LiveTestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUpAll(() {
    temp = Directory.systemTemp.createTempSync('photo_import_widget_test');
    Hive.init(temp.path);
  });
  tearDownAll(() async {
    await Hive.close();
    temp.deleteSync(recursive: true);
  });

  testWidgets(
    'gallery import saves only after confirmation and has no appearance menu',
    (tester) async {
      final store = TestHiveEnvironment();
      await store.init();
      final entry = await store.addEntry(title: 'Photo page');
      final dependencies = AppDependencies(
        repositories: store.repositories,
        imageSource: _Photos(),
      );
      await tester.pumpWidget(JournalApp(dependencies: dependencies));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Photo page'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit page'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add image'));
      await tester.pumpAndSettle();
      expect(find.byType(PhotoImportEditor), findsOneWidget);
      expect(
        store.repositories.documentRepository.documents
            .singleWhere((document) => document.id == entry.id)
            .nodes,
        isEmpty,
      );
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(
        store.repositories.documentRepository.documents
            .singleWhere((document) => document.id == entry.id)
            .nodes,
        isEmpty,
      );
      await tester.tap(find.byTooltip('Add image'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('photo-frame-cream')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to page'));
      await tester.pumpAndSettle();
      await dependencies.flush();
      final document = store.repositories.documentRepository.documents
          .singleWhere((document) => document.id == entry.id);
      expect(document.nodes, hasLength(1));
      final node = document.nodes.single;
      final blob = store.repositories.assetRepository.readAsset(node.assetId!)!;
      final image = img.decodeImage(Uint8List.fromList(blob.bytes))!;
      expect(image.width, 106);
      expect(image.height, 66);
      expect(node.frameWidth, 0); // Frame is baked into the asset.
      await tester.tap(find.byTooltip('More editing tools'));
      await tester.pumpAndSettle();
      expect(find.text('Edit image'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}

class _Photos implements ImageSourceService {
  @override
  Set<ImagePickOrigin> get supportedOrigins => const {ImagePickOrigin.gallery};

  @override
  Future<PickedImage?> pickImage(ImagePickOrigin origin) async => PickedImage(
    bytes: Uint8List.fromList(
      img.encodePng(
        img.Image(width: 100, height: 60)..clear(img.ColorRgb8(160, 80, 40)),
      ),
    ),
    mime: 'image/png',
  );
}

