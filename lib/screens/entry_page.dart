import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../editor/editor_toolbar.dart';
import '../editor/editor_controller.dart';
import '../editor/entry_canvas.dart';
import '../models/document.dart';
import '../models/entry.dart';
import '../models/sticker.dart';
import '../models/template.dart';
import '../services/image_source.dart';
import '../services/journal_archive.dart';
import '../services/journal_store.dart';
import '../widgets/entry_chrome.dart';
import '../widgets/page_viewport.dart';
import '../widgets/paper_page.dart';

/// Shows one [Entry] as a journal page.
///
/// Renders one framed paper page and its freely positioned content blocks.
class EntryPage extends StatefulWidget {
  const EntryPage({
    super.key,
    required this.entry,
    required this.store,
    required this.onViewChanged,
    required this.onDocumentChanged,
    required this.onTitleChanged,
    required this.onTitleStyleChanged,
    required this.onTitleFontFamilyChanged,
    required this.onTitleTextColorChanged,
    required this.onEditingChanged,
    this.controlsVisible = true,
    this.imageSource,
    this.imageProcessor = const ImageProcessor(),
  });

  final Entry entry;
  final JournalStore store;
  final ValueChanged<ViewState> onViewChanged;
  final Future<void> Function(List<ContentBlock>, BoardSettings)
  onDocumentChanged;
  final ValueChanged<String> onTitleChanged;
  final void Function(double fontSize, bool bold, bool italic)
  onTitleStyleChanged;
  final ValueChanged<String?> onTitleFontFamilyChanged;
  final ValueChanged<int?> onTitleTextColorChanged;
  final ValueChanged<bool> onEditingChanged;
  final bool controlsVisible;

  final ImageSourceService? imageSource;
  final ImageProcessor imageProcessor;

  @override
  State<EntryPage> createState() => _EntryPageState();
}

class _RenameLayerDialog extends StatefulWidget {
  const _RenameLayerDialog({
    this.initial = '',
    this.title = 'Rename layer',
    this.label = 'Layer name',
  });

  final String initial;
  final String title;
  final String label;

  @override
  State<_RenameLayerDialog> createState() => _RenameLayerDialogState();
}

