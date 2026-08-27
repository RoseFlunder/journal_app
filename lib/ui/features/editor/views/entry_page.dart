import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../editor/editor_toolbar.dart';
import '../../../../editor/editor_state.dart';
import '../../../../editor/entry_canvas.dart';
import '../../../../models/document.dart';
import '../../../../models/page_music.dart';
import '../../../../models/sticker.dart';
import '../../../../models/view_state.dart';
import '../../../../services/image_source.dart';
import '../../../../services/journal_transfer_service.dart';
import '../view_models/entry_editor_view_model.dart';
import 'entry_editor_surface.dart';
import 'editor_canvas_view.dart';
import 'editor_layers_view.dart';
import 'editor_image_editor_view.dart';
import 'editor_history_view.dart';
import 'editor_templates_view.dart';
import '../../music/view_models/page_music_controller.dart';
import '../../music/views/music_picker_sheet.dart';
import '../../../../widgets/entry_chrome.dart';
import '../../../../widgets/page_viewport.dart';
import '../../../../widgets/paper_page.dart';

/// Shows one immutable [EntryDocument] as a journal page.
///
/// Renders one framed paper page and its freely positioned content blocks.
class EntryPage extends StatefulWidget {
  const EntryPage({
    super.key,
    required this.document,
    required this.editorViewModelFactory,
    this.onDocumentPreviewChanged,
    required this.onEditingChanged,
    required this.active,
    required this.musicController,
    this.controlsVisible = true,
    this.imageSource,
    this.imageProcessor = const ImageProcessor(),
    this.archiveService = const JournalTransferService(),
  });

  final EntryDocument document;
  final EntryEditorViewModelFactory editorViewModelFactory;
  final ValueChanged<EntryDocument>? onDocumentPreviewChanged;
  final ValueChanged<bool> onEditingChanged;
  final bool controlsVisible;
  final bool active;
  final PageMusicController musicController;

  final ImageSourceService? imageSource;
  final ImageProcessor imageProcessor;
  final JournalTransferService archiveService;

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
  int _inkColorValue = 0xFF3B3226;
  double _inkWidth = 1.8;
  double _inkOpacity = 1;
  double _cameraScale = 1;
  bool _titleFocused = false;
  String? _colorTransactionBlockId;
  bool _strokeColorTransactionActive = false;
  bool _samplingColor = false;
  final GlobalKey _pageCaptureKey = GlobalKey();
  Completer<Color?>? _colorSampleCompleter;
  late final TextEditingController _titleController = TextEditingController(
    text: widget.document.title,
  );
  late final FocusNode _titleFocusNode = FocusNode()
    ..addListener(_handleTitleFocusChanged);
  late final ImageSourceService _imageSource =
      widget.imageSource ?? PlatformImageSource();
  bool _pickingImage = false;
  final Map<String, ImageProvider<Object>> _imageProviders = {};
  final Map<String, ImageProvider<Object>> _stickerProviders = {};
  late EntryEditorViewModel _editor;
  late EntryDocument _document;
  Future<void> Function()? _flushHook;
  String? _lastWorkflowError;

  // Presentation/tool state is owned by the feature view model. These
  // forwarding accessors keep this legacy surface readable while the view is
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
      _editor.selectedDrawableBlocks.any((block) => !block.locked);

  int? get _activeStrokeColorValue {
    final block = _activeStrokeBlock;
    if (block == null) return null;
    return Color(block.strokeColorValue ?? PaperPage.ink.toARGB32())
        .withValues(alpha: block.opacity.clamp(0.0, 1.0).toDouble())
        .toARGB32();
  }

  int get _inkPickerValue =>
      Color(_inkColorValue)
          .withValues(alpha: _inkOpacity.clamp(0.0, 1.0).toDouble())
          .toARGB32();

  bool _isDrawable(CanvasRenderable block) =>
      block.type == BlockType.ink || block.type == BlockType.shape;

  @override
  void initState() {
    super.initState();
    _document = widget.document;
    WidgetsBinding.instance.addObserver(this);
    _editor = widget.editorViewModelFactory(widget.document)
      ..addListener(_handleEditorChanged);
    _flushHook = _editor.flushText;
    _editor.persistence.addFlushHook(_flushHook!);
  }

