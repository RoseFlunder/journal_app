// The public constructor keeps capability names stable while storing them in
// private fields; initializing-formal linting cannot express that distinction.
// ignore_for_file: prefer_initializing_formals, use_super_parameters

import 'dart:async';
import 'dart:typed_data';

import '../../../../editor/editor_controller.dart';
import '../../../../models/document.dart';
import '../../../../models/page_music.dart';
import '../../../../models/view_state.dart';
import '../../../../services/audio_playback.dart';
import '../../../../services/image_source.dart';
import '../../../../services/image_processing.dart';
import '../../../../services/repositories.dart';
import '../use_cases/archive_transfer_use_case.dart';
import '../use_cases/checkpoint_recovery_use_case.dart';
import '../use_cases/image_insertion_use_case.dart';
import 'editor_tool_state.dart';
import '../../music/view_models/music_picker_view_model.dart';

typedef EntryEditorViewModelFactory = EntryEditorViewModel Function(
  EntryDocument document,
);

/// Editor feature view model backed by the document repository.
class EntryEditorViewModel extends EditorController {
  static const _formatUnset = Object();

  EntryEditorViewModel({
    required EntryDocument document,
    required DocumentRepository documentRepository,
    required CheckpointRepository checkpointRepository,
    required AssetRepository assetRepository,
    required PreferencesRepository preferenceRepository,
    required PersistenceRepository persistenceRepository,
    required ArchiveRepository archiveRepository,
    required MusicCatalogRepository musicCatalog,
    required AudioPlaybackFactory audioPlaybackFactory,
    required ImageInsertionUseCase imageInsertion,
    required ArchiveTransferUseCase archiveTransfer,
    super.maxHistory,
  }) : _documentId = document.id,
       _documentRepository = documentRepository,
       _checkpointRepository = checkpointRepository,
       _assets = assetRepository,
       _preferences = preferenceRepository,
       _persistence = persistenceRepository,
       _musicCatalog = musicCatalog,
       _audioPlaybackFactory = audioPlaybackFactory,
       _imageInsertion = imageInsertion,
       _archiveTransfer = archiveTransfer,
       super(
         document: document,
         persistDocument: (EntryDocument next) =>
             _persistCurrentDocument(
               documentRepository,
               checkpointRepository,
               document,
               next,
             ),
       );

  final String _documentId;
  final DocumentRepository _documentRepository;
  final CheckpointRepository _checkpointRepository;
  final AssetRepository _assets;
  final PreferencesRepository _preferences;
  final PersistenceRepository _persistence;
  final MusicCatalogRepository _musicCatalog;
  final AudioPlaybackFactory _audioPlaybackFactory;
  final ImageInsertionUseCase _imageInsertion;
  final ArchiveTransferUseCase _archiveTransfer;

  bool _editing = false;
  bool _selectMode = false;
  bool _drawMode = false;
  String? _textEditingId;
  String? _workflowError;
  EntryDocument? _pendingMetadata;
  InkSettings _inkSettings = const InkSettings();

  String get documentId => _documentId;
  String? get workflowError => _workflowError;
  /// Repository capabilities stay private to this feature model; callers see
  /// only feature operations and immutable values.
  Uint8List? readAsset(String id) => _assets.readAsset(id);

  /// Creates the configured music picker model without exposing the catalog
  /// or playback factory to a feature view.
  MusicPickerViewModel createMusicPickerViewModel({PageMusicTrack? current}) =>
      MusicPickerViewModel(
        catalog: _musicCatalog,
        playback: _audioPlaybackFactory(),
        current: current,
      );

  /// Coordinates editor flushes with the application persistence owner.
  void addFlushHook(Future<void> Function() hook) =>
      _persistence.addFlushHook(hook);

  void removeFlushHook(Future<void> Function() hook) =>
      _persistence.removeFlushHook(hook);

  Future<void> flushPersistence() => _persistence.flush();

  /// Current immutable settings for newly-created vector ink.
  InkSettings get inkSettings => _inkSettings;

  /// Updates the transient ink tool state without adding an editor history
  /// command. The values are consumed by the canvas while drawing.
  void updateInkSettings(InkSettings value) {
    if (_inkSettings == value) return;
    _inkSettings = value;
    notifyListeners();
  }

  List<int> get recentColorValues => _preferences.recentColorValues;

  Set<int> get favoriteColorValues => _preferences.favoriteColorValues;

  void addRecentColor(int value) {
    final recent = [
      value,
      ..._preferences.recentColorValues.where((item) => item != value),
    ].take(8).toList(growable: false);
    unawaited(_preferences.updateColorPreferences(recent: recent));
  }

  void updateFavoriteColors(Set<int> values) {
    unawaited(_preferences.updateColorPreferences(favorites: values));
  }

  /// Runs media cleanup without deleting assets still reachable from this
  /// editor's immutable undo/redo or clipboard snapshots.
  Future<void> collectUnreferencedAssets() =>
      _assets.collectUnreferencedAssets(
        retainedAssetIds: retainedAssetIds,
      );

  /// Presentation/tool state that must stay consistent with the document
  /// selection. Flutter-only focus, dialogs, and animations remain in views.
  bool get editing => _editing;
  set editing(bool value) {
    if (_editing == value) return;
    _editing = value;
    notifyListeners();
  }

  bool get selectMode => _selectMode;
  set selectMode(bool value) {
    if (_selectMode == value && (!value || !_drawMode)) return;
    _selectMode = value;
    if (value) _drawMode = false;
    notifyListeners();
  }

