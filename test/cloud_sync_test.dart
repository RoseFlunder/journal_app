import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:journal_app/models/document.dart';
import 'package:journal_app/services/cloud_gateway.dart';
import 'package:journal_app/services/cloud_sync_coordinator.dart';
import 'package:journal_app/services/repositories.dart';
import 'package:journal_app/services/sync_local_store.dart';
import 'package:journal_app/services/sync_models.dart';
import 'package:journal_app/ui/features/journal/view_models/cloud_sync_view_model.dart';

void main() {
  test('version vectors are immutable and order causal edits', () {
    final source = <String, int>{'device-a': 1};
    final vector = SyncVersionVector(source);
    source['device-a'] = 9;

    expect(vector['device-a'], 1);
    expect(vector.increment('device-b').relationTo(vector), SyncRelation.after);
    expect(
      SyncVersionVector({'device-a': 2}).relationTo(
        SyncVersionVector({'device-a': 1, 'device-b': 1}),
      ),
      SyncRelation.concurrent,
    );
    expect(
      SyncVersionVector({'device-a': 1, 'device-b': 2}),
      SyncVersionVector({'device-b': 2, 'device-a': 1}),
    );
    final properties = <String, String>{'type': 'document-head'};
    final record = DriveSyncRecord(
      fileId: 'file',
      name: 'head',
      mimeType: 'application/json',
      properties: properties,
      modifiedAt: null,
    );
    properties['type'] = 'mutated';
    expect(record.properties['type'], 'document-head');
    expect(
      () => record.properties['type'] = 'mutated',
      throwsUnsupportedError,
    );
    expect(() => vector.values['device-c'] = 1, throwsUnsupportedError);
  });

  test('sync imports remote pages and uploads assets before page heads', () async {
    final drive = InMemoryDriveSyncGateway();
    final persistenceA = _FakePersistence();
    final persistenceB = _FakePersistence();
    final documentsA = _FakeDocuments([_document('page-a', 'A', assetId: 'asset-a')]);
    final documentsB = _FakeDocuments();
    final accountA = _FakeAccount('account-1');
    final accountB = _FakeAccount('account-1');
    final localA = _BoundStore(documentsA, deviceId: 'device-a');
    final localB = _BoundStore(documentsB, deviceId: 'device-b');
    await localA.putAssetExact(
      LocalAssetSnapshot(
        id: 'asset-a',
        kind: AssetKind.image,
        mime: 'image/png',
        bytes: const [1, 2, 3],
      ),
    );
    final coordinatorA = CloudSyncCoordinator(
      documents: documentsA,
      local: localA,
      account: accountA,
      drive: drive,
      persistence: persistenceA,
    );
    final coordinatorB = CloudSyncCoordinator(
      documents: documentsB,
      local: localB,
      account: accountB,
      drive: drive,
      persistence: persistenceB,
    );
    await coordinatorA.init();
    await coordinatorB.init();

    await coordinatorA.connect();
    final recordsAfterUpload = await drive.listRecords();
    final assetIndex = recordsAfterUpload.indexWhere(
      (record) => record.properties['type'] == 'asset',
    );
    final headIndex = recordsAfterUpload.indexWhere(
      (record) => record.properties['type'] == 'document-head',
    );
    expect(assetIndex, greaterThanOrEqualTo(0));
    expect(headIndex, greaterThan(assetIndex));

    await coordinatorB.connect();
    expect(documentsB.documents.map((document) => document.id), ['page-a']);
    expect(localB.asset('asset-a')?.bytes, [1, 2, 3]);
    expect(coordinatorB.state.phase, CloudSyncPhase.synced);

    await documentsA.deleteDocument('page-a');
    await coordinatorA.syncNow();
    await coordinatorB.syncNow();
    expect(documentsB.documents, isEmpty);
    expect(localB.documentHead('page-a')?.isDeleted, isTrue);

    await coordinatorA.close();
    await coordinatorB.close();
  });

  test('remote pages wait for valid referenced assets', () async {
    final drive = InMemoryDriveSyncGateway();
    final document = _document('remote-page', 'Remote', assetId: 'remote-asset');
    final descriptor = SyncedAssetDescriptor(
      id: 'remote-asset',
      kind: AssetKind.image,
      mime: 'image/png',
      sha256: 'expected-content-hash',
    );
    final head = SyncedDocumentHead(
      documentId: document.id,
      deviceId: 'device-remote',
      vector: SyncVersionVector({'device-remote': 1}),
      stamp: SyncMutationStamp(
        modifiedAt: DateTime.utc(2026, 1, 1),
        deviceId: 'device-remote',
        counter: 1,
      ),
      document: document,
      deletedAt: null,
      assets: [descriptor],
    );
    await drive.createRecord(
      name: 'asset-invalid.bin',
      mimeType: descriptor.mime,
      properties: {
        'type': 'asset',
        'namespace': 'cozy-bloom-sync-v2',
        'sha256': descriptor.sha256,
        'assetId': descriptor.id,
      },
      bytes: const [9, 9, 9],
    );
    await drive.createRecord(
      name: 'document-head.json',
      mimeType: 'application/json',
      properties: {
        'type': 'document-head',
        'namespace': 'cozy-bloom-sync-v2',
        'documentId': head.documentId,
        'deviceId': head.deviceId,
      },
      bytes: jsonUtf8(head.toJson()),
    );
    final documents = _FakeDocuments();
    final coordinator = _coordinator(
      documents,
      _BoundStore(documents, deviceId: 'device-local'),
      _FakeAccount('account-1'),
      drive,
    );
    await coordinator.init();
    await coordinator.connect();

    expect(documents.documents, isEmpty);
    expect(coordinator.state.phase, CloudSyncPhase.synced);
    await coordinator.close();
  });

  test('concurrent edits preserve a conflict copy and converge', () async {
    final drive = InMemoryDriveSyncGateway();
    final document = _document('page-a', 'Original');
    final documentsA = _FakeDocuments([document]);
    final documentsB = _FakeDocuments();
    final coordinatorA = _coordinator(
      documentsA,
      _BoundStore(documentsA, deviceId: 'device-a'),
      _FakeAccount('account-1'),
      drive,
    );
    final coordinatorB = _coordinator(
      documentsB,
      _BoundStore(documentsB, deviceId: 'device-b'),
      _FakeAccount('account-1'),
      drive,
    );
    await coordinatorA.init();
    await coordinatorB.init();
    await coordinatorA.connect();
    await coordinatorB.connect();

    documentsA.replaceWithoutNotify(
      document.copyWith(title: 'A edit', modifiedAt: DateTime.utc(2026, 1, 1)),
    );
    final imported = documentsB.documents.single;
    documentsB.replaceWithoutNotify(
      imported.copyWith(
        title: 'B edit',
        modifiedAt: DateTime.utc(2026, 1, 2),
      ),
    );
    await coordinatorA.syncNow();
    await coordinatorB.syncNow();

    expect(documentsB.documents, hasLength(2));
    expect(
      documentsB.documents.any((entry) => entry.title.contains('conflict from')),
      isTrue,
    );
    final countAfterConflict = documentsB.documents.length;
    await coordinatorB.syncNow();
    expect(documentsB.documents, hasLength(countAfterConflict));

    await coordinatorA.close();
    await coordinatorB.close();
  });

  test('page order is synchronized as a separate collection head', () async {
    final drive = InMemoryDriveSyncGateway();
    final documentsA = _FakeDocuments([
      _document('page-a', 'A'),
      _document('page-b', 'B'),
    ]);
    final documentsB = _FakeDocuments();
    final localA = _BoundStore(documentsA, deviceId: 'device-a');
    final localB = _BoundStore(documentsB, deviceId: 'device-b');
    final coordinatorA = _coordinator(
      documentsA,
      localA,
      _FakeAccount('account-1'),
      drive,
    );
    final coordinatorB = _coordinator(
      documentsB,
      localB,
      _FakeAccount('account-1'),
      drive,
    );
    await coordinatorA.init();
    await coordinatorB.init();
    await coordinatorA.connect();
    await coordinatorB.connect();
    await Future<void>.delayed(Duration.zero);

    documentsA.reorderWithoutNotify(['page-b', 'page-a']);
    await coordinatorA.syncNow();
    await coordinatorB.syncNow();
    expect(documentsB.documents.map((document) => document.id), [
      'page-b',
      'page-a',
    ]);

    await coordinatorA.close();
    await coordinatorB.close();
  });

  test('account switching is blocked until the device is explicitly reset', () async {
    final documents = _FakeDocuments([_document('page-a', 'A')]);
    final local = _BoundStore(documents, deviceId: 'device-a');
    final account = _FakeAccount('account-2');
    final coordinator = _coordinator(
      documents,
      local,
      account,
      InMemoryDriveSyncGateway(),
    );
    await coordinator.init();
    await local.bindAccount('account-1');

    await coordinator.connect();
    expect(coordinator.state.phase, CloudSyncPhase.failed);
    expect(local.boundAccountId, 'account-1');

    await coordinator.resetLocalData();
    expect(local.boundAccountId, isNull);
    expect(documents.documents, isEmpty);
    await coordinator.close();
  });

  test('sync view model forwards commands and publishes immutable state', () async {
    final repository = _FakeCloudSyncRepository();
    final viewModel = CloudSyncViewModel(coordinator: repository);
    expect(viewModel.state.phase, CloudSyncPhase.signedOut);

    repository.publish(const CloudSyncState(
      phase: CloudSyncPhase.synced,
      account: CloudAccount(id: 'account-1', email: 'one@example.test'),
    ));
    await Future<void>.delayed(Duration.zero);
    expect(viewModel.state.phase, CloudSyncPhase.synced);
    await viewModel.syncNow();
    await viewModel.connect();
    await viewModel.reconnect();
    await viewModel.signOut();
    await viewModel.resetLocalData();
    expect(repository.commands, [
      'sync',
      'connect',
      'reauthorize',
      'disconnect',
      'reset',
    ]);
    viewModel.dispose();
    await repository.dispose();
  });

  test('authentication does not implicitly request Drive authorization', () async {
    final documents = _FakeDocuments();
    final account = _FakeAccount('account-1')..driveAuthorized = false;
    final coordinator = _coordinator(
      documents,
      _BoundStore(documents, deviceId: 'device-a'),
      account,
      InMemoryDriveSyncGateway(),
    );
    await coordinator.init();
    await coordinator.connect();

    expect(coordinator.state.phase, CloudSyncPhase.authorizationRequired);
    expect(account.requestAuthorizationCount, 0);

    await coordinator.close();
  });
}

