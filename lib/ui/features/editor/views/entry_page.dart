import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../editor/editor_state.dart';
import '../../../../editor/image_layout.dart';
import '../../../../models/document.dart';
import '../../../../models/sticker.dart';
import '../../../../models/view_state.dart';
import '../../../../services/image_source.dart';
import '../../../../models/journal_share_result.dart';
import '../view_models/entry_editor_view_model.dart';
import '../view_models/editor_tool_state.dart';
import 'entry_editor_surface.dart';
import 'editor_canvas_view.dart';
import 'editor_layers_view.dart';
import 'photo_import_editor.dart';
import 'editor_toolbar_view.dart';
import 'editor_more_tools_view.dart';
import 'editor_ink_settings_view.dart';
import 'editor_music_view.dart';
import '../../music/view_models/page_music_controller.dart';
import '../../../../widgets/entry_chrome.dart';
import '../../../../widgets/page_viewport.dart';
import '../../../../widgets/paper_page.dart';

/// Shows one immutable [EntryDocument] as a journal page.
///
/// Renders one framed paper page and its freely positioned content blocks.
class EntryPage extends StatefulWidget {
  const EntryPage({
    super.key,
    required this.viewModel,
    this.onDocumentPreviewChanged,
    required this.onEditingChanged,
    required this.active,
    required this.musicController,
    this.controlsVisible = true,
    required this.imageSource,
  });

  /// Configured editor state for this page. The owner of the page disposes
  /// the model after the page is removed from the journal.
  final EntryEditorViewModel viewModel;
  final ValueChanged<EntryDocument>? onDocumentPreviewChanged;
  final ValueChanged<bool> onEditingChanged;
  final bool controlsVisible;
  final bool active;
  final PageMusicController musicController;

  final ImageSourceService imageSource;

  @override
  State<EntryPage> createState() => _EntryPageState();
}

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({required this.title, required this.label});

  final String title;
  final String label;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      textInputAction: TextInputAction.done,
      onSubmitted: (value) => Navigator.pop(context, value),
      decoration: InputDecoration(labelText: widget.label),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('Save'),
      ),
    ],
  );
}

class _EntryPageState extends State<EntryPage> with WidgetsBindingObserver {
  static const _uuid = Uuid();
  static const _workspaceSize = PageViewport.pageSize;
  static const _pageFramePosition = Offset.zero;
  // Existing block coordinates are model-local and were historically given a
  // 50-unit page inset by the infinite-board origin. Keep that visual inset
  // while rendering against the finite page origin.
  static const _worldOrigin = Offset(50, 50);
  static const _headerPosition = Offset.zero;
  static const _fontSizeStep = 2.0;
  static const _minFontSize = 12.0;
  static const _maxFontSize = 48.0;
  bool _resizeActive = false;
  double _cameraScale = 1;
  Rect? _visibleCanvasRect;
  bool _titleFocused = false;
  String? _colorTransactionBlockId;
  bool _strokeColorTransactionActive = false;
  bool _samplingColor = false;
  final GlobalKey _pageCaptureKey = GlobalKey();
  Completer<Color?>? _colorSampleCompleter;
  late final TextEditingController _titleController = TextEditingController(
    text: widget.viewModel.document.title,
  );
  late final FocusNode _titleFocusNode = FocusNode()
    ..addListener(_handleTitleFocusChanged);
  late final ImageSourceService _imageSource = widget.imageSource;
  bool _pickingImage = false;
  bool _musicPickerOpen = false;
  final Map<String, ImageProvider<Object>> _imageProviders = {};
  final Map<String, ImageProvider<Object>> _stickerProviders = {};
  late EntryEditorViewModel _editor;
  Future<void> Function()? _flushHook;
  String? _lastWorkflowError;

  EntryDocument get _document => _editor.document;

  // Presentation/tool state is owned by the feature view model. These
  // forwarding accessors keep this surface readable while the view is
  // split into feature-native widgets.
  bool get _editing => _editor.editing;
  set _editing(bool value) => _editor.editing = value;
  bool get _selectMode => _editor.selectMode;
  set _selectMode(bool value) => _editor.selectMode = value;
  bool get _drawMode => _editor.drawMode;
  set _drawMode(bool value) => _editor.drawMode = value;
  String? get _textEditingId => _editor.textEditingId;
  set _textEditingId(String? value) => _editor.textEditingId = value;
  String? get _selectedId => _editor.selectedId;
  set _selectedId(String? value) => _editor.select(value);

  List<CanvasNode> get _nodes => _editor.allNodes;

  InkSettings get _inkSettings => _editor.inkSettings;
  int get _inkColorValue => _inkSettings.colorValue;
  double get _inkWidth => _inkSettings.width;
  double get _inkOpacity => _inkSettings.opacity;
  InkStrokeType get _inkStrokeType => _inkSettings.strokeType;

  CanvasNode? get _activeStrokeBlock {
    final primary = _editor.primaryNode;
    if (primary != null &&
        _isDrawable(primary) &&
        !primary.locked &&
        !primary.hidden) {
      return primary;
    }
    for (final block in _editor.selectedDrawableNodes) {
      if (!block.locked && !block.hidden) return block;
    }
    return null;
  }

  bool get _strokeColorAvailable =>
      _editor.selectedDrawableNodes.any((node) => !node.locked);

