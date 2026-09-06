import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:journal_app/models/document.dart';
import 'package:journal_app/models/page_music.dart';
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

  test('previewed music changes remain durable after reopening', () async {
    final source = HiveJournalDataSource();
    final repositorySet = HiveRepositorySet.fromDataSource(source);
    final documents = repositorySet.repositories.documentRepository;
    await documents.init();
    await Future.wait([
      Hive.box<dynamic>('cozyBloom.documents.v2').clear(),
      Hive.box<dynamic>('cozyBloom.assets.v2').clear(),
      Hive.box<dynamic>('cozyBloom.meta.v2').clear(),
      Hive.box<dynamic>('cozyBloom.checkpoints.v2').clear(),
      Hive.box<dynamic>('cozyBloom.syncHeads.v2').clear(),
      Hive.box<dynamic>('cozyBloom.quarantine.v2').clear(),
    ]);
    await source.writeSchemaMarker();

    const firstTrack = PageMusicTrack(
      provider: 'jamendo',
      trackId: 'first',
      title: 'First track',
      artist: 'Artist',
      streamUrl: 'https://audio.example/first.mp3',
      trackPageUrl: 'https://jamendo.example/first',
      licenseUrl: 'https://creativecommons.org/licenses/by/4.0/',
    );
    const secondTrack = PageMusicTrack(
      provider: 'jamendo',
      trackId: 'second',
      title: 'Second track',
      artist: 'Artist',
      streamUrl: 'https://audio.example/second.mp3',
      trackPageUrl: 'https://jamendo.example/second',
      licenseUrl: 'https://creativecommons.org/licenses/by/4.0/',
    );

    final added = await documents.createDocument(title: 'Added');
    final addedMusic = added.copyWith(music: firstTrack);
    documents.previewDocument(addedMusic);
    await documents.saveDocument(addedMusic);

    final replaced = await documents.createDocument(title: 'Replaced');
    await documents.saveDocument(replaced.copyWith(music: firstTrack));
    final replacement = documents.documents
        .firstWhere((document) => document.id == replaced.id)
        .copyWith(music: secondTrack);
    documents.previewDocument(replacement);
    await documents.saveDocument(replacement);

    final removed = await documents.createDocument(title: 'Removed');
    await documents.saveDocument(removed.copyWith(music: firstTrack));
    final removal = documents.documents
        .firstWhere((document) => document.id == removed.id)
        .copyWith(music: null);
    documents.previewDocument(removal);
    await documents.saveDocument(removal);

    final previewOnly = await documents.createDocument(title: 'Durable title');
    documents.previewDocument(previewOnly.copyWith(title: 'Preview title'));

    final viewOnly = await documents.createDocument(title: 'View only');
    final revisionBeforeView = (source.readEntry(viewOnly.id) as Map)['revision'];
    final viewPreview = viewOnly.copyWith(
      view: const ViewState(zoom: 2, panX: 3),
      board: const BoardSettings(gridVisible: true),
    );
    documents.previewDocument(viewPreview);
    await documents.saveDocument(viewPreview);
    expect((source.readEntry(viewOnly.id) as Map)['revision'], revisionBeforeView);
    expect(source.entryKeys.length, 5);
    await source.flush();

    await repositorySet.dispose();
    await source.dispose();

    final reopenedSource = HiveJournalDataSource();
    final reopenedSet = HiveRepositorySet.fromDataSource(reopenedSource);
    final reopened = reopenedSet.repositories.documentRepository;
    await reopened.init();
    expect(reopened.documents, hasLength(5));

    EntryDocument page(String id) =>
        reopened.documents.firstWhere((document) => document.id == id);
    expect(page(added.id).music?.trackId, 'first');
    expect(page(replaced.id).music?.trackId, 'second');
    expect(page(removed.id).music, isNull);
    expect(page(previewOnly.id).title, 'Durable title');
    expect(page(viewOnly.id).view?.zoom, 2);
    expect(page(viewOnly.id).board.gridVisible, isTrue);

    await reopenedSet.dispose();
    await reopenedSource.dispose();
  });
}
