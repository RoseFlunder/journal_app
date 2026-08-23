import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  int get _pageCount => widget.store.entries.length + 1;

  int get _currentPage {
    final page = _pageController.page;
    return page == null ? 0 : page.round().clamp(0, _pageCount - 1);
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

  void _createPage() {
    final entry = widget.store.addEntry();
    // Wait for the PageView to pick up the new child, then animate to it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      goToEntry(widget.store.entries.indexWhere((e) => e.id == entry.id));
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        return CallbackShortcuts(
          bindings: {
            // Keyboard navigation (arrows also work when no text field is
            // focused; PageUp/PageDown never do, so they always navigate).
            SingleActivator(LogicalKeyboardKey.pageDown): _goNext,
            SingleActivator(LogicalKeyboardKey.pageUp): _goPrev,
            SingleActivator(LogicalKeyboardKey.home): _goToToc,
            SingleActivator(LogicalKeyboardKey.arrowRight): _goNext,
            SingleActivator(LogicalKeyboardKey.arrowLeft): _goPrev,
          },
          child: PageView(
            controller: _pageController,
            children: [
              ContentsPage(
                store: widget.store,
                onOpenPage: goToEntry,
                onNewPage: _createPage,
              ),
              for (var i = 0; i < widget.store.entries.length; i++)
                EntryPage(
                  entry: widget.store.entries[i],
                  index: i,
                  total: widget.store.entries.length,
                  onContents: _goToToc,
                  onPrev: _goPrev,
                  onNext: _goNext,
                ),
            ],
          ),
        );
      },
    );
  }
}
