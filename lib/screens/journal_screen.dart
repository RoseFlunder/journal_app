import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/entry.dart';
import '../services/journal_store.dart';
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

  @override
  void dispose() {
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
      onEditingChanged: (_) {},
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
              child: Stack(
                children: [
                  PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (page) {
                      if (page != _currentPageIndex) {
                        setState(() => _currentPageIndex = page);
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
                      child: _NavigationButton(
                        tooltip: 'Home',
                        icon: Icons.home_outlined,
                        onPressed: _goToToc,
                      ),
                    ),
                  Positioned(
                    left: 8,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _NavigationButton(
                        tooltip: 'Previous page',
                        icon: Icons.chevron_left,
                        onPressed: _currentPage > 0 ? _goPrev : null,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 0,
                    bottom: 0,
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
                ],
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
