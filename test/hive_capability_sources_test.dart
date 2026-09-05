import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:journal_app/models/document.dart';
import 'package:journal_app/models/view_state.dart';
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
    final beforeView = Map<String, dynamic>.from(
      source.readEntry(created.id) as Map,
    );
    final beforeRevision = beforeView['revision'];
    await repositories.documentRepository.saveDocument(
      repositories.documentRepository.documents.single.copyWith(
        view: const ViewState(zoom: 2, panX: 3),
        board: const BoardSettings(gridVisible: true),
      ),
    );
    final afterView = Map<String, dynamic>.from(
      source.readEntry(created.id) as Map,
    );
    expect(afterView['revision'], beforeRevision);
    expect(
      repositories.viewPreferencesRepository
          ?.preferencesFor(created.id)
          .view
          ?.zoom,
      2,
    );
    final assetId = await repositories.assetRepository.putAsset(
      AssetKind.image,
      'image/png',
      [1, 2, 3],
    );
    final firstAssetRead = repositories.assetRepository.readAsset(assetId.id);
    final secondAssetRead = repositories.assetRepository.readAsset(assetId.id);
    expect(firstAssetRead?.bytes, [1, 2, 3]);
    expect(identical(firstAssetRead, secondAssetRead), isTrue);

    await repositories.documentRepository.deleteDocument(created.id);
    expect(repositories.documentRepository.documents, isEmpty);
    expect(repositories.assetRepository.readAsset(assetId.id), isNull);
  });
}
