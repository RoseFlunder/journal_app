import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../editor/editor_toolbar.dart';
import '../editor/entry_canvas.dart';
import '../models/entry.dart';
import '../models/sticker.dart';
import '../services/image_source.dart';
import '../services/journal_store.dart';
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
    required this.onEditingChanged,
    required this.onOpenNavigation,
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
  final ValueChanged<bool> onEditingChanged;

  final VoidCallback onOpenNavigation;
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
  String? _selectedId;
  String? _textEditingId;
  late final TextEditingController _titleController = TextEditingController(
    text: widget.entry.title,
  );
  late final ImageSourceService _imageSource =
      widget.imageSource ?? PlatformImageSource();
  bool _pickingImage = false;
  final Map<String, ImageProvider<Object>> _imageProviders = {};
  final Map<String, ImageProvider<Object>> _stickerProviders = {};

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _changeBlock(ContentBlock block) {
    widget.onBlocksChanged(List<ContentBlock>.from(widget.entry.blocks));
  }

  ContentBlock? get _editingTextBlock {
    final id = _textEditingId;
    if (id == null) return null;
    for (final block in widget.entry.blocks) {
      if (block.id == id && block.type == BlockType.text) return block;
    }
    return null;
  }

  double get _activeFontSize =>
      _editingTextBlock?.fontSize ?? widget.entry.titleFontSize;

  bool get _activeBold => _editingTextBlock?.bold ?? widget.entry.titleBold;

  bool get _activeItalic =>
      _editingTextBlock?.italic ?? widget.entry.titleItalic;

  void _changeFontSize(double delta) {
    final block = _editingTextBlock;
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
    final block = _editingTextBlock;
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
    final block = _editingTextBlock;
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

  TextStyle _titleStyle(BuildContext context) =>
      (Theme.of(context).textTheme.headlineSmall ?? const TextStyle()).copyWith(
        fontSize: widget.entry.titleFontSize,
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
      w: 60,
      h: 22,
    );
    widget.onBlocksChanged([...widget.entry.blocks, block]);
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sticker pack',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              GridView.builder(
                shrinkWrap: true,
                itemCount: StickerCatalog.definitions.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.25,
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
            ],
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          children: [
            PageViewport(
              canvasSize: _workspaceSize,
              fitSize: PageViewport.pageSize,
              initialFocus: _headerPosition,
              fitFocus: Offset(
                _pageFramePosition.dx + PageViewport.pageSize.width / 2,
                _pageFramePosition.dy + PageViewport.pageSize.height / 2,
              ),
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
                        onSelect: (id) {
                          if (id == null) {
                            FocusScope.of(context).unfocus();
                            setState(() => _textEditingId = null);
                            return;
                          }
                          setState(() {
                            _selectedId = id;
                            _textEditingId = null;
                          });
                        },
                        onEditText: (id) => setState(() {
                          _selectedId = id;
                          _textEditingId = id;
                        }),
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
                        padding: const EdgeInsets.fromLTRB(48, 18, 28, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _editing
                                ? TextField(
                                    key: const ValueKey('entry-title'),
                                    controller: _titleController,
                                    maxLines: 1,
                                    onTap: () {
                                      if (_textEditingId != null) {
                                        setState(() => _textEditingId = null);
                                      }
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
                              DateFormat.yMMMMd().format(
                                widget.entry.createdAt,
                              ),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: Colors.black54),
                            ),
                            Divider(
                              height: 24,
                              color: PaperPage.ink.withValues(alpha: 0.2),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              left: 12,
              top: 12,
              child: IconButton(
                tooltip: 'Open page navigation',
                onPressed: widget.onOpenNavigation,
                icon: const Icon(Icons.menu),
              ),
            ),
            if (!_editing)
              Positioned(
                right: 12,
                top: 12,
                child: EditorToolbar(
                  editing: false,
                  hasSelection: false,
                  textEditing: false,
                  onToggleEditing: () => setState(() {
                    _editing = true;
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
                  onToggleBold: _toggleBold,
                  onToggleItalic: _toggleItalic,
                  bold: _activeBold,
                  italic: _activeItalic,
                  onDelete: _deleteSelected,
                  onBringToFront: _bringToFront,
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
                    onToggleEditing: () => setState(() {
                      _editing = false;
                      widget.onEditingChanged(false);
                      _selectedId = null;
                      _textEditingId = null;
                    }),
                    onAddText: _addText,
                    onAddImage: _addImage,
                    onAddSticker: _addSticker,
                    onMore: _showMoreTools,
                    onEditText: () {
                      final block = _editingTextBlock;
                      if (block != null) {
                        setState(() => _textEditingId = block.id);
                      } else {
                        final selected = _selectedId == null
                            ? null
                            : widget.entry.blocks.firstWhere(
                                (block) => block.id == _selectedId,
                                orElse: () => ContentBlock(
                                  id: '',
                                  type: BlockType.image,
                                ),
                              );
                        if (selected?.type == BlockType.text) {
                          setState(() => _textEditingId = selected!.id);
                        }
                      }
                    },
                    onDecreaseFontSize: _activeFontSize > _minFontSize
                        ? () => _changeFontSize(-_fontSizeStep)
                        : null,
                    onIncreaseFontSize: _activeFontSize < _maxFontSize
                        ? () => _changeFontSize(_fontSizeStep)
                        : null,
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