class _RenameLayerDialogState extends State<_RenameLayerDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

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
        child: const Text('Rename'),
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
  bool _editing = false;
  bool _resizeActive = false;
  bool _selectMode = false;
  bool _drawMode = false;
  int _inkColorValue = 0xFF3B3226;
  double _inkWidth = 1.8;
  double _inkOpacity = 1;
  double _cameraScale = 1;
  bool _titleFocused = false;
  String? _selectedId;
  String? _textEditingId;
  String? _colorTransactionBlockId;
  bool _samplingColor = false;
  final GlobalKey _pageCaptureKey = GlobalKey();
  Completer<Color?>? _colorSampleCompleter;
  late final TextEditingController _titleController = TextEditingController(
    text: widget.entry.title,
  );
  late final FocusNode _titleFocusNode = FocusNode()
    ..addListener(_handleTitleFocusChanged);
  late final ImageSourceService _imageSource =
      widget.imageSource ?? PlatformImageSource();
  bool _pickingImage = false;
  final Map<String, ImageProvider<Object>> _imageProviders = {};
  final Map<String, ImageProvider<Object>> _stickerProviders = {};
  late final EditorController _editor;
  Future<void> Function()? _flushHook;

  List<ContentBlock> get _blocks => _editor.blocks;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _editor = EditorController(
      blocks: widget.entry.blocks,
      initialBoard: widget.entry.board,
      persistDocument: (blocks, board) async {
        widget.entry
          ..blocks = blocks
          ..board = board;
        await widget.onDocumentChanged(blocks, board);
        widget.store.scheduleCheckpoint(widget.entry.id);
      },
    )..addListener(_handleEditorChanged);
    _flushHook = _editor.flushText;
    widget.store.addFlushHook(_flushHook!);
  }

  void _handleEditorChanged() {
    // Keep the app's in-memory entry current for immediate previews and UI
    // consumers, while the controller still batches the Hive write itself.
    widget.entry
      ..blocks = _editor.snapshotBlocks()
      ..board = _editor.board;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _colorSampleCompleter?.complete(null);
    _colorSampleCompleter = null;
    WidgetsBinding.instance.removeObserver(this);
    final flushHook = _flushHook;
    if (flushHook != null) widget.store.removeFlushHook(flushHook);
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
    }
  }

  Future<void> _flushLifecycle() async {
    await widget.store.flush();
    await widget.store.createCheckpoint(widget.entry.id);
    await widget.store.flush();
  }

  void _handleTitleFocusChanged() {
    if (!mounted || !_titleFocusNode.hasFocus || _titleFocused) return;
    setState(() {
      _titleFocused = true;
      _textEditingId = null;
    });
  }

  void _changeBlock(ContentBlock block) {
    _editor.replaceBlockSnapshot(block, label: 'Edit ${block.type.name}');
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

  ContentBlock? get _editingTextBlock {
    final id = _textEditingId;
    if (id == null) return null;
    for (final block in _blocks) {
      if (block.id == id && block.type == BlockType.text) return block;
    }
    return null;
  }

  ContentBlock? get _activeTextBlock {
    if (_titleFocused) return null;
    final editing = _editingTextBlock;
    if (editing != null) return editing;
    final selectedId = _selectedId;
    if (selectedId == null) return null;
    for (final block in _blocks) {
      if (block.id == selectedId && block.type == BlockType.text) return block;
    }
    return null;
  }

  String? get _activeFontFamily {
    final block = _activeTextBlock;
    return block?.fontFamily ??
        (_titleFocused ? widget.entry.titleFontFamily : null);
  }

  bool get _textFormattingAvailable =>
      _titleFocused || _activeTextBlock != null;

  int? get _activeTextColor {
    final block = _activeTextBlock;
    return block?.textColorValue ??
        (_titleFocused ? widget.entry.titleTextColorValue : null);
  }

  void _changeFontFamily(String? fontFamily) {
    final block = _activeTextBlock;
    if (block != null) {
      _editor.beginTransaction('Format text');
      _editor.updateBlock(block.id, (target) => target.fontFamily = fontFamily);
      unawaited(_editor.commitTransaction());
    } else if (_titleFocused) {
      widget.onTitleFontFamilyChanged(fontFamily);
    }
    setState(() {});
  }

  double get _activeFontSize =>
      _activeTextBlock?.fontSize ?? widget.entry.titleFontSize;

  bool get _activeBold => _activeTextBlock?.bold ?? widget.entry.titleBold;

  bool get _activeItalic =>
      _activeTextBlock?.italic ?? widget.entry.titleItalic;

  void _changeFontSize(double delta) {
    final block = _activeTextBlock;
    if (block == null && !_titleFocused) return;
    final size = (_activeFontSize + delta)
        .clamp(_minFontSize, _maxFontSize)
        .toDouble();
    if (block != null) {
      _editor.beginTransaction('Format text');
      _editor.updateBlock(block.id, (target) => target.fontSize = size);
      unawaited(_editor.commitTransaction());
    } else {
      widget.onTitleStyleChanged(
        size,
        widget.entry.titleBold,
        widget.entry.titleItalic,
      );
    }
    setState(() {});
  }

  void _toggleBold() {
    final block = _activeTextBlock;
    if (block == null && !_titleFocused) return;
    if (block != null) {
      _editor.beginTransaction('Format text');
      _editor.updateBlock(block.id, (target) => target.bold = !target.bold);
      unawaited(_editor.commitTransaction());
    } else {
      widget.onTitleStyleChanged(
        widget.entry.titleFontSize,
        !widget.entry.titleBold,
        widget.entry.titleItalic,
      );
    }
    setState(() {});
  }

  void _toggleItalic() {
    final block = _activeTextBlock;
    if (block == null && !_titleFocused) return;
    if (block != null) {
      _editor.beginTransaction('Format text');
      _editor.updateBlock(block.id, (target) => target.italic = !target.italic);
      unawaited(_editor.commitTransaction());
    } else {
      widget.onTitleStyleChanged(
        widget.entry.titleFontSize,
        widget.entry.titleBold,
        !widget.entry.titleItalic,
      );
    }
    setState(() {});
  }

  void _changeTextColor(int? value) {
    final block = _activeTextBlock;
    if (block != null) {
      _editor.updateBlock(block.id, (target) => target.textColorValue = value);
    } else if (_titleFocused) {
      widget.onTitleTextColorChanged(value);
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
      ...widget.store.recentColorValues.where((item) => item != value),
    ].take(8).toList(growable: false);
    unawaited(widget.store.updateColorPreferences(recent: recent));
  }

  void _updateFavoriteColors(Set<int> values) {
    unawaited(widget.store.updateColorPreferences(favorites: values));
  }

  TextStyle _titleStyle(BuildContext context) =>
      (Theme.of(context).textTheme.headlineSmall ?? const TextStyle()).copyWith(
        fontSize: widget.entry.titleFontSize,
        fontFamily: widget.entry.titleFontFamily,
        color: widget.entry.titleTextColorValue == null
            ? PaperPage.ink
            : Color(widget.entry.titleTextColorValue!),
        fontWeight: widget.entry.titleBold
            ? FontWeight.bold
            : FontWeight.normal,
        fontStyle: widget.entry.titleItalic
            ? FontStyle.italic
            : FontStyle.normal,
      );

  void _addText() {
    final block = ContentBlock(
      id: _uuid.v4(),
      type: BlockType.text,
      text: '',
      x: -20,
      y: 12 + (_blocks.length * 8) % 80,
      w: 30,
      h: 11,
      fontSize: 26,
    );
    _editor.add(block);
    setState(() {
      _titleFocused = false;
      _selectedId = block.id;
      _textEditingId = block.id;
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
    final block = ContentBlock(
      id: _uuid.v4(),
      type: BlockType.shape,
      name: shape[0].toUpperCase() + shape.substring(1),
      shape: shape,
      x: -10,
      y: 28 + (_blocks.length * 7) % 70,
      w: shape == 'line' || shape == 'arrow' ? 42 : 32,
      h: shape == 'line' || shape == 'arrow' ? 18 : 24,
      strokeColorValue: PaperPage.ink.toARGB32(),
      fillColorValue: shape == 'rectangle' || shape == 'ellipse'
          ? const Color(0x33C97068).toARGB32()
          : null,
      strokeWidth: 1.5,
    );
    _editor.add(block);
    setState(() => _selectedId = block.id);
  }

  Future<void> _addImage() async {
    if (_pickingImage) return;
    setState(() => _pickingImage = true);
    try {
      final picked = await _imageSource.pickImage(context);
      if (!mounted || picked == null) return;
      final image = widget.imageProcessor.process(picked.bytes);
      final assetId = await widget.store.addAsset(
        widget.entry.id,
        AssetKind.image,
        image.mime,
        image.bytes,
      );
      if (!mounted) return;
      final size = imageBlockSize(image.width, image.height);
      final block = ContentBlock(
        id: _uuid.v4(),
        type: BlockType.image,
        assetId: assetId,
        x: -20,
        y: 12 + (_blocks.length * 8) % 80,
        w: size.width,
        h: size.height,
      );
      _editor.add(block);
      setState(() => _selectedId = block.id);
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
    final block = ContentBlock(
      id: _uuid.v4(),
      type: BlockType.sticker,
      stickerId: sticker.id,
      x: 8,
      y: 40 + (_blocks.length * 5) % 60,
      w: sticker.defaultSize.width,
      h: sticker.defaultSize.height,
    );
    _editor.add(block);
    setState(() => _selectedId = block.id);
  }

  ImageProvider<Object>? _imageProvider(String assetId) {
    final sticker = StickerCatalog.byId(assetId);
    if (sticker != null) {
      return _stickerProviders.putIfAbsent(
        assetId,
        () => AssetImage(sticker.assetPath),
      );
    }
    final bytes = widget.store.getAsset(assetId);
    if (bytes == null) return null;
    return _imageProviders.putIfAbsent(assetId, () => MemoryImage(bytes));
  }

  void _showImageError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openImage(ContentBlock block) async {
    final assetId = block.assetId;
    final bytes = assetId == null ? null : widget.store.getAsset(assetId);
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

  ContentBlock? _imageSelection() {
    final block = _editor.primarySelection;
    if (block == null ||
        (block.type != BlockType.image && block.type != BlockType.sticker)) {
      return null;
    }
    return block;
  }

  void _commitImageEdit(
    String blockId,
    void Function(ContentBlock block) mutate, {
    String label = 'Edit image',
  }) {
    final source = _blocks.where((block) => block.id == blockId).firstOrNull;
    if (source == null || source.locked) return;
    final next = source.clone();
    mutate(next);
    unawaited(_editor.replaceBlockAndCommit(next, label: label));
  }

  void _previewImageEdit(
    String blockId,
    void Function(ContentBlock block) mutate, {
    String label = 'Edit image',
  }) {
    final source = _blocks.where((block) => block.id == blockId).firstOrNull;
    if (source == null || source.locked) return;
    final next = source.clone();
    mutate(next);
    _editor.replaceBlockSnapshot(next, label: label);
  }

  Future<void> _showImageEditor() async {
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
                        _commitImageEdit(block.id, (next) => next.crop = null);
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
                          (next) => next.crop = _squareCrop,
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
                          (next) => next.crop = _portraitCrop,
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
                          (next) => next.crop = _wideCrop,
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
                      (next) => next.opacity = value,
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
                      (next) => next.brightness = value,
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
                      (next) => next.contrast = value,
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
                      (next) => next.saturation = value,
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
                        (next) => next.rotation += math.pi / 2,
                      ),
                      icon: const Icon(Icons.rotate_90_degrees_ccw),
                      label: const Text('Rotate 90°'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _commitImageEdit(
                        block.id,
                        (next) => next.flipX = !next.flipX,
                      ),
                      icon: const Icon(Icons.flip),
                      label: const Text('Flip horizontal'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _commitImageEdit(
                        block.id,
                        (next) => next.flipY = !next.flipY,
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
                      (next) => next.imageMask = nextMask,
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
    final selectedBlocks = _editor.selectedGraphSnapshot();
    if (selectedBlocks.isEmpty) return;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _RenameLayerDialog(
        title: 'Save template',
        label: 'Template name',
      ),
    );
    if (!mounted || name == null || name.trim().isEmpty) return;
    final now = DateTime.now();
    await widget.store.saveTemplate(
      JournalTemplate(
        id: _uuid.v4(),
        name: name.trim(),
        document: EntryDocument.fromEntry(
          Entry(
            id: _uuid.v4(),
            title: widget.entry.title,
            createdAt: now,
            blocks: selectedBlocks,
            board: _editor.board,
          ),
        ),
        createdAt: now,
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved template “${name.trim()}”')),
      );
    }
  }

  void _showTemplates() {
    final templates = widget.store.templates;
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
                        _editor.insertBlocks(
                          template.document.toEntry().blocks,
                          offset: Offset(
                            PageViewport.modelPageSize.width / 2,
                            PageViewport.modelPageSize.height / 2,
                          ),
                          label: 'Insert template',
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
    final archive = widget.store.archiveForEntry(widget.entry.id);
    if (archive == null || !mounted) return;
    final uri = await FilePicker.saveFile(
      fileName:
          '${widget.entry.title.trim().isEmpty ? 'journal' : widget.entry.title.trim()}.cozyjournal',
      bytes: archive.encode(),
      mimeType: 'application/x-cozyjournal',
      dialogTitle: 'Export journal backup',
      type: FileType.custom,
      allowedExtensions: ['cozyjournal'],
    );
    if (mounted && uri != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Journal backup exported')));
    }
  }

  Future<void> _importArchive() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['cozyjournal'],
    );
    if (!mounted || picked.isEmpty) return;
    final file = picked.single;
    final bytes = await file.readAsBytes();
    try {
      final archive = JournalArchive.decode(bytes);
      await widget.store.importArchive(archive);
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

  void _showInkSettings() {
    var colorValue = _inkColorValue;
    var width = _inkWidth;
    var opacity = _inkOpacity;
    showModalBottomSheet<void>(
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
                  subtitle: Text('Vector pen and highlighter presets'),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  children: [
                    for (final choice in const [
                      (label: 'Ink', value: 0xFF3B3226),
                      (label: 'Berry', value: 0xFF873F4D),
                      (label: 'Moss', value: 0xFF4E684A),
                    ])
                      ChoiceChip(
                        label: Text(choice.label),
                        selected: colorValue == choice.value,
                        onSelected: (_) =>
                            setSheetState(() => colorValue = choice.value),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Width ${width.toStringAsFixed(1)}'),
                Slider(
                  min: 0.8,
                  max: 8,
                  value: width,
                  onChanged: (value) => setSheetState(() => width = value),
                ),
                Text('Opacity ${(opacity * 100).round()}%'),
                Slider(
                  min: 0.2,
                  max: 1,
                  value: opacity,
                  onChanged: (value) => setSheetState(() => opacity = value),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () {
                      setState(() {
                        _inkColorValue = colorValue;
                        _inkWidth = width;
                        _inkOpacity = opacity;
                      });
                      Navigator.pop(context);
                    },
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
                    leading: const Icon(Icons.tune),
                    title: const Text('Ink settings'),
                    subtitle: const Text('Color, width, and opacity'),
                    onTap: () {
                      Navigator.pop(context);
                      _showInkSettings();
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
                  enabled: _editor.primarySelection != null,
                  onTap: _editor.primarySelection == null
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
    final block = _editor.primarySelection;
    if (block != null) _editor.setLocked(!block.locked);
  }

  void _showTransformInspector() {
    final block = _editor.primarySelection;
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
      _editor.updateBlock(block.id, (target) {
        target
          ..x = nextX!
          ..y = nextY!
          ..w = math.max(EntryCanvas.minWidth, nextWidth!)
          ..h = math.max(EntryCanvas.minHeight, nextHeight!)
          ..rotation = degrees! * math.pi / 180
          ..opacity = (nextOpacity! / 100).clamp(0.0, 1.0).toDouble();
      });
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
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final checkpoints = widget.store.checkpointsFor(widget.entry.id);
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.62,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.add_task_outlined),
                    title: const Text('Create recovery checkpoint'),
                    onTap: () async {
                      await widget.store.createCheckpoint(widget.entry.id);
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
                                  await widget.store.restoreCheckpoint(
                                    checkpoint.id,
                                  );
                                  final restored = widget.store.entries
                                      .firstWhere(
                                        (entry) => entry.id == widget.entry.id,
                                      );
                                  _editor.replaceDocument(
                                    restored.blocks,
                                    restored.board,
                                  );
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

  Future<void> _renameLayer(ContentBlock block) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameLayerDialog(initial: block.name ?? ''),
    );
    if (!mounted || name == null) return;
    _editor.renameLayer(block.id, name);
  }

  void _showLayers() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: PaperPage.paper,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.62,
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.layers_outlined),
                title: Text('Layers'),
                subtitle: Text('Top layers appear first'),
              ),
              const Divider(height: 1),
              Expanded(
                child: ReorderableListView.builder(
                  itemCount: _blocks.length,
                  onReorderItem: (oldIndex, newIndex) {
                    final visible = _blocks.reversed.toList();
                    if (oldIndex < 0 || oldIndex >= visible.length) return;
                    final targetIndex = (_blocks.length - newIndex - 1).clamp(
                      0,
                      _blocks.length,
                    );
                    _editor.reorderLayer(visible[oldIndex].id, targetIndex);
                  },
                  itemBuilder: (context, index) {
                    final block = _blocks[_blocks.length - index - 1];
                    final selected = _selectedId == block.id;
                    final label =
                        block.name ??
                        switch (block.type) {
                          BlockType.text =>
                            block.text.isEmpty
                                ? 'Text'
                                : block.text.split('\n').first,
                          BlockType.image => 'Photo',
                          BlockType.sticker => 'Sticker',
                          BlockType.ink => 'Drawing',
                          BlockType.shape => 'Shape',
                          BlockType.group => 'Group',
                        };
                    return ListTile(
                      key: ValueKey('layer-${block.id}'),
                      contentPadding: EdgeInsets.only(
                        left: block.groupId == null ? 16 : 40,
                        right: 8,
                      ),
                      selected: selected,
                      leading: Icon(switch (block.type) {
                        BlockType.text => Icons.text_fields,
                        BlockType.image => Icons.photo_outlined,
                        BlockType.sticker => Icons.emoji_emotions_outlined,
                        BlockType.ink => Icons.draw_outlined,
                        BlockType.shape => Icons.category_outlined,
                        BlockType.group => Icons.folder_copy_outlined,
                      }),
                      title: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: block.hidden ? 'Show layer' : 'Hide layer',
                            onPressed: () {
                              _editor.select(block.id);
                              _editor.setHidden(!block.hidden);
                            },
                            icon: Icon(
                              block.hidden
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          ),
                          IconButton(
                            tooltip: block.locked
                                ? 'Unlock layer'
                                : 'Lock layer',
                            onPressed: () {
                              _editor.select(block.id);
                              _editor.setLocked(!block.locked);
                            },
                            icon: Icon(
                              block.locked
                                  ? Icons.lock
                                  : Icons.lock_open_outlined,
                            ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'Layer actions',
                            onSelected: (action) {
                              switch (action) {
                                case 'rename':
                                  _renameLayer(block);
                                case 'forward':
                                  _editor.select(block.id);
                                  _editor.moveLayerForward();
                                case 'backward':
                                  _editor.select(block.id);
                                  _editor.moveLayerBackward();
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'rename',
                                child: Text('Rename layer'),
                              ),
                              PopupMenuItem(
                                value: 'forward',
                                child: Text('Bring forward'),
                              ),
                              PopupMenuItem(
                                value: 'backward',
                                child: Text('Send backward'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      onTap: () {
                        _editor.select(block.id);
                        setState(() => _selectedId = block.id);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
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
              PageViewport(
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
                    !_resizeActive && !(_editing && _editor.hasSelection),
                initialView: widget.entry.view,
                onViewChanged: widget.onViewChanged,
                child: RepaintBoundary(
                  key: _pageCaptureKey,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: PaperPage(child: const SizedBox.expand()),
                      ),
                      Positioned.fill(
                        child: EntryCanvas(
                          workspaceSize: _workspaceSize,
                          worldOrigin: _worldOrigin,
                          // Render from detached snapshots. EntryCanvas may
                          // mutate a preview during pointer updates, but the
                          // controller-owned document remains behind its
                          // explicit snapshot command boundary.
                          blocks: _blocks
                              .map((block) => block.clone())
                              .toList(),
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
                          onEditImage: (block) {
                            _editor.select(block.id);
                            setState(() => _selectedId = block.id);
                            _showImageEditor();
                          },
                          onChanged: _changeBlock,
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
                          onInkCreated: (block) {
                            _editor.add(block);
                            setState(() => _selectedId = block.id);
                          },
                          imageBytes: widget.store.getAsset,
                          imageProvider: _imageProvider,
                          onOpenImage: _openImage,
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
                                      onChanged: widget.onTitleChanged,
                                      style: _titleStyle(context),
                                      textAlign: TextAlign.center,
                                      decoration: const InputDecoration(
                                        hintText: 'Untitled page',
                                        border: InputBorder.none,
                                        isDense: true,
                                      ),
                                    )
                                  : Text(
                                      widget.entry.title.isEmpty
                                          ? 'Untitled page'
                                          : widget.entry.title,
                                      style: _titleStyle(context),
                                      textAlign: TextAlign.center,
                                    ),
                              const SizedBox(height: 4),
                              Text(
                                DateFormat.yMMMMd().format(
                                  widget.entry.createdAt,
                                ),
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
              if (!_editing)
                Positioned(
                  right: 12,
                  top: 12,
                  child: EntryChrome(
                    visible: widget.controlsVisible,
                    child: EditorToolbar(
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
                      recentColorValues: widget.store.recentColorValues,
                      favoriteColorValues: widget.store.favoriteColorValues,
                      onRecentColorAdded: _addRecentColor,
                      onFavoriteColorsChanged: _updateFavoriteColors,
                      onSampleColor: _requestColorSample,
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
                      locked: _editor.primarySelection?.locked ?? false,
                      onLayers: _showLayers,
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
                          final selected = _selectedId == null
                              ? null
                              : _blocks.firstWhere(
                                  (block) => block.id == _selectedId,
                                  orElse: () => ContentBlock(
                                    id: '',
                                    type: BlockType.image,
                                  ),
                                );
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
                      recentColorValues: widget.store.recentColorValues,
                      favoriteColorValues: widget.store.favoriteColorValues,
                      onRecentColorAdded: _addRecentColor,
                      onFavoriteColorsChanged: _updateFavoriteColors,
                      onSampleColor: _requestColorSample,
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
                      locked: _editor.primarySelection?.locked ?? false,
                      onLayers: _showLayers,
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