EntryDocument _document(String id, String title, {String? assetId}) => EntryDocument(
      id: id,
      title: title,
      createdAt: DateTime.utc(2026, 1, 1),
      modifiedAt: DateTime.utc(2026, 1, 1),
      nodes: [
        CanvasNode(
          id: '$id-node',
          type: BlockType.text,
          transform: const Transform2D(width: 100, height: 40),
          payload: <String, dynamic>{
            'text': 'Hello',
            ..._assetPayload(assetId),
          },
        ),
      ],
    );

Map<String, dynamic> _assetPayload(String? id) =>
    id == null ? const <String, dynamic>{} : <String, dynamic>{'assetId': id};

List<int> jsonUtf8(Map<String, dynamic> value) => utf8.encode(jsonEncode(value));

CloudSyncCoordinator _coordinator(
  _FakeDocuments documents,
  _BoundStore local,
  _FakeAccount account,
  DriveSyncGateway drive,
) => CloudSyncCoordinator(
      documents: documents,
      local: local,
      account: account,
      drive: drive,
      persistence: _FakePersistence(),
    );

class _FakeDocuments implements DocumentRepository {
  _FakeDocuments([Iterable<EntryDocument> initial = const []])
      : _documents = List<EntryDocument>.from(initial);

  List<EntryDocument> _documents;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Future<void> init() async {}

