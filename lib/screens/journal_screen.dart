import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/document.dart';
import '../models/entry.dart';
import '../services/repositories.dart';
import '../view_models/journal_view_model.dart';
import '../widgets/entry_chrome.dart';
import 'contents_page.dart';
import 'entry_page.dart';

/// Root of the journal: a [PageView] over
/// `[table of contents, ...one page per entry]`.
class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key, required this.repository});

  final JournalRepository repository;

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  final PageController _pageController = PageController();
  late final JournalViewModel _journal;
  bool _animating = false;
  int _currentPageIndex = 0;
  static const _chromeIdleDuration = Duration(seconds: 3);
  final Set<String> _editingEntryIds = <String>{};
  final Set<int> _activePointers = <int>{};
  Timer? _chromeTimer;
  bool _chromeVisible = true;

  @override
  void initState() {
    super.initState();
    _journal = JournalViewModel(repository: widget.repository);
  }

  @override
  void dispose() {
    _chromeTimer?.cancel();
    _pageController.dispose();
    _journal.dispose();
    super.dispose();
  }

  int get _pageCount => _journal.documents.length + 1;

  int get _currentPage {
    return _currentPageIndex.clamp(0, _pageCount - 1).toInt();
  }

  /// Animates to absolute [PageView] page [page] (0 = TOC, 1+ = entries).
  void goToPageIndex(int page) {
    if (_animating || !_pageController.hasClients) return;
    if (page < 0 || page >= _pageCount) return;
    _animating = true;
    _pageController
        .animateToPage(
          page,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        )
        .whenComplete(() => _animating = false);
  }

  String? get _activeEntryId {
    final page = _currentPage;
    if (page == 0 || page > _journal.documents.length) return null;
    return _journal.documents[page - 1].id;
  }

  bool get _activeEntryIsEditing {
    final id = _activeEntryId;
    return id != null && _editingEntryIds.contains(id);
  }

  bool get _entryChromeVisible =>
      _currentPage > 0 && (_chromeVisible || _activeEntryIsEditing);

  void _scheduleChromeHide() {
    _chromeTimer?.cancel();
    if (_currentPage == 0 || _activeEntryIsEditing) return;
    _chromeTimer = Timer(_chromeIdleDuration, () {
      if (!mounted || _currentPage == 0 || _activeEntryIsEditing) return;
      setState(() => _chromeVisible = false);
    });
  }

  void _showChrome({bool schedule = true}) {
    if (_currentPage == 0) return;
    _chromeTimer?.cancel();
    if (!_chromeVisible) setState(() => _chromeVisible = true);
    if (schedule) _scheduleChromeHide();
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_currentPage == 0) return;
    _activePointers.add(event.pointer);
    _showChrome(schedule: false);
  }

  void _handlePointerUp(PointerEvent event) {
    if (_currentPage == 0) return;
    _activePointers.remove(event.pointer);
    if (_activePointers.isEmpty) _scheduleChromeHide();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (_currentPage > 0) _showChrome();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && _currentPage > 0) _showChrome();
    return KeyEventResult.ignored;
  }

  void _handleEditingChanged(String entryId, bool editing) {
    setState(() {
      if (editing) {
        _editingEntryIds.add(entryId);
      } else {
        _editingEntryIds.remove(entryId);
      }
    });
    if (entryId != _activeEntryId) return;
    if (editing) {
      _chromeTimer?.cancel();
      if (!_chromeVisible) setState(() => _chromeVisible = true);
    } else {
      _showChrome();
    }
  }

  /// Jumps to the page of [entryIndex] (index into the repository documents).
  /// The TOC occupies page 0 of the [PageView], so the page index is +1.
  void goToEntry(int entryIndex) => goToPageIndex(entryIndex + 1);

  void _goToToc() => goToPageIndex(0);
  void _goPrev() => goToPageIndex(_currentPage - 1);
  void _goNext() => goToPageIndex(_currentPage + 1);

  Future<void> _createPage() async {
    final title = await _promptForTitle();
    if (!mounted || title == null) return;
    final document = await _journal.createPage(title: title);
    // Wait two frames: the store notification builds the new PageView child
    // on the first one, then the controller can safely animate to it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        goToEntry(_journal.indexOf(document.id));
      });
    });
  }

  Future<String?> _promptForTitle() async {
    return showDialog<String>(
      context: context,
      builder: (context) => const _NewPageTitleDialog(),
    );
  }

  EntryDocument _latestDocument(EntryDocument fallback) =>
      widget.repository.documents.firstWhere(
        (document) => document.id == fallback.id,
        orElse: () => fallback,
      );

  void _previewEntryMutation(
    EntryDocument fallback,
    List<ContentBlock> blocks,
    BoardSettings board,
  ) {
    final entry = _latestDocument(fallback).toEntry()
      ..blocks = blocks
      ..board = board;
    widget.repository.previewDocument(EntryDocument.fromEntry(entry));
  }

  Future<void> _saveEntryMutation(
    EntryDocument fallback,
    void Function(Entry entry) mutate,
  ) async {
    final entry = _latestDocument(fallback).toEntry();
    mutate(entry);
    await _journal.saveDocument(EntryDocument.fromEntry(entry));
  }

  Widget _buildEntryPage(EntryDocument document) {
    final entry = document.toEntry();
    return EntryPage(
      entry: entry,
      repository: widget.repository,
      controlsVisible: _entryChromeVisible,
      onViewChanged: (view) =>
          _saveEntryMutation(document, (entry) => entry.view = view),
      onDocumentPreviewChanged: (blocks, board) =>
          _previewEntryMutation(document, blocks, board),
      onTitleChanged: (title) =>
          _saveEntryMutation(document, (entry) => entry.title = title),
      onTitleStyleChanged: (fontSize, bold, italic) =>
          _saveEntryMutation(document, (entry) {
            entry
              ..titleFontSize = fontSize
              ..titleBold = bold
              ..titleItalic = italic;
          }),
      onTitleFontFamilyChanged: (fontFamily) => _saveEntryMutation(
        document,
        (entry) => entry.titleFontFamily = fontFamily,
      ),
      onTitleTextColorChanged: (colorValue) => _saveEntryMutation(
        document,
        (entry) => entry.titleTextColorValue = colorValue,
      ),
      onEditingChanged: (editing) => _handleEditingChanged(entry.id, editing),
    );
  }

  void _handleBack() {
    if (_currentPage != 0) _goToToc();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _journal,
      builder: (context, _) {
        return PopScope(
          canPop: _currentPage == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _handleBack();
          },
          child: Scaffold(
            body: CallbackShortcuts(
              bindings: {
                // Keyboard navigation (arrows also work when no text field is
                // focused; PageUp/PageDown never do, so they always navigate).
                SingleActivator(LogicalKeyboardKey.pageDown): _goNext,
                SingleActivator(LogicalKeyboardKey.pageUp): _goPrev,
                SingleActivator(LogicalKeyboardKey.home): _goToToc,
                SingleActivator(LogicalKeyboardKey.arrowRight): _goNext,
                SingleActivator(LogicalKeyboardKey.arrowLeft): _goPrev,
              },
              child: Focus(
                autofocus: true,
                onKeyEvent: _handleKeyEvent,
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: _handlePointerDown,
                  onPointerUp: _handlePointerUp,
                  onPointerCancel: _handlePointerUp,
                  onPointerSignal: _handlePointerSignal,
                  child: Stack(
                    children: [
                      PageView(
                        controller: _pageController,
                        physics: const NeverScrollableScrollPhysics(),
                        onPageChanged: (page) {
                          if (page != _currentPageIndex) {
                            setState(() => _currentPageIndex = page);
                            _chromeTimer?.cancel();
                            _chromeVisible = true;
                            if (page > 0) {
                              _scheduleChromeHide();
                            }
                          }
                        },
                        children: [
                          ContentsPage(
                            repository: widget.repository,
                            onOpenPage: goToEntry,
                            onNewPage: _createPage,
                          ),
                          for (final document in _journal.documents)
                            _buildEntryPage(document),
                        ],
                      ),
                      if (_currentPage > 0)
                        Positioned(
                          left: 12,
                          top: MediaQuery.paddingOf(context).top + 12,
                          child: EntryChrome(
                            visible: _entryChromeVisible,
                            child: _NavigationButton(
                              tooltip: 'Home',
                              icon: Icons.home_outlined,
                              onPressed: _goToToc,
                            ),
                          ),
                        ),
                      if (_currentPage > 0)
                        Positioned(
                          left: 8,
                          top: 0,
                          bottom: 0,
                          child: EntryChrome(
                            visible: _entryChromeVisible,
                            child: Center(
                              child: _NavigationButton(
                                tooltip: 'Previous page',
                                icon: Icons.chevron_left,
                                onPressed: _goPrev,
                              ),
                            ),
                          ),
                        ),
                      if (_currentPage > 0)
                        Positioned(
                          right: 8,
                          top: 0,
                          bottom: 0,
                          child: EntryChrome(
                            visible: _entryChromeVisible,
                            child: Center(
                              child: _NavigationButton(
                                tooltip: 'Next page',
                                icon: Icons.chevron_right,
                                onPressed: _currentPage < _pageCount - 1
                                    ? _goNext
                                    : null,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NewPageTitleDialog extends StatefulWidget {
  const _NewPageTitleDialog();

  @override
  State<_NewPageTitleDialog> createState() => _NewPageTitleDialogState();
}

class _NewPageTitleDialogState extends State<_NewPageTitleDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _controller.text.trim();
    if (title.isNotEmpty) Navigator.pop(context, title);
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = _controller.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Text('Name your journal page'),
      content: TextField(
        key: const ValueKey('new-page-title'),
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
        decoration: const InputDecoration(
          labelText: 'Page title',
          hintText: 'e.g. Sunday reflections',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: canCreate ? _submit : null,
          child: const Text('Create page'),
        ),
      ],
    );
  }
}

class _NavigationButton extends StatelessWidget {
  const _NavigationButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.88),
      shape: const CircleBorder(),
      elevation: 2,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}
