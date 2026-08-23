import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../editor/editor_toolbar.dart';
import '../editor/entry_canvas.dart';
import '../models/entry.dart';
import '../widgets/page_viewport.dart';
import '../widgets/paper_page.dart';

/// Shows one [Entry] as a journal page.
///
/// M1: read-only placeholder page with title + date. Free-positioned
/// content blocks arrive in later milestones (see PLAN.md).
class EntryPage extends StatefulWidget {
  const EntryPage({
    super.key,
    required this.entry,
    required this.index,
    required this.total,
    required this.onViewChanged,
    required this.onBlocksChanged,
    required this.onEditingChanged,
    required this.onOpenNavigation,
    required this.onContents,
    required this.onPrev,
    required this.onNext,
  });

  /// Index of this entry within the journal (0-based).
  final Entry entry;
  final int index;
  final int total;
  final ValueChanged<ViewState> onViewChanged;
  final ValueChanged<List<ContentBlock>> onBlocksChanged;
  final ValueChanged<bool> onEditingChanged;

  final VoidCallback onOpenNavigation;
  final VoidCallback onContents;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  State<EntryPage> createState() => _EntryPageState();
}

class _EntryPageState extends State<EntryPage> {
  static const _uuid = Uuid();
  bool _editing = false;
  String? _selectedId;
  String? _textEditingId;

  void _changeBlock(ContentBlock block) {
    widget.onBlocksChanged(List<ContentBlock>.from(widget.entry.blocks));
  }

  void _addText() {
    final block = ContentBlock(
      id: _uuid.v4(),
      type: BlockType.text,
      text: '',
      x: 6,
      y: 12 + (widget.entry.blocks.length * 8) % 80,
      w: 60,
      h: 22,
    );
    widget.onBlocksChanged([...widget.entry.blocks, block]);
    setState(() => _selectedId = block.id);
  }

  void _deleteSelected() {
    final selectedId = _selectedId;
    if (selectedId == null) return;
    widget.onBlocksChanged(
      widget.entry.blocks.where((block) => block.id != selectedId).toList(),
    );
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
      backgroundColor: const Color(0xFFE4D7BF),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Stack(
            children: [
              PageViewport(
                initialView: widget.entry.view,
                onViewChanged: widget.onViewChanged,
                child: PaperPage(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(48, 18, 28, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                  // Navigation row (desktop/web affordance).
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: widget.onContents,
                        icon: const Icon(Icons.menu_book_outlined),
                        label: const Text('Contents'),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Previous page (PageUp / \u2190)',
                        onPressed: widget.index > 0 ? widget.onPrev : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      IconButton(
                        tooltip: 'Next page (PageDown / \u2192)',
                        onPressed: widget.index + 1 < widget.total
                          ? widget.onNext
                          : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  Text(
                    widget.entry.title.isEmpty
                        ? 'Untitled page'
                        : widget.entry.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat.yMMMMd().format(widget.entry.createdAt),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: Colors.black54),
                  ),
                  Divider(
                    height: 24,
                    color: PaperPage.ink.withValues(alpha: 0.2),
                  ),
                  Expanded(
                    child: EntryCanvas(
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
                    ),
                  ),
                      ],
                    ),
                  ),
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
              Positioned(
                right: 12,
                top: 12,
                child: EditorToolbar(
                  editing: _editing,
                  hasSelection: _selectedId != null,
                  textEditing: _textEditingId != null,
                  onToggleEditing: () => setState(() {
                    _editing = !_editing;
                    widget.onEditingChanged(_editing);
                    if (!_editing) {
                      _selectedId = null;
                      _textEditingId = null;
                    }
                  }),
                  onAddText: _addText,
                  onEditText: () => setState(() {
                    _textEditingId = _selectedId;
                  }),
                  onDelete: _deleteSelected,
                  onBringToFront: _bringToFront,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