  @override
  List<EntryDocument> get documents => List.unmodifiable(_documents);

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<EntryDocument> createDocument({String title = ''}) async {
    final next = _document('created-${_documents.length}', title);
    _documents = [..._documents, next];
    _changes.add(null);
    return next;
  }

  @override
  Future<void> saveDocument(EntryDocument document) async {
    replaceWithoutNotify(document);
    _changes.add(null);
  }

  @override
  void previewDocument(EntryDocument document) => replaceWithoutNotify(document);

  @override
  Future<void> deleteDocument(String id) async {
    _documents = _documents.where((document) => document.id != id).toList();
    _changes.add(null);
  }

  void replaceWithoutNotify(EntryDocument document) {
    final index = _documents.indexWhere((item) => item.id == document.id);
    if (index < 0) {
      _documents = [..._documents, document];
    } else {
      _documents = List<EntryDocument>.from(_documents)..[index] = document;
    }
  }

  void reorderWithoutNotify(Iterable<String> ids) {
    final byId = <String, EntryDocument>{
      for (final document in _documents) document.id: document,
    };
    _documents = [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
  }

  Future<void> upsertExact(EntryDocument document) async =>
      replaceWithoutNotify(document);

  Future<void> deleteExact(String id) async {
    _documents = _documents.where((document) => document.id != id).toList();
  }

  Future<void> reorderExact(Iterable<EntryDocument> ordered) async {
    final byId = <String, EntryDocument>{
      for (final document in _documents) document.id: document,
    };
    final next = [
      for (final document in ordered)
        if (byId[document.id] != null) byId[document.id]!,
    ];
    if (next.length == _documents.length) _documents = next;
  }

  void clearAll() => _documents = <EntryDocument>[];
}

class _BoundStore extends MemorySyncLocalStore {
  _BoundStore(this.documents, {required super.deviceId});