  bool get drawMode => _drawMode;
  set drawMode(bool value) {
    if (_drawMode == value && (!value || !_selectMode)) return;
    _drawMode = value;
    if (value) _selectMode = false;
    notifyListeners();
  }

  String? get textEditingId => _textEditingId;
  set textEditingId(String? value) {
    if (_textEditingId == value) return;
    _textEditingId = value;
    notifyListeners();
  }

  /// Publishes title, view, music, and other document metadata from the
  /// feature boundary. Metadata is deliberately not added to node history,
  /// but it is persisted through the same document capability.
  Future<void> updateMetadata(EntryDocument next) async {
    updateDocumentMetadata(next);
    try {
      await _documentRepository.saveDocument(next);
      _pendingMetadata = null;
      _setWorkflowError(null);
    } catch (error) {
      _pendingMetadata = next;
      _setWorkflowError(error.toString());
    }
  }

  /// Persists page ambience metadata through the editor boundary.
  Future<void> updateMusic(PageMusicTrack? track) => updateMetadata(
    document.copyWith(music: track, modifiedAt: DateTime.now()),
  );

  /// Persists the page camera state as document metadata.
  Future<void> updateView(ViewState view) => updateMetadata(
    document.copyWith(view: view, modifiedAt: DateTime.now()),
  );

  /// Persists the page title as document metadata.
  Future<void> updateTitle(String title) => updateMetadata(
    document.copyWith(title: title, modifiedAt: DateTime.now()),
  );

  /// Applies text styling to one immutable node. Callers may wrap a series of
  /// previews in an existing transaction (for example, a color picker); a
  /// standalone update owns and commits its transaction here.
  Future<void> updateTextFormatting(
    String nodeId, {
    Object? fontFamily = _formatUnset,
    double? fontSize,
    Object? textColorValue = _formatUnset,
    bool? bold,
    bool? italic,
  }) async {
    final node = document.nodeById(nodeId);
    if (node == null || node.type != BlockType.text || node.locked) return;
    final ownsTransaction = !inTransaction;
    if (ownsTransaction) {
      beginStyleTransaction('Format text');
    }
    final payload = Map<String, dynamic>.from(node.payload);
    if (!identical(fontFamily, _formatUnset)) {
      payload['fontFamily'] = fontFamily as String?;
    }
    if (fontSize != null) payload['fontSize'] = fontSize;
    if (!identical(textColorValue, _formatUnset)) {
      payload['textColorValue'] = textColorValue as int?;
    }
    if (bold != null) payload['bold'] = bold;
    if (italic != null) payload['italic'] = italic;
    replaceNode(node.copyWith(payload: payload), label: 'Format text');
    if (ownsTransaction) await commitTransaction();
  }

  /// Persists title styling as document metadata rather than node history.
  Future<void> updateTitleFormatting({
    Object? fontFamily = _formatUnset,
    double? fontSize,
    Object? textColorValue = _formatUnset,
    bool? bold,
    bool? italic,
  }) => updateMetadata(
    document.copyWith(
      titleFontFamily: identical(fontFamily, _formatUnset)
          ? document.titleFontFamily
          : fontFamily as String?,
      titleFontSize: fontSize,
      titleTextColorValue: identical(textColorValue, _formatUnset)
          ? document.titleTextColorValue
          : textColorValue as int?,
      titleBold: bold,
      titleItalic: italic,
      modifiedAt: DateTime.now(),
    ),
  );

  void clearWorkflowError() => _setWorkflowError(null);

  @override
  Future<void> retrySave() {
    final pending = _pendingMetadata;
    if (pending != null) return updateMetadata(pending);
    return super.retrySave();
  }

  void _setWorkflowError(String? value) {
    if (_workflowError == value) return;
    _workflowError = value;
    notifyListeners();
  }

  String? get selectedId => selection.isEmpty ? null : selection.last;

  late final CheckpointRecoveryUseCase _checkpointRecovery =
      CheckpointRecoveryUseCase(
        checkpoints: _checkpointRepository,
        documents: _documentRepository,
      );

  Future<({ProcessedImage image, String assetId})> insertImageAsset({
    required String ownerId,
    required PickedImage picked,
  }) => _imageInsertion.processAndStore(ownerId: ownerId, picked: picked);

  List<CheckpointInfo> checkpointsFor(String id) =>
      _checkpointRecovery.forDocument(id);

  Future<void> createCheckpoint(String id) => _checkpointRecovery.create(id);

  Future<EntryDocument?> restoreCheckpoint({
    required String checkpointId,
    required String documentId,
  }) =>
      _checkpointRecovery.restore(
        checkpointId: checkpointId,
        documentId: documentId,
      );

  Future<bool> exportArchive({
    required String documentId,
    required String fileName,
  }) => _archiveTransfer.exportDocument(documentId: documentId, fileName: fileName);

  Future<EntryDocument?> importArchive() => _archiveTransfer.importDocument();

}

Future<void> _persistCurrentDocument(
  DocumentRepository documentRepository,
  CheckpointRepository checkpointRepository,
  EntryDocument initial,
  EntryDocument next,
) async {
  final current = documentRepository.documents.firstWhere(
    (document) => document.id == initial.id,
    orElse: () => initial,
  );
  await documentRepository.saveDocument(
    current.copyWith(
      nodes: next.nodes,
      board: next.board,
      modifiedAt: DateTime.now(),
    ),
  );
  checkpointRepository.scheduleCheckpoint(initial.id);
}