  @override
  void didUpdateWidget(covariant EntryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document.id != widget.document.id) {
      final oldFlushHook = _flushHook;
      if (oldFlushHook != null) _editor.persistence.removeFlushHook(oldFlushHook);
      _editor
        ..removeListener(_handleEditorChanged)
        ..dispose();
      _document = widget.document;
      _editor = widget.editorViewModelFactory(widget.document)
        ..addListener(_handleEditorChanged);
      _flushHook = _editor.flushText;
      _editor.persistence.addFlushHook(_flushHook!);
    }
    if (widget.active &&
        (!oldWidget.active ||
            oldWidget.document.music != widget.document.music)) {
      unawaited(
        widget.musicController.setActivePage(_document.id, _document.music),
      );
    }
  }

  void _handleEditorChanged() {
    // Keep the app's in-memory entry current for immediate previews and UI
    // consumers, while the controller still batches the Hive write itself.
    _document = _editor.document;
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
    final flushHook = _flushHook;
    if (flushHook != null) {
      _editor.persistence.removeFlushHook(flushHook);
    }
    _editor
      ..removeListener(_handleEditorChanged)
      ..dispose();
    _titleController.dispose();
    _titleFocusNode
      ..removeListener(_handleTitleFocusChanged)
      ..dispose();
    super.dispose();
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
    await _editor.persistence.flush();
    await _editor.createCheckpoint(_document.id);
    await _editor.persistence.flush();
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

  void _publishDocument(EntryDocument next) {
    unawaited(_editor.updateMetadata(next));
  }

  void _handleViewChanged(ViewState view) {
    _publishDocument(
      _document.copyWith(view: view, modifiedAt: DateTime.now()),
    );
  }

  int? get _activeTextColor {
    final block = _activeTextBlock;
    return block?.textColorValue ??
        (_titleFocused ? _document.titleTextColorValue : null);
  }

  void _changeFontFamily(String? fontFamily) {
    final block = _activeTextBlock;
    if (block != null) {
      _editor.beginTransaction('Format text');
      _editor.updateNode(
        block.id,
        (node) => _withNodePayload(node, 'fontFamily', fontFamily),
        label: 'Format text',
      );
      unawaited(_editor.commitTransaction());
    } else if (_titleFocused) {
      _publishDocument(
        _document.copyWith(
          titleFontFamily: fontFamily,
          modifiedAt: DateTime.now(),
        ),
      );
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
      _editor.beginTransaction('Format text');
      _editor.updateNode(
        block.id,
        (node) => _withNodePayload(node, 'fontSize', size),
        label: 'Format text',
      );
      unawaited(_editor.commitTransaction());
    } else {
      _publishDocument(
        _document.copyWith(titleFontSize: size, modifiedAt: DateTime.now()),
      );
    }
    setState(() {});
  }

  void _toggleBold() {
    final block = _activeTextBlock;
    if (block == null && !_titleFocused) return;
    if (block != null) {
      _editor.beginTransaction('Format text');
      _editor.updateNode(
        block.id,
        (node) => _withNodePayload(node, 'bold', !block.bold),
        label: 'Format text',
      );
      unawaited(_editor.commitTransaction());
    } else {
      _publishDocument(
        _document.copyWith(
          titleBold: !_document.titleBold,
          modifiedAt: DateTime.now(),
        ),
      );
    }
    setState(() {});
  }

  void _toggleItalic() {
    final block = _activeTextBlock;
    if (block == null && !_titleFocused) return;
    if (block != null) {
      _editor.beginTransaction('Format text');
      _editor.updateNode(
        block.id,
        (node) => _withNodePayload(node, 'italic', !block.italic),
        label: 'Format text',
      );
      unawaited(_editor.commitTransaction());
    } else {
      _publishDocument(
        _document.copyWith(
          titleItalic: !_document.titleItalic,
          modifiedAt: DateTime.now(),
        ),
      );
    }
    setState(() {});
  }

  void _changeTextColor(int? value) {
    final block = _activeTextBlock;
    if (block != null) {
      _editor.updateNode(
        block.id,
        (node) => _withNodePayload(node, 'textColorValue', value),
        label: 'Format text',
      );
    } else if (_titleFocused) {
      _publishDocument(
        _document.copyWith(
          titleTextColorValue: value,
          modifiedAt: DateTime.now(),
        ),
      );
    }
    setState(() {});
  }

  void _beginTextColorEdit() {
    final block = _activeTextBlock;
    if (block == null) return;
    _colorTransactionBlockId = block.id;
    _editor.beginTransaction('Format text');
  }

  void _endTextColorEdit() {
    if (_colorTransactionBlockId == null) return;
    _colorTransactionBlockId = null;
    unawaited(_editor.commitTransaction());
  }

  void _applyInkColorValue(int? value, {VoidCallback? refreshSheet}) {
    final color = value == null ? PaperPage.ink : Color(value);
    setState(() {
      _inkColorValue = color.withValues(alpha: 1).toARGB32();
      _inkOpacity = value == null ? 1 : color.a;
    });
    refreshSheet?.call();
  }

  void _beginStrokeColorEdit() {
    if (!_strokeColorAvailable) return;
    _strokeColorTransactionActive = true;
    _editor.beginTransaction('Format stroke');
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

  Future<void> _openInkColorPicker(
    BuildContext sheetContext,
    StateSetter setSheetState,
  ) async {
    final originalColor = _inkColorValue;
    final originalOpacity = _inkOpacity;
    final pickerValue = Color(originalColor)
        .withValues(alpha: originalOpacity)
        .toARGB32();
    final result = await showVisualColorPicker(
      sheetContext,
      initialValue: pickerValue,
      dialogTitle: 'Ink color',
      recentColorValues:
          _editor.preferenceRepository.recentColorValues,
      favoriteColorValues:
          _editor.preferenceRepository.favoriteColorValues,
      onPreview: (value) =>
          _applyInkColorValue(value, refreshSheet: () => setSheetState(() {})),
      onFavoriteColorsChanged: _updateFavoriteColors,
      onSampleColor: () => _sampleFromInkSettings(sheetContext),
    );
    if (!mounted) return;
    if (result?.isSample == true) {
      if (!sheetContext.mounted) return;
      final sampled = await _sampleFromInkSettings(sheetContext);
      if (sampled == null) {
        setState(() {
          _inkColorValue = originalColor;
          _inkOpacity = originalOpacity;
        });
      } else {
        final value = sampled.toARGB32();
        _applyInkColorValue(value);
        _addRecentColor(value);
      }
      return;
    }
    if (result == null) {
      setState(() {
        _inkColorValue = originalColor;
        _inkOpacity = originalOpacity;
      });
      return;
    }
    _applyInkColorValue(result.value, refreshSheet: () => setSheetState(() {}));
    if (result.value != null) _addRecentColor(result.value!);
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

  void _addRecentColor(int value) {
    final recent = [
      value,
      ..._editor.preferenceRepository.recentColorValues.where(
        (item) => item != value,
      ),
    ].take(8).toList(growable: false);
    unawaited(
      _editor.preferenceRepository.updateColorPreferences(
        recent: recent,
      ),
    );
  }

  void _updateFavoriteColors(Set<int> values) {
    unawaited(
      _editor.preferenceRepository.updateColorPreferences(
        favorites: values,
      ),
    );
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

  Future<void> _addShape() async {
    const shapes = <({String value, String label, IconData icon})>[
      (value: 'rectangle', label: 'Rectangle', icon: Icons.rectangle_outlined),
      (value: 'ellipse', label: 'Ellipse', icon: Icons.circle_outlined),
      (value: 'line', label: 'Line', icon: Icons.horizontal_rule),
      (value: 'arrow', label: 'Arrow', icon: Icons.arrow_right_alt),
    ];
    final shape = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: PaperPage.paper,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              leading: Icon(Icons.category_outlined),
              title: Text('Add shape'),
            ),
            for (final option in shapes)
              ListTile(
                leading: Icon(option.icon),
                title: Text(option.label),
                onTap: () => Navigator.pop(context, option.value),
              ),
          ],
        ),
      ),
    );
    if (!mounted || shape == null) return;
    final node = CanvasNode(
      id: _uuid.v4(),
      type: BlockType.shape,
      transform: Transform2D(
        x: -10,
        y: 28 + (_nodes.length * 7) % 70,
        width: shape == 'line' || shape == 'arrow' ? 42 : 32,
        height: shape == 'line' || shape == 'arrow' ? 18 : 24,
      ),
      opacity: _inkOpacity,
      accessibilityLabel: shape[0].toUpperCase() + shape.substring(1),
      payload: {
        'shape': shape,
        'strokeColorValue': _inkColorValue,
        if (shape == 'rectangle' || shape == 'ellipse')
          'fillColorValue': const Color(0x33C97068).toARGB32(),
        'strokeWidth': 1.5,
      },
    );
    _editor.addNode(node);
    setState(() => _selectedId = node.id);
  }

  Future<void> _addImage() async {
    if (_pickingImage) return;
    setState(() => _pickingImage = true);
    try {
      final picked = await _imageSource.pickImage(context);
      if (!mounted || picked == null) return;
      final stored = await _editor.insertImageAsset(
        ownerId: _document.id,
        picked: picked,
        processor: widget.imageProcessor,
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
    final bytes = _editor.readAsset(assetId);
    if (bytes == null) return null;
    return _imageProviders.putIfAbsent(assetId, () => MemoryImage(bytes));
  }

  void _showImageError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openImage(CanvasRenderable block) async {
    final assetId = block.assetId;
    final bytes = assetId == null
        ? null
        : _editor.readAsset(assetId);
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

  CanvasNode? _imageSelection() {
    final block = _editor.primaryNode;
    if (block == null ||
        (block.type != BlockType.image && block.type != BlockType.sticker)) {
      return null;
    }
    return _editor.primaryNode;
  }

  void _commitImageEdit(
    String blockId,
    CanvasNode Function(CanvasNode node) update, {
    String label = 'Edit image',
  }) {
    _editor.updateNode(blockId, update, label: label);
    unawaited(_editor.commitTransaction());
  }

  void _previewImageEdit(
    String blockId,
    CanvasNode Function(CanvasNode node) update, {
    String label = 'Edit image',
  }) {
    _editor.updateNode(blockId, update, label: label);
  }

  CanvasNode _withNodePayload(
    CanvasNode node,
    String key,
    Object? value,
  ) {
    final payload = Map<String, dynamic>.from(node.payload);
    if (value == null) {
      payload.remove(key);
    } else {
      payload[key] = value;
    }
    return node.copyWith(payload: payload);
  }

  CanvasNode _withImagePayload(
    CanvasNode node,
    String key,
    Object? value,
  ) =>
      _withNodePayload(node, key, value);

  Future<void> _showImageEditor() async {
    final node = _imageSelection();
    if (node == null) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: PaperPage.paper,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => EditorImageEditorView(
        node: node,
        onCommit: (id, update, label) {
          _editor.updateNode(id, update, label: label);
          unawaited(_editor.commitTransaction());
        },
        onPreview: (id, update, label) =>
            _editor.updateNode(id, update, label: label),
        onBeginTransaction: _editor.beginTransaction,
        onEndTransaction: () => unawaited(_editor.commitTransaction()),
      ),
    );
  }

  // Kept temporarily for downstream embedders that still reference the
  // pre-extraction implementation while the image view rolls out.
  // ignore: unused_element
  Future<void> _showImageEditorLegacy() async {
    final block = _imageSelection();
    if (block == null) return;
    var crop = block.crop;
    var opacity = block.opacity;
    var brightness = block.brightness;
    var contrast = block.contrast;
    var saturation = block.saturation;
    var imageMask = block.imageMask;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: PaperPage.paper,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.62,
            minChildSize: 0.42,
            maxChildSize: 0.9,
            builder: (context, scrollController) => ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                const ListTile(
                  leading: Icon(Icons.tune),
                  title: Text('Edit image'),
                  subtitle: Text('Non-destructive crop and presentation'),
                ),
                const Divider(),
                Text('Crop', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _cropChoice(
                      context,
                      label: 'Original',
                      selected: crop == null,
                      onTap: () {
                        setSheetState(() => crop = null);
                        _commitImageEdit(
                          block.id,
                          (next) => _withImagePayload(next, 'crop', null),
                        );
                      },
                    ),
                    _cropChoice(
                      context,
                      label: 'Square',
                      selected: crop == _squareCrop,
                      onTap: () {
                        setSheetState(() => crop = _squareCrop);
                        _commitImageEdit(
                          block.id,
                          (next) => _withImagePayload(next, 'crop', {
                            'left': _squareCrop.left,
                            'top': _squareCrop.top,
                            'right': _squareCrop.right,
                            'bottom': _squareCrop.bottom,
                          }),
                        );
                      },
                    ),
                    _cropChoice(
                      context,
                      label: 'Portrait',
                      selected: crop == _portraitCrop,
                      onTap: () {
                        setSheetState(() => crop = _portraitCrop);
                        _commitImageEdit(
                          block.id,
                          (next) => _withImagePayload(next, 'crop', {
                            'left': _portraitCrop.left,
                            'top': _portraitCrop.top,
                            'right': _portraitCrop.right,
                            'bottom': _portraitCrop.bottom,
                          }),
                        );
                      },
                    ),
                    _cropChoice(
                      context,
                      label: 'Wide',
                      selected: crop == _wideCrop,
                      onTap: () {
                        setSheetState(() => crop = _wideCrop);
                        _commitImageEdit(
                          block.id,
                          (next) => _withImagePayload(next, 'crop', {
                            'left': _wideCrop.left,
                            'top': _wideCrop.top,
                            'right': _wideCrop.right,
                            'bottom': _wideCrop.bottom,
                          }),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'Opacity ${((opacity * 100).round())}%',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Slider(
                  min: 0.1,
                  max: 1,
                  value: opacity,
                  label: '${(opacity * 100).round()}%',
                  onChangeStart: (_) =>
                      _editor.beginTransaction('Image opacity'),
                  onChanged: (value) {
                    opacity = value;
                    setSheetState(() {});
                    _previewImageEdit(
                      block.id,
                      (next) => next.copyWith(opacity: value),
                      label: 'Image opacity',
                    );
                  },
                  onChangeEnd: (_) => unawaited(_editor.commitTransaction()),
                ),
                _imageAdjustmentSlider(
                  context,
                  label: 'Brightness',
                  value: brightness,
                  min: -1,
                  max: 1,
                  onStart: () => _editor.beginTransaction('Image brightness'),
                  onChanged: (value) {
                    setSheetState(() => brightness = value);
                    _previewImageEdit(
                      block.id,
                      (next) => _withImagePayload(next, 'brightness', value),
                      label: 'Image brightness',
                    );
                  },
                  onEnd: () => unawaited(_editor.commitTransaction()),
                ),
                _imageAdjustmentSlider(
                  context,
                  label: 'Contrast',
                  value: contrast,
                  min: -1,
                  max: 1,
                  onStart: () => _editor.beginTransaction('Image contrast'),
                  onChanged: (value) {
                    setSheetState(() => contrast = value);
                    _previewImageEdit(
                      block.id,
                      (next) => _withImagePayload(next, 'contrast', value),
                      label: 'Image contrast',
                    );
                  },
                  onEnd: () => unawaited(_editor.commitTransaction()),
                ),
                _imageAdjustmentSlider(
                  context,
                  label: 'Saturation',
                  value: saturation,
                  min: 0,
                  max: 2,
                  onStart: () => _editor.beginTransaction('Image saturation'),
                  onChanged: (value) {
                    setSheetState(() => saturation = value);
                    _previewImageEdit(
                      block.id,
                      (next) => _withImagePayload(next, 'saturation', value),
                      label: 'Image saturation',
                    );
                  },
                  onEnd: () => unawaited(_editor.commitTransaction()),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () => _commitImageEdit(
                        block.id,
                        (next) => next.copyWith(
                          transform: next.transform.copyWith(
                            rotation: next.transform.rotation + math.pi / 2,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.rotate_90_degrees_ccw),
                      label: const Text('Rotate 90°'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _commitImageEdit(
                        block.id,
                        (next) => _withImagePayload(
                          next,
                          'flipX',
                          next.payload['flipX'] != true,
                        ),
                      ),
                      icon: const Icon(Icons.flip),
                      label: const Text('Flip horizontal'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _commitImageEdit(
                        block.id,
                        (next) => _withImagePayload(
                          next,
                          'flipY',
                          next.payload['flipY'] != true,
                        ),
                      ),
                      icon: const Icon(Icons.flip_camera_android),
                      label: const Text('Flip vertical'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text('Mask', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'rectangle', label: Text('Square')),
                    ButtonSegment(value: 'rounded', label: Text('Rounded')),
                    ButtonSegment(value: 'circle', label: Text('Circle')),
                  ],
                  selected: {imageMask},
                  onSelectionChanged: (selection) {
                    final nextMask = selection.first;
                    setSheetState(() => imageMask = nextMask);
                    _commitImageEdit(
                      block.id,
                      (next) => _withImagePayload(next, 'imageMask', nextMask),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveTemplate() async {
    final selectedNodes = _editor.selectedNodeGraphSnapshot();
    if (selectedNodes.isEmpty) return;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _TextPromptDialog(
        title: 'Save template',
        label: 'Template name',
      ),
    );
    if (!mounted || name == null || name.trim().isEmpty) return;
    final now = DateTime.now();
    await _editor.saveTemplateSelection(
      name: name.trim(),
      source: _document,
      nodes: selectedNodes,
      createdAt: now,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved template “${name.trim()}”')),
      );
    }
  }

  void _showTemplates() {
    final templates = _editor.templates;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: PaperPage.paper,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => EditorTemplatesView(
        templates: templates,
        onInsert: (template) => _editor.insertTemplate(
          nodes: template.document.nodes,
          offset: Offset(
            PageViewport.modelPageSize.width / 2,
            PageViewport.modelPageSize.height / 2,
          ),
        ),
      ),
    );
  }

  // Kept temporarily while downstream callers transition to
  // [EditorTemplatesView].
  // ignore: unused_element
  void _showTemplatesLegacy() {
    final templates = _editor.templates;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: PaperPage.paper,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.68,
          child: templates.isEmpty
              ? const Center(child: Text('No saved templates yet'))
              : ListView.builder(
                  itemCount: templates.length,
                  itemBuilder: (context, index) {
                    final template = templates[index];
                    return ListTile(
                      leading: const Icon(Icons.dashboard_customize_outlined),
                      title: Text(template.name),
                      subtitle: Text(
                        '${template.document.nodes.length} top-level objects',
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _editor.insertTemplate(
                          nodes: template.document.nodes,
                          offset: Offset(
                            PageViewport.modelPageSize.width / 2,
                            PageViewport.modelPageSize.height / 2,
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _exportArchive() async {
    if (!mounted) return;
    final exported = await _editor.exportArchive(
      documentId: _document.id,
      fileName:
          '${_document.title.trim().isEmpty ? 'journal' : _document.title.trim()}.cozyjournal',
      transfer: widget.archiveService,
    );
    if (mounted && exported) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Journal backup exported')));
    }
  }

  Future<void> _importArchive() async {
    if (!mounted) return;
    try {
      final imported = await _editor.importArchive(widget.archiveService);
      if (!mounted || imported == null) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Journal backup imported as a new page'),
          ),
        );
      }
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not import backup: ${error.message}')),
        );
      }
    }
  }

  static const _squareCrop = Rect.fromLTWH(0.125, 0, 0.75, 1);
  static const _portraitCrop = Rect.fromLTWH(0.22, 0, 0.56, 1);
  static const _wideCrop = Rect.fromLTWH(0, 0.2, 1, 0.6);

  Widget _cropChoice(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onTap(),
  );

  Future<void> _showInkSettings() async {
    final originalColor = _inkColorValue;
    final originalOpacity = _inkOpacity;
    final originalWidth = _inkWidth;
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: PaperPage.paper,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ListTile(
                  leading: Icon(Icons.draw_outlined),
                  title: Text('Ink settings'),
                  subtitle: Text('Color, opacity, and stroke width'),
                ),
                ListTile(
                  key: const ValueKey('ink-color'),
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: Color(_inkColorValue)
                        .withValues(alpha: _inkOpacity),
                    child: const Icon(Icons.brush_outlined),
                  ),
                  title: const Text('Ink color'),
                  subtitle: const Text('Open the visual color picker'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openInkColorPicker(context, setSheetState),
                ),
                const SizedBox(height: 8),
                Text('Width ${_inkWidth.toStringAsFixed(1)}'),
                Slider(
                  min: 0.8,
                  max: 8,
                  value: _inkWidth,
                  onChanged: (value) {
                    setState(() => _inkWidth = value);
                    setSheetState(() {});
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || result == true) return;
    setState(() {
      _inkColorValue = originalColor;
      _inkOpacity = originalOpacity;
      _inkWidth = originalWidth;
    });
  }

  void _showMoreTools() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: PaperPage.paper,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.35,
          maxChildSize: 0.94,
          builder: (context, scrollController) => SafeArea(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                ListTile(
                  leading: const Icon(Icons.undo),
                  title: const Text('Undo'),
                  enabled: _editor.canUndo,
                  onTap: _editor.canUndo
                      ? () {
                          Navigator.pop(context);
                          _undo();
                        }
                      : null,
                ),
                ListTile(
                  leading: const Icon(Icons.redo),
                  title: const Text('Redo'),
                  enabled: _editor.canRedo,
                  onTap: _editor.canRedo
                      ? () {
                          Navigator.pop(context);
                          _redo();
                        }
                      : null,
                ),
                ListTile(
                  leading: const Icon(Icons.category_outlined),
                  title: const Text('Add shape'),
                  subtitle: const Text('Rectangle, ellipse, line, or arrow'),
                  onTap: () {
                    Navigator.pop(context);
                    _addShape();
                  },
                ),
                if (_imageSelection() != null)
                  ListTile(
                    leading: const Icon(Icons.image_outlined),
                    title: const Text('Edit image'),
                    subtitle: const Text('Crop, flip, mask, and opacity'),
                    onTap: () {
                      Navigator.pop(context);
                      _showImageEditor();
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.dashboard_customize_outlined),
                  title: const Text('Save selection as template'),
                  subtitle: const Text('Reuse selected objects locally'),
                  enabled: _editor.hasSelection,
                  onTap: !_editor.hasSelection
                      ? null
                      : () {
                          Navigator.pop(context);
                          _saveTemplate();
                        },
                ),
                ListTile(
                  leading: const Icon(Icons.library_books_outlined),
                  title: const Text('Insert template'),
                  subtitle: const Text(
                    'Add a saved board at the camera center',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showTemplates();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.file_upload_outlined),
                  title: const Text('Export .cozyjournal backup'),
                  onTap: () {
                    Navigator.pop(context);
                    _exportArchive();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('Import .cozyjournal backup'),
                  onTap: () {
                    Navigator.pop(context);
                    _importArchive();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.group_work_outlined),
                  title: const Text('Group selection'),
                  subtitle: const Text('Keep selected objects together'),
                  enabled: _editor.canGroup,
                  onTap: _editor.canGroup
                      ? () {
                          _editor.groupSelection();
                          Navigator.pop(context);
                        }
                      : null,
                ),
                ListTile(
                  leading: const Icon(Icons.group_off_outlined),
                  title: const Text('Ungroup selection'),
                  enabled: _editor.canUngroup,
                  onTap: _editor.canUngroup
                      ? () {
                          _editor.ungroupSelection();
                          Navigator.pop(context);
                        }
                      : null,
                ),
                ListTile(
                  leading: const Icon(Icons.align_horizontal_center_outlined),
                  title: const Text('Align selection'),
                  subtitle: const Text(
                    'Align selected objects to their shared bounds',
                  ),
                  enabled: _editor.selection.length > 1,
                  onTap: _editor.selection.length > 1
                      ? () {
                          Navigator.pop(context);
                          _showAlignment();
                        }
                      : null,
                ),
                ListTile(
                  leading: Icon(
                    _selectMode ? Icons.select_all : Icons.select_all_outlined,
                  ),
                  title: Text(
                    _selectMode ? 'Exit select mode' : 'Select multiple',
                  ),
                  subtitle: const Text(
                    'Drag blank board space to lasso content',
                  ),
                  onTap: () {
                    setState(() => _selectMode = !_selectMode);
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: Icon(_drawMode ? Icons.draw : Icons.draw_outlined),
                  title: Text(_drawMode ? 'Exit draw mode' : 'Draw'),
                  subtitle: const Text('Draw a vector ink stroke on the board'),
                  onTap: () {
                    setState(() {
                      _drawMode = !_drawMode;
                      if (_drawMode) _selectMode = false;
                    });
                    Navigator.pop(context);
                  },
                ),
                if (_drawMode)
                  ListTile(
                    key: const ValueKey('ink-settings'),
                    leading: const Icon(Icons.tune),
                    title: const Text('Ink settings'),
                    subtitle: const Text('Color, width, and opacity'),
                    onTap: () {
                      Navigator.pop(context);
                      _showInkSettings();
                    },
                  ),
                ListTile(
                  key: const ValueKey('page-music-tool'),
                  leading: const Icon(Icons.library_music_outlined),
                  title: Text(
                    _document.music == null
                        ? 'Add page music'
                        : 'Change page music',
                  ),
                  subtitle: const Text(
                    'Stream Creative Commons music from Jamendo',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    unawaited(_showMusicPicker());
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.layers_outlined),
                  title: const Text('Layers'),
                  subtitle: const Text('Reorder, show, hide, and lock content'),
                  onTap: () {
                    Navigator.pop(context);
                    _showLayers();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: const Text('Precise transform'),
                  subtitle: const Text(
                    'Move, resize, rotate, and nudge without dragging',
                  ),
                  enabled: _editor.primaryNode != null,
                  onTap: _editor.primaryNode == null
                      ? null
                      : () {
                          Navigator.pop(context);
                          _showTransformInspector();
                        },
                ),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('History & recovery'),
                  onTap: () {
                    Navigator.pop(context);
                    _showHistory();
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.grid_4x4_outlined),
                  title: const Text('Snap to grid'),
                  value: _editor.board.snapToGrid,
                  onChanged: (value) {
                    _editor.updateBoard(
                      _editor.board.copyWith(snapToGrid: value),
                    );
                    setSheetState(() {});
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.grid_on_outlined),
                  title: const Text('Show grid'),
                  value: _editor.board.gridVisible,
                  onChanged: (value) {
                    _editor.updateBoard(
                      _editor.board.copyWith(gridVisible: value),
                    );
                    setSheetState(() {});
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showMusicPicker() async {
    await widget.musicController.stopAndReset();
    if (!mounted) return;
    final result = await showModalBottomSheet<MusicPickerResult>(
      context: context,
      backgroundColor: PaperPage.paper,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => MusicPickerSheet(
        catalog: _editor.musicCatalog,
        audioPlaybackFactory: _editor.audioPlaybackFactory,
        current: _document.music,
      ),
    );
    if (!mounted || result == null) return;
    final track = result.remove ? null : result.track;
    final next = _document.copyWith(
      music: track,
      modifiedAt: DateTime.now(),
    );
    _publishDocument(next);
    await widget.musicController.setActivePage(
      widget.active ? _document.id : null,
      widget.active ? track : null,
    );
    if (mounted) setState(() {});
  }

  void _showAlignment() {
    const choices = <({String label, IconData icon, Alignment alignment})>[
      (
        label: 'Align left',
        icon: Icons.format_align_left,
        alignment: Alignment.centerLeft,
      ),
      (
        label: 'Align center',
        icon: Icons.format_align_center,
        alignment: Alignment.center,
      ),
      (
        label: 'Align right',
        icon: Icons.format_align_right,
        alignment: Alignment.centerRight,
      ),
      (
        label: 'Align top',
        icon: Icons.vertical_align_top,
        alignment: Alignment.topCenter,
      ),
      (
        label: 'Align middle',
        icon: Icons.vertical_align_center,
        alignment: Alignment.center,
      ),
      (
        label: 'Align bottom',
        icon: Icons.vertical_align_bottom,
        alignment: Alignment.bottomCenter,
      ),
    ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: PaperPage.paper,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              leading: Icon(Icons.align_horizontal_center_outlined),
              title: Text('Align selection'),
            ),
            for (final choice in choices)
              ListTile(
                leading: Icon(choice.icon),
                title: Text(choice.label),
                onTap: () {
                  _editor.align(choice.alignment);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
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

  void _showTransformInspector() {
    final block = _editor.primaryNode;
    if (block == null) return;
    final x = TextEditingController(text: block.x.toStringAsFixed(1));
    final y = TextEditingController(text: block.y.toStringAsFixed(1));
    final width = TextEditingController(text: block.w.toStringAsFixed(1));
    final height = TextEditingController(text: block.h.toStringAsFixed(1));
    final rotation = TextEditingController(
      text: (block.rotation * 180 / math.pi).toStringAsFixed(1),
    );
    final opacity = TextEditingController(
      text: (block.opacity * 100).round().toString(),
    );
    Future<void> apply() async {
      final nextX = double.tryParse(x.text);
      final nextY = double.tryParse(y.text);
      final nextWidth = double.tryParse(width.text);
      final nextHeight = double.tryParse(height.text);
      final degrees = double.tryParse(rotation.text);
      final nextOpacity = double.tryParse(opacity.text);
      if ([
        nextX,
        nextY,
        nextWidth,
        nextHeight,
        degrees,
        nextOpacity,
      ].any((value) => value == null)) {
        return;
      }
      _editor.beginTransaction('Precise transform');
      _editor.replaceNodeWorldTransform(
        block.id,
        Transform2D(
          x: nextX!,
          y: nextY!,
          width: math.max(EntryCanvas.minWidth, nextWidth!),
          height: math.max(EntryCanvas.minHeight, nextHeight!),
          rotation: degrees! * math.pi / 180,
        ),
        label: 'Precise transform',
      );
      _editor.updateNode(
        block.id,
        (node) => node.copyWith(
          opacity: (nextOpacity! / 100).clamp(0.0, 1.0).toDouble(),
        ),
        label: 'Precise transform',
      );
      await _editor.commitTransaction();
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PaperPage.paper,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Precise transform', style: TextStyle(fontSize: 22)),
              if (block.locked)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Unlock this block before editing its transform.',
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _numberField('X', x)),
                  const SizedBox(width: 12),
                  Expanded(child: _numberField('Y', y)),
                ],
              ),
              Row(
                children: [
                  Expanded(child: _numberField('Width', width)),
                  const SizedBox(width: 12),
                  Expanded(child: _numberField('Height', height)),
                ],
              ),
              Row(
                children: [
                  Expanded(child: _numberField('Rotation °', rotation)),
                  const SizedBox(width: 12),
                  Expanded(child: _numberField('Opacity %', opacity)),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                children: [
                  _nudgeButton('←', const Offset(-1, 0)),
                  _nudgeButton('↑', const Offset(0, -1)),
                  _nudgeButton('↓', const Offset(0, 1)),
                  _nudgeButton('→', const Offset(1, 0)),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: block.locked
                      ? null
                      : () async {
                          await apply();
                          if (context.mounted) Navigator.pop(context);
                        },
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      x.dispose();
      y.dispose();
      width.dispose();
      height.dispose();
      rotation.dispose();
      opacity.dispose();
    });
  }

  Widget _numberField(String label, TextEditingController controller) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          decoration: InputDecoration(labelText: label),
        ),
      );

  Widget _imageAdjustmentSlider(
    BuildContext context, {
    required String label,
    required double value,
    required double min,
    required double max,
    required VoidCallback onStart,
    required ValueChanged<double> onChanged,
    required VoidCallback onEnd,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.titleMedium),
      Slider(
        min: min,
        max: max,
        value: value.clamp(min, max).toDouble(),
        onChangeStart: (_) => onStart(),
        onChanged: onChanged,
        onChangeEnd: (_) => onEnd(),
      ),
    ],
  );

  Widget _nudgeButton(String label, Offset delta) => Semantics(
    button: true,
    label: 'Nudge $label',
    child: OutlinedButton(
      onPressed: () => _editor.nudge(delta),
      child: Text(label),
    ),
  );

  void _showHistory() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: PaperPage.paper,
      showDragHandle: true,
      builder: (context) => EditorHistoryView(
        checkpoints: _editor.checkpointsFor(_document.id),
        onCreateCheckpoint: () => _editor.createCheckpoint(_document.id),
        onRestore: (checkpoint) async {
          final restored = await _editor.restoreCheckpoint(
            checkpointId: checkpoint.id,
            documentId: _document.id,
          );
          if (restored != null) _editor.replaceDocumentModel(restored);
        },
      ),
    );
  }

  // Kept temporarily while downstream callers transition to
  // [EditorHistoryView].
  // ignore: unused_element
  void _showHistoryLegacy() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: PaperPage.paper,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final checkpoints = _editor.checkpointsFor(_document.id);
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.62,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.add_task_outlined),
                    title: const Text('Create recovery checkpoint'),
                    onTap: () async {
                      await _editor.createCheckpoint(_document.id);
                      setModalState(() {});
                    },
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: checkpoints.isEmpty
                        ? const Center(
                            child: Text('No recovery checkpoints yet'),
                          )
                        : ListView.builder(
                            itemCount: checkpoints.length,
                            itemBuilder: (context, index) {
                              final checkpoint = checkpoints[index];
                              return ListTile(
                                leading: const Icon(Icons.restore),
                                title: Text(
                                  DateFormat.yMMMd().add_jm().format(
                                    checkpoint.createdAt,
                                  ),
                                ),
                                subtitle: const Text(
                                  'Restore this local version',
                                ),
                                onTap: () async {
                                  final restored = await _editor.restoreCheckpoint(
                                        checkpointId: checkpoint.id,
                                        documentId: _document.id,
                                      );
                                  if (restored == null) return;
                                  _editor.replaceDocumentModel(restored);
                                  if (context.mounted) Navigator.pop(context);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
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

  Widget _buildMusicChip() => ListenableBuilder(
    listenable: widget.musicController,
    builder: (context, _) {
      final controller = widget.musicController;
      final track = controller.pageId == _document.id
          ? controller.track ?? _document.music
          : _document.music;
      if (track == null) return const SizedBox.shrink();
      final loading = widget.active && controller.isLoading;
      final playing = widget.active && controller.isPlaying;
      final failed = widget.active && controller.error != null;
      return Material(
        color: PaperPage.paper,
        elevation: 2,
        borderRadius: BorderRadius.circular(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: const ValueKey('page-music-play-pause'),
                tooltip: failed
                    ? 'Retry page music'
                    : playing
                    ? 'Pause page music'
                    : 'Play page music',
                onPressed: !widget.active || loading
                    ? null
                    : () async {
                        await controller.toggle();
                        if (!context.mounted || controller.error == null) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(controller.error!)),
                        );
                      },
                icon: loading
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        failed
                            ? Icons.refresh
                            : playing
                            ? Icons.pause
                            : Icons.play_arrow,
                      ),
              ),
              Flexible(
                child: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              IconButton(
                tooltip: 'Page music details',
                onPressed: () => _showMusicDetails(track),
                icon: const Icon(Icons.info_outline, size: 20),
              ),
            ],
          ),
        ),
      );
    },
  );

  Future<void> _showMusicDetails(PageMusicTrack track) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(track.title),
        content: Text(
          track.isLegacy
              ? 'This page contains a legacy local music reference. Replace or remove it from More tools.'
              : '${track.artist}\n\nStreamed from Jamendo under the linked Creative Commons license.',
        ),
        actions: [
          if (track.licenseUrl.isNotEmpty)
            TextButton(
              onPressed: () => launchUrl(Uri.parse(track.licenseUrl)),
              child: const Text('License'),
            ),
          if (track.trackPageUrl.isNotEmpty)
            TextButton(
              onPressed: () => launchUrl(Uri.parse(track.trackPageUrl)),
              child: const Text('Open on Jamendo'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
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
                            _showImageEditor();
                          },
                          onTransformChanged: (id, transform) =>
                              _editor.replaceNodeWorldTransform(id, transform),
                          onTextChanged: _editor.replaceText,
                          onInteractionStart: () =>
                              _editor.beginTransaction('Transform'),
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
                          imageBytes:
                              _editor.readAsset,
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
                                      onChanged: (title) => _publishDocument(
                                        _document.copyWith(
                                          title: title,
                                          modifiedAt: DateTime.now(),
                                        ),
                                      ),
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
                    child: _buildMusicChip(),
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
                          _buildMusicChip(),
                          const SizedBox(height: 8),
                        ],
                        EditorToolbar(
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
                          recentColorValues: _editor
                              .preferenceRepository
                              .recentColorValues,
                          favoriteColorValues: _editor
                              .preferenceRepository
                              .favoriteColorValues,
                          onRecentColorAdded: _addRecentColor,
                          onFavoriteColorsChanged: _updateFavoriteColors,
                          onSampleColor: _requestColorSample,
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
                    child: EditorToolbar(
                      editing: true,
                      hasSelection: _selectedId != null,
                      textEditing: _textEditingId != null,
                      textFormattingAvailable: _textFormattingAvailable,
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
                      recentColorValues: _editor
                          .preferenceRepository
                          .recentColorValues,
                      favoriteColorValues: _editor
                          .preferenceRepository
                          .favoriteColorValues,
                      onRecentColorAdded: _addRecentColor,
                      onFavoriteColorsChanged: _updateFavoriteColors,
                      onSampleColor: _requestColorSample,
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