  final _FakeDocuments documents;

  @override
  Future<void> upsertDocumentExact(EntryDocument document) =>
      documents.upsertExact(document);

  @override
  Future<void> deleteDocumentExact(String id) => documents.deleteExact(id);

  @override
  Future<void> reorderDocumentsExact(Iterable<EntryDocument> ordered) =>
      documents.reorderExact(ordered);

  @override
  Future<void> clearAllLocalData() async {
    documents.clearAll();
    await super.clearAllLocalData();
  }
}

class _FakeAccount implements CloudAccountGateway {
  _FakeAccount(String id) : _account = CloudAccount(id: id, email: '$id@example.test');

  final CloudAccount _account;
  final StreamController<CloudAuthState> _states =
      StreamController<CloudAuthState>.broadcast();
  bool driveAuthorized = true;
  int requestAuthorizationCount = 0;

  @override
  CloudAuthState get state => const CloudAuthState.signedOut();

  @override
  Stream<CloudAuthState> get states => _states.stream;

  @override
  Future<CloudAccount?> restoreSession() async => null;

  @override
  Future<CloudAccount> authenticate() async => _account;

  @override
  Future<bool> hasDriveAuthorization() async => driveAuthorized;

  @override
  Future<void> requestDriveAuthorization() async => requestAuthorizationCount++;

  @override
  Future<String?> accessToken() async => 'test-token';

  @override
  Future<void> signOut() async {}

  @override
  Future<void> dispose() => _states.close();
}

class _FakePersistence implements PersistenceRepository {
  int flushCount = 0;

  @override
  void addFlushHook(Future<void> Function() hook) {}

  @override
  void removeFlushHook(Future<void> Function() hook) {}

  @override
  Future<void> flush() async => flushCount++;
}

class _FakeCloudSyncRepository implements CloudSyncRepository {
  _FakeCloudSyncRepository()
      : _state = const CloudSyncState(phase: CloudSyncPhase.signedOut);

  final StreamController<CloudSyncState> _states =
      StreamController<CloudSyncState>.broadcast();
  final List<String> commands = <String>[];
  CloudSyncState _state;

  @override
  CloudSyncState get state => _state;

  @override
  Stream<CloudSyncState> get states => _states.stream;

  void publish(CloudSyncState state) {
    _state = state;
    _states.add(state);
  }

  @override
  Future<void> connect() async => commands.add('connect');

  @override
  Future<void> reauthorize() async => commands.add('reauthorize');

  @override
  Future<void> disconnect() async => commands.add('disconnect');

  @override
  Future<void> resetLocalData() async => commands.add('reset');

  @override
  Future<void> syncNow({bool initial = false}) async => commands.add('sync');

  Future<void> dispose() => _states.close();
}
