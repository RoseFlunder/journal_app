import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:journal_app/models/document.dart';
import 'package:journal_app/models/template.dart';
import 'package:journal_app/services/hive_journal_data_source.dart';
import 'package:journal_app/services/hive_repositories.dart';
import 'package:journal_app/services/repositories.dart';

void main() {
  late Directory temp;

  setUpAll(() {
    temp = Directory.systemTemp.createTempSync('hive_capability_sources');
    Hive.init(temp.path);
  });

  tearDownAll(() async {
    await Hive.close();
    temp.deleteSync(recursive: true);
  });

  test('direct capability sources round-trip immutable documents', () async {
    final source = HiveJournalDataSource();
    final repositories = HiveRepositorySet.fromDataSource(source).repositories;
    await repositories.documentRepository.init();

    final created = await repositories.documentRepository.createDocument(
      title: 'Direct source',
    );
    final node = CanvasNode(
      id: 'direct-node',
      type: BlockType.text,
      transform: const Transform2D(width: 24, height: 12),
      payload: const {'text': 'Immutable'},
    );
    final updated = created.copyWith(nodes: [node]);
    await repositories.documentRepository.saveDocument(updated);

    expect(
      repositories.documentRepository.documents.single.nodes.single.text,
      'Immutable',
    );
    final assetId = await repositories.assetRepository.putAsset(
      created.id,
      AssetKind.image,
      'image/png',
      [1, 2, 3],
    );
    expect(repositories.assetRepository.readAsset(assetId), [1, 2, 3]);

    final template = JournalTemplate(
      id: 'direct-template',
      name: 'Direct',
      document: updated,
      createdAt: DateTime.utc(2026),
    );
    await repositories.templateRepository.saveTemplate(template);
    expect(repositories.templateRepository.templates.single.name, 'Direct');

    await repositories.documentRepository.deleteDocument(created.id);
    expect(repositories.documentRepository.documents, isEmpty);
    expect(repositories.assetRepository.readAsset(assetId), isNull);
  });
}
