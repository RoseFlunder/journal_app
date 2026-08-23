import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../editor/editor_toolbar.dart';
import '../editor/entry_canvas.dart';
import '../models/entry.dart';
import '../models/sticker.dart';
import '../services/image_source.dart';
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
    required this.onBlocksChanged,
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
  final ValueChanged<List<ContentBlock>> onBlocksChanged;
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

class _EntryPageState extends State<EntryPage> {
  static const _uuid = Uuid();
  static const _workspaceSize = Size(10000, 10000);
  static const _pageFramePosition = Offset(4000, 4500);
  static const _worldOrigin = Offset(450, 450);
  static const _headerPosition = Offset(4000, 4500);
  static const _fontSizeStep = 2.0;
  static const _minFontSize = 12.0;
  static const _maxFontSize = 48.0;
  bool _editing = false;
  bool _resizeActive = false;
  bool _titleFocused = false;
  String? _selectedId;
  String? _textEditingId;
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

  @override
  void dispose() {
    _titleController.dispose();
    _titleFocusNode
      ..removeListener(_handleTitleFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _handleTitleFocusChanged() {
    if (!mounted || !_titleFocusNode.hasFocus || _titleFocused) return;
    setState(() {
      _titleFocused = true;
      _textEditingId = null;
    });
  }

  void _changeBlock(ContentBlock block) {
    widget.onBlocksChanged(List<ContentBlock>.from(widget.entry.blocks));
  }

  void _beginTextEditing(String blockId) {
    setState(() {
      _titleFocused = false;
      _selectedId = blockId;
      _textEditingId = blockId;
    });
  }

  void _stopTextEditing() {
    FocusScope.of(context).unfocus();
    setState(() {
      _titleFocused = false;
      _textEditingId = null;
    });
  }

  ContentBlock? get _editingTextBlock {
    final id = _textEditingId;
    if (id == null) return null;
    for (final block in widget.entry.blocks) {
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
    for (final block in widget.entry.blocks) {
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
      block.fontFamily = fontFamily;
      _changeBlock(block);
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
      block.fontSize = size;
      _changeBlock(block);
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
      block.bold = !block.bold;
      _changeBlock(block);
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
      block.italic = !block.italic;
      _changeBlock(block);
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
      block.textColorValue = value;
      _changeBlock(block);
    } else if (_titleFocused) {
      widget.onTitleTextColorChanged(value);
    }
    setState(() {});
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
      y: 12 + (widget.entry.blocks.length * 8) % 80,
      w: 30,
      h: 11,
      fontSize: 26,
    );
    widget.onBlocksChanged([...widget.entry.blocks, block]);
    setState(() {
      _titleFocused = false;
      _selectedId = block.id;
      _textEditingId = block.id;
    });
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
        y: 12 + (widget.entry.blocks.length * 8) % 80,
        w: size.width,
        h: size.height,
      );
      widget.onBlocksChanged([...widget.entry.blocks, block]);
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
      y: 40 + (widget.entry.blocks.length * 5) % 60,
      w: sticker.defaultSize.width,
      h: sticker.defaultSize.height,
    );
    widget.onBlocksChanged([...widget.entry.blocks, block]);
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

  void _showMoreTools() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: PaperPage.paper,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              leading: Icon(Icons.brush_outlined),
              title: Text('Draw & doodle'),
              subtitle: Text('Coming soon'),
              enabled: false,
            ),
            const ListTile(
              leading: Icon(Icons.tune),
              title: Text('Photo editing'),
              subtitle: Text('Coming soon'),
              enabled: false,
            ),
            const ListTile(
              leading: Icon(Icons.music_note_outlined),
              title: Text('Background music'),
              subtitle: Text('Coming soon'),
              enabled: false,
            ),
          ],
        ),
      ),
    );
  }

  void _deleteSelected() {
    final selectedId = _selectedId;
    if (selectedId == null) return;
    final selected = widget.entry.blocks.firstWhere(
      (block) => block.id == selectedId,
    );
    final remaining = widget.entry.blocks
        .where((block) => block.id != selectedId)
        .toList();
    if (selected.type == BlockType.image && selected.assetId != null) {
      widget.store.removeAssetIfUnreferenced(selected.assetId!, remaining);
    }
    widget.onBlocksChanged(remaining);
    setState(() => _selectedId = null);
  }

  void _bringToFront() {
    final selectedId = _selectedId;
    if (selectedId == null) return;
    final blocks = List<ContentBlock>.from(widget.entry.blocks);
    final index = blocks.indexWhere((block) => block.id == selectedId);
    if (index < 0 || index == blocks.length - 1) return;
    final block = blocks.removeAt(index);
    blocks.add(block);
    widget.onBlocksChanged(blocks);
  }

  Rect _contentBounds() {
    // This is the actual visible header column: the title field and date are
    // inset from the page frame by the same padding used below.
    var bounds = Rect.fromLTWH(
      _headerPosition.dx + 220,
      _headerPosition.dy + 18,
      752,
      92,
    );
    for (final block in widget.entry.blocks) {
      final width = math.max(EntryCanvas.minWidth, block.w) *
          PageViewport.modelToRenderScale;
      final height = math.max(EntryCanvas.minHeight, block.h) *
          PageViewport.modelToRenderScale;
      final center = Offset(
        (block.x + _worldOrigin.dx) * PageViewport.modelToRenderScale +
            width / 2,
        (block.y + _worldOrigin.dy) * PageViewport.modelToRenderScale +
            height / 2,
      );
      bounds = bounds.expandToInclude(
        ViewportMath.rotatedRectBounds(
          Rect.fromCenter(center: center, width: width, height: height),
          block.rotation,
        ),
      );
    }
    return bounds;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          children: [
            PageViewport(
              canvasSize: _workspaceSize,
              pageRect: Rect.fromLTWH(
                _pageFramePosition.dx,
                _pageFramePosition.dy,
                PageViewport.pageSize.width,
                PageViewport.pageSize.height,
              ),
              contentRect: _contentBounds(),
              controlsBottomInset: _editing ? 88 : 12,
              controlsVisible: widget.controlsVisible,
              gesturesEnabled: !_resizeActive,
              initialView: widget.entry.view,
              onViewChanged: widget.onViewChanged,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    left: _pageFramePosition.dx,
                    top: _pageFramePosition.dy,
                    width: PageViewport.pageSize.width,
                    height: PageViewport.pageSize.height,
                    child: const PaperPage(child: SizedBox.expand()),
                  ),
                  Positioned.fill(
                    child: EntryCanvas(
                      workspaceSize: _workspaceSize,
                      worldOrigin: _worldOrigin,
                      blocks: widget.entry.blocks,
                      editing: _editing,
                      selectedId: _selectedId,
                      textEditingId: _textEditingId,
                      onResizeActiveChanged: (active) {
                        if (_resizeActive == active || !mounted) return;
                        setState(() => _resizeActive = active);
                      },
                      onSelect: (id) {
                        if (id == null) {
                          FocusScope.of(context).unfocus();
                          setState(() {
                            _titleFocused = false;
                            _textEditingId = null;
                          });
                          return;
                        }
                        setState(() {
                          _titleFocused = false;
                          _selectedId = id;
                          _textEditingId = null;
                        });
                      },
                      onEditText: _beginTextEditing,
                      onChanged: _changeBlock,
                      imageBytes: widget.store.getAsset,
                      imageProvider: _imageProvider,
                      onOpenImage: _openImage,
                    ),
                  ),
                  Positioned(
                    left: _headerPosition.dx,
                    top: _headerPosition.dy,
                    width: 1000,
                    child: Padding(
                      // Leave room for the page-level Home control in the
                      // upper-left corner of the viewport.
                      padding: const EdgeInsets.fromLTRB(220, 18, 28, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                                ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat.yMMMMd().format(widget.entry.createdAt),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
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
                    onToggleBold: _toggleBold,
                    onToggleItalic: _toggleItalic,
                    bold: _activeBold,
                    italic: _activeItalic,
                    onDelete: _deleteSelected,
                    onBringToFront: _bringToFront,
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
                    onToggleEditing: () {
                      FocusScope.of(context).unfocus();
                      setState(() {
                        _editing = false;
                        _resizeActive = false;
                        _titleFocused = false;
                        widget.onEditingChanged(false);
                        _selectedId = null;
                        _textEditingId = null;
                      });
                    },
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
                            : widget.entry.blocks.firstWhere(
                                (block) => block.id == _selectedId,
                                orElse: () =>
                                    ContentBlock(id: '', type: BlockType.image),
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
                    onToggleBold: _toggleBold,
                    onToggleItalic: _toggleItalic,
                    bold: _activeBold,
                    italic: _activeItalic,
                    onDelete: _deleteSelected,
                    onBringToFront: _bringToFront,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
