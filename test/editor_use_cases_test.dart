import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:journal_app/models/document.dart';
import 'package:journal_app/models/entry.dart';
import 'package:journal_app/models/template.dart';
import 'package:journal_app/services/image_source.dart';
import 'package:journal_app/services/repositories.dart';
import 'package:journal_app/ui/features/editor/use_cases/checkpoint_recovery_use_case.dart';
import 'package:journal_app/ui/features/editor/use_cases/image_insertion_use_case.dart';
import 'package:journal_app/ui/features/editor/use_cases/template_workflow.dart';

void main() {
  test('image insertion processes bytes before storing an asset', () async {
    final assets = _FakeAssets();
    final useCase = ImageInsertionUseCase(
      assets: assets,
      processor: const ImageProcessor(),
    );
    final bytes = Uint8List.fromList(
      image.encodePng(image.Image(width: 2, height: 1)),
    );

    final result = await useCase.processAndStore(
      ownerId: 'entry',
      picked: PickedImage(bytes: bytes, mime: 'image/png'),
    );

    expect(result.assetId, 'asset-1');
    expect(result.image.width, 2);
    expect(result.image.height, 1);
    expect(assets.ownerId, 'entry');
    expect(assets.bytes, isNotEmpty);
  });

  test('template workflow persists immutable node selections', () async {
    final repository = _FakeTemplates();
    final workflow = TemplateWorkflow(templates: repository);
    final now = DateTime.utc(2026);
    final source = EntryDocument(
      id: 'entry',
      title: 'Source',
      createdAt: now,
      modifiedAt: now,
      board: const BoardSettings(gridVisible: true),
    );
    final node = CanvasNode(
      id: 'node',
      type: BlockType.text,
      transform: const Transform2D(width: 20, height: 10),
      payload: const {'text': 'Hello'},
    );

    await workflow.saveSelection(
      name: 'Greeting',
      source: source,
      nodes: [node],
      createdAt: now,
    );

    expect(repository.saved, hasLength(1));
    expect(repository.saved.single.document.nodes.single.id, 'node');
    expect(repository.saved.single.document.board.gridVisible, isTrue);
  });

  test('checkpoint workflow restores the current immutable document', () async {
    final now = DateTime.utc(2026);
    final document = EntryDocument(
      id: 'entry',
      title: 'Restored',
      createdAt: now,
      modifiedAt: now,
    );
    final checkpoints = _FakeCheckpoints();
    final useCase = CheckpointRecoveryUseCase(
      checkpoints: checkpoints,
      documents: _FakeDocuments(document),
    );

    final restored = await useCase.restore(
      checkpointId: 'checkpoint',
      documentId: document.id,
    );

    expect(checkpoints.restoredId, 'checkpoint');
    expect(restored?.title, 'Restored');
  });
}

class _FakeAssets implements AssetRepository {
  String? ownerId;
  Uint8List? bytes;

  @override
  Future<String> putAsset(
    String ownerId,
    AssetKind kind,
    String mime,
    List<int> bytes,
  ) async {
    this.ownerId = ownerId;
    this.bytes = Uint8List.fromList(bytes);
    return 'asset-1';
  }

  @override
  Uint8List? readAsset(String id) => bytes;

  @override
  String? assetMime(String id) => 'image/jpeg';

  @override
  Future<void> collectUnreferencedAssets() async {}
}

class _FakeTemplates implements TemplateRepository {
  final List<JournalTemplate> saved = <JournalTemplate>[];

  @override
  List<JournalTemplate> get templates => List.unmodifiable(saved);

  @override
  Future<void> saveTemplate(JournalTemplate template) async => saved.add(template);

  @override
  Future<void> deleteTemplate(String id) async {}
}

class _FakeCheckpoints implements CheckpointRepository {
  String? restoredId;

  @override
  List<EntryCheckpoint> checkpointsFor(String documentId) =>
      const <EntryCheckpoint>[];

  @override
  void scheduleCheckpoint(String documentId) {}

  @override
  Future<void> createCheckpoint(String documentId) async {}

  @override
  Future<void> restoreCheckpoint(String checkpointId) async {
    restoredId = checkpointId;
  }
}

class _FakeDocuments implements DocumentRepository {
  _FakeDocuments(EntryDocument document) : _documents = [document];

  final List<EntryDocument> _documents;

  @override
  List<EntryDocument> get documents => List.unmodifiable(_documents);

  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<void> init() async {}

  @override
  Future<EntryDocument> createDocument({String title = ''}) async =>
      _documents.first;

  @override
  Future<void> saveDocument(EntryDocument document) async {}

  @override
  void previewDocument(EntryDocument document) {}

  @override
  Future<void> deleteDocument(String id) async {}
}