  CanvasNode? get _singleSelectedImage {
    if (_editor.selection.length != 1) return null;
    final node = _editor.primaryNode;
    return node?.type == BlockType.image ? node : null;
  }

  int? get _activeStrokeColorValue {
    final block = _activeStrokeBlock;
    if (block == null) return null;
    return Color(block.strokeColorValue ?? PaperPage.ink.toARGB32())
        .withValues(alpha: block.opacity.clamp(0.0, 1.0).toDouble())
        .toARGB32();
  }

  int get _inkPickerValue => _inkSettings.pickerValue;

  bool _isDrawable(CanvasRenderable block) =>
      block.type == BlockType.ink || block.type == BlockType.shape;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attachEditor(widget.viewModel);
  }

  @override
  void didUpdateWidget(covariant EntryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.viewModel, widget.viewModel)) {
      _detachEditor();
      _attachEditor(widget.viewModel);
      if (!_titleFocused) {
        _titleController.text = _document.title;
      }
    }
  }

  void _handleEditorChanged() {
    // Keep the app's in-memory entry current for immediate previews and UI
    // consumers, while the controller still batches the Hive write itself.
    widget.onDocumentPreviewChanged?.call(_document);
    final workflowError = _editor.workflowError;
    if (workflowError != null && workflowError != _lastWorkflowError) {
      _lastWorkflowError = workflowError;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save this change: $workflowError'),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => unawaited(_editor.retrySave()),
            ),
          ),
        );
      });
    } else if (workflowError == null) {
      _lastWorkflowError = null;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _colorSampleCompleter?.complete(null);
    _colorSampleCompleter = null;
    WidgetsBinding.instance.removeObserver(this);
    _detachEditor();
    _titleController.dispose();
    _titleFocusNode
      ..removeListener(_handleTitleFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _attachEditor(EntryEditorViewModel editor) {
    _editor = editor..addListener(_handleEditorChanged);
    _flushHook = _editor.flushText;
    _editor.addFlushHook(_flushHook!);
  }

  void _detachEditor() {
    final flushHook = _flushHook;
    if (flushHook != null) _editor.removeFlushHook(flushHook);
    _flushHook = null;
    _editor.removeListener(_handleEditorChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_flushLifecycle());
      if (widget.active) unawaited(widget.musicController.stopAndReset());
    }
  }

  Future<void> _flushLifecycle() async {
    await _editor.flushPersistence();
    await _editor.createCheckpoint(_document.id);
    await _editor.flushPersistence();
  }

  void _handleTitleFocusChanged() {
    if (!mounted || !_titleFocusNode.hasFocus || _titleFocused) return;
    setState(() {
      _titleFocused = true;
      _textEditingId = null;
    });
  }

  void _beginTextEditing(String blockId) {
    _editor.select(blockId);
    setState(() {
      _titleFocused = false;
      _selectedId = blockId;
      _textEditingId = blockId;
    });
  }

  void _stopTextEditing() {
    // Commit before dropping the editing flags so the last keystroke cannot
    // race the TextField's disposal. Hiding the platform input explicitly is
    // important on mobile where unfocus alone may keep the composing surface.
    unawaited(_editor.flushText());
    FocusScope.of(context).unfocus();
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
    setState(() {
      _titleFocused = false;
      _textEditingId = null;
    });
  }

  void _finishEditing() {
    // Clear both the visible selection and the controller selection. The
    // canvas intentionally renders every controller-selected block, so
    // clearing only [_selectedId] could leave a block looking editable.
    unawaited(_editor.flushText());
    FocusScope.of(context).unfocus();
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
    _editor.select(null);
    setState(() {
      _editing = false;
      _resizeActive = false;
      _titleFocused = false;
      _selectedId = null;
      _textEditingId = null;
      _selectMode = false;
      _drawMode = false;
    });
    widget.onEditingChanged(false);
  }

  CanvasNode? get _editingTextBlock {
    final id = _textEditingId;
    if (id == null) return null;
    for (final block in _nodes) {
      if (block.id == id && block.type == BlockType.text) return block;
    }
    return null;
  }

  CanvasNode? get _activeTextBlock {
    if (_titleFocused) return null;
    final editing = _editingTextBlock;
    if (editing != null) return editing;
    final selectedId = _selectedId;
    if (selectedId == null) return null;
    for (final block in _nodes) {
      if (block.id == selectedId && block.type == BlockType.text) return block;
    }
    return null;
  }

  String? get _activeFontFamily {
    final block = _activeTextBlock;
    return block?.fontFamily ??
        (_titleFocused ? _document.titleFontFamily : null);
  }

  bool get _textFormattingAvailable =>
      _titleFocused || _activeTextBlock != null;

  void _handleViewChanged(ViewState view) =>
      unawaited(_editor.updateView(view));

  int? get _activeTextColor {
    final block = _activeTextBlock;
    return block?.textColorValue ??
        (_titleFocused ? _document.titleTextColorValue : null);
  }

  void _changeFontFamily(String? fontFamily) {
    final block = _activeTextBlock;
    if (block != null) {
      unawaited(_editor.updateTextFormatting(block.id, fontFamily: fontFamily));
    } else if (_titleFocused) {
      unawaited(_editor.updateTitleFormatting(fontFamily: fontFamily));
    }
    setState(() {});
  }

  double get _activeFontSize =>
      _activeTextBlock?.fontSize ?? _document.titleFontSize;

  bool get _activeBold => _activeTextBlock?.bold ?? _document.titleBold;

  bool get _activeItalic => _activeTextBlock?.italic ?? _document.titleItalic;

  void _changeFontSize(double delta) {
    final block = _activeTextBlock;
    if (block == null && !_titleFocused) return;
    final size = (_activeFontSize + delta)
        .clamp(_minFontSize, _maxFontSize)
        .toDouble();
    if (block != null) {
      unawaited(_editor.updateTextFormatting(block.id, fontSize: size));
    } else {
      unawaited(_editor.updateTitleFormatting(fontSize: size));
    }
    setState(() {});
  }

  void _toggleBold() {
    final block = _activeTextBlock;
    if (block == null && !_titleFocused) return;
    if (block != null) {
      unawaited(_editor.updateTextFormatting(block.id, bold: !block.bold));
    } else {
      unawaited(_editor.updateTitleFormatting(bold: !_document.titleBold));
    }
    setState(() {});
  }

  void _toggleItalic() {
    final block = _activeTextBlock;
    if (block == null && !_titleFocused) return;
    if (block != null) {
      unawaited(_editor.updateTextFormatting(block.id, italic: !block.italic));
    } else {
      unawaited(_editor.updateTitleFormatting(italic: !_document.titleItalic));
    }
    setState(() {});
  }

  void _changeTextColor(int? value) {
    final block = _activeTextBlock;
    if (block != null) {
      unawaited(_editor.updateTextFormatting(block.id, textColorValue: value));
    } else if (_titleFocused) {
      unawaited(_editor.updateTitleFormatting(textColorValue: value));
    }
    setState(() {});
  }

  void _beginTextColorEdit() {
    final block = _activeTextBlock;
    if (block == null) return;
    _colorTransactionBlockId = block.id;
    _editor.beginStyleTransaction('Format text');
  }

  void _endTextColorEdit() {
    if (_colorTransactionBlockId == null) return;
    _colorTransactionBlockId = null;
    unawaited(_editor.commitTransaction());
  }

  void _applyInkColorValue(int? value, {VoidCallback? refreshSheet}) {
    final color = value == null ? PaperPage.ink : Color(value);
    _editor.updateInkSettings(
      _inkSettings.copyWith(
        colorValue: color.withValues(alpha: 1).toARGB32(),
        opacity: value == null ? 1 : color.a,
      ),
    );
    refreshSheet?.call();
  }

  void _beginStrokeColorEdit() {
    if (!_strokeColorAvailable) return;
    _strokeColorTransactionActive = true;
    _editor.beginStyleTransaction('Format stroke');
  }

  void _changeStrokeColor(int? value) {
    final color = value == null ? PaperPage.ink : Color(value);
    _editor.updateSelectedDrawableStroke(
      colorValue: color.withValues(alpha: 1).toARGB32(),
      opacity: value == null ? 1 : color.a,
    );
    setState(() {});
  }

  void _endStrokeColorEdit() {
    if (!_strokeColorTransactionActive) return;
    _strokeColorTransactionActive = false;
    unawaited(_editor.commitTransaction());
  }

  Future<Color?> _sampleFromInkSettings(BuildContext sheetContext) async {
    if (!sheetContext.mounted) return null;
    Navigator.pop(sheetContext, true);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return null;
    return _requestColorSample();
  }

  Future<InkSettings?> _openInkColorPicker(
    BuildContext sheetContext,
    InkSettings current,
  ) async {
    final original = current;
    InkSettings preview = current;
    final result = await showVisualColorPicker(
      sheetContext,
      initialValue: current.pickerValue,
      dialogTitle: 'Ink color',
      recentColorValues: _editor.recentColorValues,
      favoriteColorValues: _editor.favoriteColorValues,
      onPreview: (value) {
        preview = _inkSettingsForColor(current, value);
        _editor.updateInkSettings(preview);
      },
      onFavoriteColorsChanged: _editor.updateFavoriteColors,
      onSampleColor: () => _sampleFromInkSettings(sheetContext),
    );
    if (!mounted) return null;
    if (result?.isSample == true) {
      if (!sheetContext.mounted) return null;
      final sampled = await _sampleFromInkSettings(sheetContext);
      if (sampled == null) {
        _editor.updateInkSettings(original);
        return null;
      } else {
        final value = sampled.toARGB32();
        final next = _inkSettingsForColor(current, value);
        _editor.updateInkSettings(next);
        _editor.addRecentColor(value);
        return next;
      }
    }
    if (result == null) {
      _editor.updateInkSettings(original);
      return null;
    }
    final next = _inkSettingsForColor(preview, result.value);
    _editor.updateInkSettings(next);
    if (result.value != null) _editor.addRecentColor(result.value!);
    return next;
  }

  InkSettings _inkSettingsForColor(InkSettings base, int? value) {
    final color = value == null ? PaperPage.ink : Color(value);
    return base.copyWith(
      colorValue: color.withValues(alpha: 1).toARGB32(),
      opacity: value == null ? 1 : color.a,
    );
  }

  Future<Color?> _requestColorSample() {
    final current = _colorSampleCompleter;
    if (current != null) return current.future;
    final completer = Completer<Color?>();
    _colorSampleCompleter = completer;
    setState(() => _samplingColor = true);
    return completer.future;
  }

  Future<void> _completeColorSample(Offset globalPosition) async {
    final completer = _colorSampleCompleter;
    if (completer == null) return;
    Color? sampled;
    try {
      final renderObject = _pageCaptureKey.currentContext?.findRenderObject();
      if (renderObject is RenderRepaintBoundary) {
        final box = renderObject;
        final local = box.globalToLocal(globalPosition);
        if ((Offset.zero & box.size).contains(local)) {
          final image = await box.toImage(pixelRatio: 1);
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          if (data != null && image.width > 0 && image.height > 0) {
            final x = (local.dx * image.width / box.size.width)
                .clamp(0, image.width - 1)
                .floor();
            final y = (local.dy * image.height / box.size.height)
                .clamp(0, image.height - 1)
                .floor();
            final index = (y * image.width + x) * 4;
            if (index + 3 < data.lengthInBytes) {
              sampled = Color.fromARGB(
                data.getUint8(index + 3),
                data.getUint8(index),
                data.getUint8(index + 1),
                data.getUint8(index + 2),
              );
            }
          }
        }
      }
    } catch (_) {
      sampled = null;
    }
    _colorSampleCompleter = null;
    if (mounted) setState(() => _samplingColor = false);
    if (sampled == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not sample that page color.')),
      );
    }
    if (!completer.isCompleted) completer.complete(sampled);
  }

  void _cancelColorSample() {
    final completer = _colorSampleCompleter;
    _colorSampleCompleter = null;
    if (mounted) setState(() => _samplingColor = false);
    if (completer != null && !completer.isCompleted) completer.complete(null);
  }

  TextStyle _titleStyle(BuildContext context) =>
      (Theme.of(context).textTheme.headlineSmall ?? const TextStyle()).copyWith(
        fontSize: _document.titleFontSize,
        fontFamily: _document.titleFontFamily,
        color: _document.titleTextColorValue == null
            ? PaperPage.ink
            : Color(_document.titleTextColorValue!),
        fontWeight: _document.titleBold ? FontWeight.bold : FontWeight.normal,
        fontStyle: _document.titleItalic ? FontStyle.italic : FontStyle.normal,
      );

  void _addText() {
    final node = CanvasNode(
      id: _uuid.v4(),
      type: BlockType.text,
      transform: Transform2D(
        x: -20,
        y: 12 + (_nodes.length * 8) % 80,
        width: 30,
        height: 11,
      ),
      payload: const {'text': '', 'fontSize': 26},
    );
    _editor.addNode(node);
    setState(() {
      _titleFocused = false;
      _selectedId = node.id;
      _textEditingId = node.id;
    });
  }

  Future<void> _addImage() async {
    if (_pickingImage) return;
    setState(() => _pickingImage = true);
    try {
      final origin = await _chooseImageOrigin();
      if (!mounted || origin == null) return;
      final picked = await _imageSource.pickImage(origin);
      if (!mounted || picked == null) return;
      final prepared = await _editor.prepareImage(picked);
      if (!mounted) return;
      final edited = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
          builder: (_) => PhotoImportEditor(bytes: prepared.bytes),
        ),
      );
      if (!mounted || edited == null) return;
      final stored = await _editor.insertImageAsset(
        picked: PickedImage(bytes: edited, mime: 'image/png'),
      );
      final image = stored.image;
      final assetId = stored.assetId;
      if (!mounted) return;
      final size = imageBlockSize(image.width, image.height);
      final node = CanvasNode(
        id: _uuid.v4(),
        type: BlockType.image,
        transform: Transform2D(
          x: -20,
          y: 12 + (_nodes.length * 8) % 80,
          width: size.width,
          height: size.height,
        ),
        payload: {'assetId': assetId},
      );
      _editor.addNode(node);
      setState(() => _selectedId = node.id);
    } on FormatException catch (error) {
      if (mounted) _showImageError(error.message);
    } catch (error) {
      if (mounted) _showImageError('Could not add image: $error');
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  Future<ImagePickOrigin?> _chooseImageOrigin() {
    final origins = _imageSource.supportedOrigins;
    if (origins.length == 1) return Future.value(origins.single);
    return showModalBottomSheet<ImagePickOrigin>(
      context: context,
      backgroundColor: PaperPage.paper,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            if (origins.contains(ImagePickOrigin.gallery))
              ListTile(
                key: const ValueKey('pick-image-gallery'),
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(context, ImagePickOrigin.gallery),
              ),
            if (origins.contains(ImagePickOrigin.camera))
              ListTile(
                key: const ValueKey('pick-image-camera'),
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(context, ImagePickOrigin.camera),
              ),
            if (origins.contains(ImagePickOrigin.file))
              ListTile(
                key: const ValueKey('pick-image-file'),
                leading: const Icon(Icons.upload_file_outlined),
                title: const Text('Choose image file'),
                onTap: () => Navigator.pop(context, ImagePickOrigin.file),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _addSticker() async {
    final sticker = await showModalBottomSheet<StickerDefinition>(
      context: context,
      backgroundColor: PaperPage.paper,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.76,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sticker pack',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: StickerCatalog.definitions.length,
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 150,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.1,
                        ),
                    itemBuilder: (context, index) {
                      final definition = StickerCatalog.definitions[index];
                      return Semantics(
                        button: true,
                        label: 'Add ${definition.label} sticker',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => Navigator.pop(context, definition),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7EFE6),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: PaperPage.ink.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Image.asset(definition.assetPath),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || sticker == null) return;
    final node = CanvasNode(
      id: _uuid.v4(),
      type: BlockType.sticker,
      transform: Transform2D(
        x: 8,
        y: 40 + (_nodes.length * 5) % 60,
        width: sticker.defaultSize.width,
        height: sticker.defaultSize.height,
      ),
      payload: {'stickerId': sticker.id},
    );
    _editor.addNode(node);
    setState(() => _selectedId = node.id);
  }

  ImageProvider<Object>? _imageProvider(String assetId) {
    final sticker = StickerCatalog.byId(assetId);
    if (sticker != null) {
      return _stickerProviders.putIfAbsent(
        assetId,
        () => AssetImage(sticker.assetPath),
      );
    }
    final cached = _imageProviders[assetId];
    if (cached != null) return cached;
    final bytes = _editor.readAsset(assetId);
    if (bytes == null) return null;
    // Imported photos can be substantially larger than an Android display.
    // A capped decode avoids allocating the full source bitmap while keeping
    // enough detail for the editor's supported zoom range.
    return _imageProviders[assetId] = ResizeImage.resizeIfNeeded(
      2048,
      2048,
      MemoryImage(bytes),
    );
  }

  void _showImageError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openImage(CanvasRenderable block) async {
    final assetId = block.assetId;
    final bytes = assetId == null ? null : _editor.readAsset(assetId);
    if (bytes == null || !mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: InteractiveViewer(
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      ),
    );
  }

  bool _sharing = false;

  Future<void> _sharePage() async {
    if (!mounted || _sharing) return;
    _sharing = true;
    FocusScope.of(context).unfocus();
    final messenger = ScaffoldMessenger.of(context);
    final progress = messenger.showSnackBar(
      const SnackBar(
        duration: Duration(minutes: 2),
        content: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Preparing page to share...'),
          ],
        ),
      ),
    );
    try {
      final result = await _editor.sharePage();
      progress.close();
      if (!mounted) return;
      if (result == JournalShareResult.unavailable) {
        final save = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Save this page instead?'),
            content: const Text(
              'Sharing is unavailable. You can save the file and send it later.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save file'),
              ),
            ],
          ),
        );
        if (save == true && mounted) {
          final saved = await _editor.saveSharedPage();
          if (saved && mounted) {
            messenger.showSnackBar(
              const SnackBar(content: Text('Shared page saved')),
            );
          }
        }
      }
    } catch (_) {
      progress.close();
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Could not share this page. Please try again.'),
          ),
        );
      }
    } finally {
      _sharing = false;
    }
  }

  Future<void> _showInkSettings() async {
    final original = _inkSettings;
    final result = await showModalBottomSheet<InkSettings>(
      context: context,
      backgroundColor: PaperPage.paper,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => EditorInkSettingsView(
        initial: original,
        onPreview: _editor.updateInkSettings,
        onPickColor: _openInkColorPicker,
      ),
    );
    if (!mounted || result != null) return;
    _editor.updateInkSettings(original);
  }

  void _showMoreTools() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: PaperPage.paper,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => EditorMoreToolsView(
        canUndo: _editor.canUndo,
        canRedo: _editor.canRedo,
        canGroup: _editor.canGroup,
        canUngroup: _editor.canUngroup,
        hasMusic: _document.music != null,
        selectMode: _selectMode,
        drawMode: _drawMode,
        onUndo: _undo,
        onRedo: _redo,
        onShare: _sharePage,
        onGroup: _editor.groupSelection,
        onUngroup: _editor.ungroupSelection,
        onToggleSelectMode: () => _selectMode = !_selectMode,
        onToggleDrawMode: () {
          _drawMode = !_drawMode;
          if (_drawMode) _selectMode = false;
        },
        onInkSettings: _showInkSettings,
        onMusic: () => unawaited(_showMusicPicker()),
        onLayers: _showLayers,
      ),
    );
  }

  void _useSelectedImageAsPreview() {
    final node = _singleSelectedImage;
    if (node == null) return;
    unawaited(_editor.setPreviewImage(node.id));
  }

  Future<void> _showMusicPicker() async {
    if (_musicPickerOpen) return;
    _musicPickerOpen = true;
    try {
      final result = await EditorMusicView.showPicker(
        context,
        editor: _editor,
        current: _document.music,
        playback: widget.musicController,
      );
      if (!mounted || result == null) return;
      final track = result.remove ? null : result.track;
      await _editor.updateMusic(track);
      if (!mounted) return;
      await widget.musicController.setActivePage(
        widget.active ? _document.id : null,
        widget.active ? track : null,
        resume: true,
      );
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not switch page music: $error')),
        );
      }
    } finally {
      _musicPickerOpen = false;
    }
  }

  void _deleteSelected() {
    final selectedId = _selectedId;
    if (selectedId == null) return;
    _editor.deleteSelection();
    setState(() => _selectedId = null);
  }

  void _bringToFront() {
    final selectedId = _selectedId;
    if (selectedId == null) return;
    _editor.bringToFront();
  }

  void _undo() => unawaited(_editor.undo());

  void _redo() => unawaited(_editor.redo());

  void _duplicateSelected() => _editor.duplicateSelection();

  void _sendToBack() => _editor.sendToBack();

  void _toggleSelectedLock() {
    final block = _editor.primaryNode;
    if (block != null) _editor.setLocked(!block.locked);
  }

  KeyEventResult _handleEditorKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent || _textEditingId != null || _titleFocused) {
      return KeyEventResult.ignored;
    }
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final command =
        pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight) ||
        pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight);
    final shift =
        pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight);
    final nudge = shift ? 10.0 : 1.0;
    if (command) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.keyZ:
          if (shift) {
            _redo();
          } else {
            _undo();
          }
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyY:
          _redo();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyC:
          _editor.copySelection();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyX:
          _editor.cutSelection();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyV:
          _editor.paste();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyD:
          _duplicateSelected();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyA:
          _editor.selectAll();
          return KeyEventResult.handled;
      }
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace:
        _deleteSelected();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _editor.nudge(Offset(-nudge, 0));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _editor.nudge(Offset(nudge, 0));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _editor.nudge(Offset(0, -nudge));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _editor.nudge(Offset(0, nudge));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        _editor.select(null);
        setState(() {
          _selectedId = null;
          _textEditingId = null;
        });
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _showLayers() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: PaperPage.paper,
      showDragHandle: true,
      builder: (context) => EditorLayersView(
        nodes: _nodes,
        selectedId: _selectedId,
        onSelect: (id) {
          _editor.select(id);
          setState(() => _selectedId = id);
        },
        onToggleHidden: (id) {
          _editor.select(id);
          final node = _editor.document.nodeById(id);
          if (node != null) _editor.setHidden(node.visible);
        },
        onToggleLocked: (id) {
          _editor.select(id);
          final node = _editor.document.nodeById(id);
          if (node != null) _editor.setLocked(!node.locked);
        },
        onReorder: _editor.reorderLayer,
        onMoveForward: (id) {
          _editor.select(id);
          _editor.moveLayerForward();
        },
        onMoveBackward: (id) {
          _editor.select(id);
          _editor.moveLayerBackward();
        },
        onRename: (id, name) async => _editor.renameLayer(id, name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      onKeyEvent: _handleEditorKey,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Stack(
            children: [
              EntryEditorSurface(
                onScaleChanged: (scale) {
                  if (!mounted || (scale - _cameraScale).abs() < 0.001) {
                    return;
                  }
                  setState(() => _cameraScale = scale);
                },
                onViewportChanged: (snapshot) {
                  if (!mounted ||
                      snapshot.visibleCanvasRect == _visibleCanvasRect) {
                    return;
                  }
                  setState(() {
                    _cameraScale = snapshot.scale;
                    _visibleCanvasRect = snapshot.visibleCanvasRect;
                  });
                },
                canvasSize: _workspaceSize,
                pageRect: Rect.fromLTWH(
                  _pageFramePosition.dx,
                  _pageFramePosition.dy,
                  PageViewport.pageSize.width,
                  PageViewport.pageSize.height,
                ),
                controlsBottomInset: _editing ? 88 : 12,
                controlsVisible: widget.controlsVisible,
                gesturesEnabled:
                    !_resizeActive &&
                    !_drawMode &&
                    (!(_editing && _editor.hasSelection) ||
                        kIsWeb ||
                        defaultTargetPlatform == TargetPlatform.windows),
                panEnabled: !_selectMode,
                initialView: _document.view,
                onViewChanged: _handleViewChanged,
                child: RepaintBoundary(
                  key: _pageCaptureKey,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: PaperPage(child: const SizedBox.expand()),
                      ),
                      Positioned.fill(
                        child: EditorCanvasView(
                          workspaceSize: _workspaceSize,
                          worldOrigin: _worldOrigin,
                          // The canvas renders the immutable document
                          // projection. Gesture updates are emitted as node
                          // intents and committed by the controller.
                          nodes: _editor.renderNodes,
                          board: _editor.board,
                          cameraScale: _cameraScale,
                          visibleCanvasRect: _visibleCanvasRect,
                          editing: _editing,
                          selectedId: _selectedId,
                          selectedIds: _editor.selection,
                          textEditingId: _textEditingId,
                          onResizeActiveChanged: (active) {
                            if (_resizeActive == active || !mounted) return;
                            setState(() => _resizeActive = active);
                          },
                          onSelect: (id) {
                            if (id == null) {
                              FocusScope.of(context).unfocus();
                              _editor.select(null);
                              setState(() {
                                _titleFocused = false;
                                _textEditingId = null;
                              });
                              return;
                            }
                            final keys =
                                HardwareKeyboard.instance.logicalKeysPressed;
                            final additive =
                                keys.contains(LogicalKeyboardKey.shiftLeft) ||
                                keys.contains(LogicalKeyboardKey.shiftRight);
                            _editor.select(id, additive: additive);
                            setState(() {
                              _titleFocused = false;
                              _selectedId = id;
                              _textEditingId = null;
                            });
                          },
                          onEditText: _beginTextEditing,
                          onEditImageId: (id) {
                            _editor.select(id);
                            setState(() => _selectedId = id);
                          },
                          onTransformChanged: (id, transform) =>
                              _editor.replaceNodeWorldTransform(id, transform),
                          onTextChanged: _editor.replaceText,
                          onInteractionStart: () =>
                              _editor.beginTransformTransaction('Transform'),
                          onInteractionEnd: () {
                            _editor.snapSelection();
                            unawaited(_editor.commitTransaction());
                          },
                          onMoveSelection: (delta) =>
                              _editor.moveSelection(delta, snap: true),
                          onRotateSelection: _editor.rotateSelection,
                          onTouchRotateSelection: (blockIds, pivot, delta) =>
                              _editor.rotateBlocksAround(
                                blockIds,
                                pivot,
                                delta,
                              ),
                          selectMode: _selectMode,
                          drawMode: _drawMode,
                          inkColorValue: _inkColorValue,
                          inkWidth: _inkWidth,
                          inkOpacity: _inkOpacity,
                          inkStrokeType: _inkStrokeType,
                          onLassoSelected: (ids) {
                            _editor.selectMany(ids);
                            setState(() {
                              _selectedId = ids.isEmpty ? null : ids.last;
                              _textEditingId = null;
                            });
                          },
                          onInkNodeCreated: (node) {
                            _editor.addNode(node);
                            setState(() => _selectedId = node.id);
                          },
                          imageBytes: _editor.readAsset,
                          imageProvider: _imageProvider,
                          onOpenImage: _openImage,
                          onOpenImageId: (id) {
                            final node = _editor.document.nodeById(id);
                            if (node != null) unawaited(_openImage(node));
                          },
                        ),
                      ),
                      Positioned(
                        left: _headerPosition.dx,
                        top: _headerPosition.dy,
                        width: PageViewport.pageSize.width,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(28, 18, 28, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _editing
                                  ? TextField(
                                      key: const ValueKey('entry-title'),
                                      controller: _titleController,
                                      focusNode: _titleFocusNode,
                                      maxLines: 1,
                                      onTap: () {
                                        setState(() {
                                          _titleFocused = true;
                                          _textEditingId = null;
                                        });
                                      },
                                      onChanged: (title) =>
                                          unawaited(_editor.updateTitle(title)),
                                      style: _titleStyle(context),
                                      textAlign: TextAlign.center,
                                      decoration: const InputDecoration(
                                        hintText: 'Untitled page',
                                        border: InputBorder.none,
                                        isDense: true,
                                      ),
                                    )
                                  : Text(
                                      _document.title.isEmpty
                                          ? 'Untitled page'
                                          : _document.title,
                                      style: _titleStyle(context),
                                      textAlign: TextAlign.center,
                                    ),
                              const SizedBox(height: 4),
                              Text(
                                DateFormat.yMMMMd().format(_document.createdAt),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: Colors.black54),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_samplingColor)
                Positioned.fill(
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.18),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (details) => unawaited(
                              _completeColorSample(details.globalPosition),
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                        Align(
                          alignment: Alignment.topCenter,
                          child: SafeArea(
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.colorize, size: 18),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Tap the page to sample a color',
                                    ),
                                    TextButton(
                                      key: const ValueKey(
                                        'color-sample-cancel',
                                      ),
                                      onPressed: _cancelColorSample,
                                      child: const Text('Cancel'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_editing && _document.music != null)
                Positioned(
                  right: 12,
                  top: 12,
                  child: EntryChrome(
                    visible: widget.controlsVisible,
                    child: EditorMusicView(
                      documentId: _document.id,
                      documentTrack: _document.music,
                      controller: widget.musicController,
                      onChange: () => unawaited(_showMusicPicker()),
                      active: widget.active,
                    ),
                  ),
                ),
              if (!_editing)
                Positioned(
                  right: 12,
                  top: 12,
                  child: EntryChrome(
                    visible: widget.controlsVisible,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_document.music != null) ...[
                          EditorMusicView(
                            documentId: _document.id,
                            documentTrack: _document.music,
                            controller: widget.musicController,
                            onChange: () => unawaited(_showMusicPicker()),
                            active: widget.active,
                          ),
                          const SizedBox(height: 8),
                        ],
                        EditorToolbarView(
                          editing: false,
                          hasSelection: false,
                          textEditing: false,
                          textFormattingAvailable: false,
                          textSelection: false,
                          onToggleEditing: () => setState(() {
                            _editing = true;
                            _titleFocused = false;
                            widget.onEditingChanged(true);
                          }),
                          onAddText: _addText,
                          onAddImage: _addImage,
                          onAddSticker: _addSticker,
                          onMore: _showMoreTools,
                          onEditText: () =>
                              setState(() => _textEditingId = _selectedId),
                          onDecreaseFontSize: _activeFontSize > _minFontSize
                              ? () => _changeFontSize(-_fontSizeStep)
                              : null,
                          onIncreaseFontSize: _activeFontSize < _maxFontSize
                              ? () => _changeFontSize(_fontSizeStep)
                              : null,
                          fontFamily: _activeFontFamily,
                          onFontFamilyChanged: _changeFontFamily,
                          textColorValue: _activeTextColor,
                          onTextColorChanged: _changeTextColor,
                          onTextColorEditStart: _beginTextColorEdit,
                          onTextColorEditEnd: _endTextColorEdit,
                          recentColorValues: _editor.recentColorValues,
                          favoriteColorValues: _editor.favoriteColorValues,
                          onRecentColorAdded: _editor.addRecentColor,
                          onFavoriteColorsChanged: _editor.updateFavoriteColors,
                          onSampleColor: _requestColorSample,
                          onInkSettings: _showInkSettings,
                          strokeColorValue: _activeStrokeColorValue,
                          strokeColorAvailable: _strokeColorAvailable,
                          onStrokeColorChanged: _changeStrokeColor,
                          onStrokeColorEditStart: _beginStrokeColorEdit,
                          onStrokeColorEditEnd: _endStrokeColorEdit,
                          inkColorValue: _inkPickerValue,
                          inkColorAvailable:
                              _drawMode &&
                              _activeStrokeBlock?.type != BlockType.shape,
                          onInkColorChanged: _applyInkColorValue,
                          onToggleBold: _toggleBold,
                          onToggleItalic: _toggleItalic,
                          bold: _activeBold,
                          italic: _activeItalic,
                          onDelete: _deleteSelected,
                          onBringToFront: _bringToFront,
                          canUndo: _editor.canUndo,
                          canRedo: _editor.canRedo,
                          onUndo: _undo,
                          onRedo: _redo,
                          onDuplicate: _duplicateSelected,
                          onSendToBack: _sendToBack,
                          onToggleLock: _toggleSelectedLock,
                          locked: _editor.primaryNode?.locked ?? false,
                          onUseAsPreview: null,
                        ),
                      ],
                    ),
                  ),
                ),
              if (_editing)
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: Center(
                    child: EditorToolbarView(
                      editing: true,
                      hasSelection: _selectedId != null,
                      textEditing: _textEditingId != null,
                      textFormattingAvailable:
                          _textFormattingAvailable && !_drawMode,
                      textSelection: _activeTextBlock != null,
                      onToggleEditing: _finishEditing,
                      onAddText: _addText,
                      onAddImage: _addImage,
                      onAddSticker: _addSticker,
                      onMore: _showMoreTools,
                      onEditText: () {
                        final block = _editingTextBlock;
                        if (block != null) {
                          _stopTextEditing();
                        } else {
                          final selected = _editor.primaryNode;
                          if (selected?.type == BlockType.text) {
                            _beginTextEditing(selected!.id);
                          }
                        }
                      },
                      onDecreaseFontSize: _activeFontSize > _minFontSize
                          ? () => _changeFontSize(-_fontSizeStep)
                          : null,
                      onIncreaseFontSize: _activeFontSize < _maxFontSize
                          ? () => _changeFontSize(_fontSizeStep)
                          : null,
                      fontFamily: _activeFontFamily,
                      onFontFamilyChanged: _changeFontFamily,
                      textColorValue: _activeTextColor,
                      onTextColorChanged: _changeTextColor,
                      onTextColorEditStart: _beginTextColorEdit,
                      onTextColorEditEnd: _endTextColorEdit,
                      recentColorValues: _editor.recentColorValues,
                      favoriteColorValues: _editor.favoriteColorValues,
                      onRecentColorAdded: _editor.addRecentColor,
                      onFavoriteColorsChanged: _editor.updateFavoriteColors,
                      onSampleColor: _requestColorSample,
                      onInkSettings: _showInkSettings,
                      strokeColorValue: _activeStrokeColorValue,
                      strokeColorAvailable: _strokeColorAvailable,
                      onStrokeColorChanged: _changeStrokeColor,
                      onStrokeColorEditStart: _beginStrokeColorEdit,
                      onStrokeColorEditEnd: _endStrokeColorEdit,
                      inkColorValue: _inkPickerValue,
                      inkColorAvailable:
                          _drawMode &&
                          _activeStrokeBlock?.type != BlockType.shape,
                      onInkColorChanged: _applyInkColorValue,
                      onToggleBold: _toggleBold,
                      onToggleItalic: _toggleItalic,
                      bold: _activeBold,
                      italic: _activeItalic,
                      onDelete: _deleteSelected,
                      onBringToFront: _bringToFront,
                      canUndo: _editor.canUndo,
                      canRedo: _editor.canRedo,
                      onUndo: _undo,
                      onRedo: _redo,
                      onDuplicate: _duplicateSelected,
                      onSendToBack: _sendToBack,
                      onToggleLock: _toggleSelectedLock,
                      locked: _editor.primaryNode?.locked ?? false,
                      onUseAsPreview: _singleSelectedImage == null
                          ? null
                          : _useSelectedImageAsPreview,
                      previewSelected:
                          _singleSelectedImage?.id ==
                          _document.previewImageNodeId,
                    ),
                  ),
                ),
              if (_editor.saveState != EditorSaveState.saved)
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 12,
                  right: 12,
                  child: ActionChip(
                    avatar: Icon(
                      _editor.saveState == EditorSaveState.failed
                          ? Icons.error_outline
                          : Icons.sync,
                      size: 18,
                    ),
                    label: Text(
                      _editor.saveState == EditorSaveState.failed
                          ? 'Save failed · Retry'
                          : 'Saving…',
                    ),
                    onPressed: _editor.saveState == EditorSaveState.failed
                        ? () => unawaited(_editor.retrySave())
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
