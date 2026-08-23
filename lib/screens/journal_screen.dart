import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/entry.dart';
import '../services/journal_store.dart';
import '../widgets/entry_chrome.dart';
import 'contents_page.dart';
import 'entry_page.dart';

/// Root of the journal: a [PageView] over
/// `[table of contents, ...one page per entry]`.
class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key, required this.store});

  final JournalStore store;

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  final PageController _pageController = PageController();
  bool _animating = false;
  int _currentPageIndex = 0;
  static const _chromeIdleDuration = Duration(seconds: 3);
  final Set<String> _editingEntryIds = <String>{};
  final Set<int> _activePointers = <int>{};
  Timer? _chromeTimer;
  bool _chromeVisible = true;

  @override
  void dispose() {
    _chromeTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  int get _pageCount => widget.store.entries.length + 1;

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
    if (page == 0 || page > widget.store.entries.length) return null;
    return widget.store.entries[page - 1].id;
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

  /// Jumps to the page of [entryIndex] (index into [JournalStore.entries]).
  /// The TOC occupies page 0 of the [PageView], so the page index is +1.
  void goToEntry(int entryIndex) => goToPageIndex(entryIndex + 1);

  void _goToToc() => goToPageIndex(0);
  void _goPrev() => goToPageIndex(_currentPage - 1);
  void _goNext() => goToPageIndex(_currentPage + 1);

  Future<void> _createPage() async {
    final entry = await widget.store.addEntry();
    // Wait for the PageView to pick up the new child, then animate to it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      goToEntry(widget.store.entries.indexWhere((e) => e.id == entry.id));
    });
  }

  Widget _buildEntryPage(Entry entry) {
    return EntryPage(
      entry: entry,
      store: widget.store,
      controlsVisible: _entryChromeVisible,
      onViewChanged: (view) =>
          widget.store.updateEntry(entry.id, (entry) => entry.view = view),
      onBlocksChanged: (blocks) =>
          widget.store.updateEntry(entry.id, (entry) => entry.blocks = blocks),
      onTitleChanged: (title) =>
          widget.store.updateEntry(entry.id, (entry) => entry.title = title),
      onTitleStyleChanged: (fontSize, bold, italic) =>
          widget.store.updateEntry(entry.id, (entry) {
            entry.titleFontSize = fontSize;
            entry.titleBold = bold;
            entry.titleItalic = italic;
          }),
      onTitleFontFamilyChanged: (fontFamily) => widget.store.updateEntry(
        entry.id,
        (entry) => entry.titleFontFamily = fontFamily,
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
      listenable: widget.store,
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
                            store: widget.store,
                            onOpenPage: goToEntry,
                            onNewPage: _createPage,
                          ),
                          for (var i = 0; i < widget.store.entries.length; i++)
                            _buildEntryPage(widget.store.entries[i]),
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
