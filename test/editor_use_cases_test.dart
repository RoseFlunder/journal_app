import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:journal_app/models/document.dart';
import 'package:journal_app/services/image_source.dart';
import 'package:journal_app/services/image_processing.dart';
import 'package:journal_app/services/repositories.dart';
import 'package:journal_app/ui/features/editor/use_cases/checkpoint_recovery_use_case.dart';
import 'package:journal_app/ui/features/editor/use_cases/image_insertion_use_case.dart';

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
      picked: PickedImage(bytes: bytes, mime: 'image/png'),
    );

    expect(result.assetId, 'asset-1');
    expect(result.image.width, 2);
    expect(result.image.height, 1);
    expect(assets.bytes, isNotEmpty);
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
  Uint8List? bytes;

  @override
  Future<AssetDescriptor> putAsset(
    AssetKind kind,
    String mime,
    List<int> bytes,
  ) async {
    this.bytes = Uint8List.fromList(bytes);
    return AssetDescriptor(
      id: 'asset-1',
      kind: kind,
      mime: mime,
      byteLength: bytes.length,
      sha256: 'asset-1',
    );
  }

  @override
  AssetBlob? readAsset(String id) {
    final data = bytes;
    if (data == null) return null;
    return AssetBlob(
      descriptor: const AssetDescriptor(
        id: 'asset-1',
        kind: AssetKind.image,
        mime: 'image/jpeg',
        byteLength: 0,
        sha256: 'asset-1',
      ),
      bytes: data,
    );
  }

  @override
  Future<void> collectUnreferencedAssets({
    Iterable<String> retainedAssetIds = const <String>[],
  }) async {}
}

class _FakeCheckpoints implements CheckpointRepository {
  String? restoredId;

  @override
  List<CheckpointInfo> checkpointsFor(String documentId) =>
      const <CheckpointInfo>[];

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
