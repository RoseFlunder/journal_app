import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../models/document.dart';
import '../view_models/journal_view_model.dart';
import '../view_models/shared_page_view_model.dart';
import '../view_models/cloud_sync_view_model.dart';
import '../../editor/view_models/entry_editor_view_model.dart';
import '../../music/view_models/page_music_controller.dart';
import '../../../../services/image_source.dart';
import '../../../../widgets/entry_chrome.dart';
import 'contents_page.dart';
import '../../editor/views/entry_page.dart';

/// Root of the journal: a [PageView] over
/// `[table of contents, ...one page per entry]`.
class JournalScreen extends StatefulWidget {
  const JournalScreen({
    super.key,
    required this.journal,
    required this.sharedPages,
    required this.music,
    required this.cloudSync,
    required this.editorViewModelFactory,
    required this.imageSource,
  });

  final JournalViewModel journal;
  final SharedPageViewModel sharedPages;
  final PageMusicController music;
  final CloudSyncViewModel cloudSync;
  final EntryEditorViewModelFactory editorViewModelFactory;
  final ImageSourceService imageSource;

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  final PageController _pageController = PageController();
  final Map<String, EntryEditorViewModel> _editorViewModels = {};
  late final JournalViewModel _journal;
  late final PageMusicController _music;
  bool _animating = false;
  int? _pendingPageIndex;
  int? _targetPageIndex;
  String? _visiblePageId;
  List<String> _knownPageIds = [];
  bool _confirmationVisible = false;
  int _currentPageIndex = 0;
  static const _chromeIdleDuration = Duration(seconds: 3);
  final Set<String> _editingEntryIds = <String>{};
  final Set<int> _activePointers = <int>{};
  Timer? _chromeTimer;
  bool _chromeVisible = true;

  @override
  void initState() {
    super.initState();
    _journal = widget.journal;
    _knownPageIds = _journal.documents.map((page) => page.id).toList();
    _music = widget.music;
    _journal.addListener(_handleJournalChanged);
    widget.sharedPages.addListener(_handleSharedPageChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.sharedPages.start();
    });
  }

  @override
  void dispose() {
    _chromeTimer?.cancel();
    _pageController.dispose();
    _journal.removeListener(_handleJournalChanged);
    widget.sharedPages.removeListener(_handleSharedPageChanged);
    for (final editor in _editorViewModels.values) {
      editor.dispose();
    }
    _editorViewModels.clear();
    _journal.dispose();
    _music.dispose();
    super.dispose();
  }

  int get _pageCount => _journal.documents.length + 1;

  int get _currentPage {
    return _currentPageIndex.clamp(0, _pageCount - 1).toInt();
  }

  /// Animates to absolute [PageView] page [page] (0 = TOC, 1+ = entries).
  void goToPageIndex(int page) {
    if (!_pageController.hasClients) return;
    if (page < 0 || page >= _pageCount) return;
    _pendingPageIndex = page;
    if (!_animating) unawaited(_drainNavigationQueue());
  }

  Future<void> _drainNavigationQueue() async {
    if (_animating) return;
    _animating = true;
    try {
      while (mounted) {
        final target = _pendingPageIndex;
        if (target == null) break;
        _pendingPageIndex = null;
        if (!_pageController.hasClients || target == _currentPage) continue;
        _targetPageIndex = target;
        final distance = (target - _currentPage).abs();
        if (distance == 1) {
          await _pageController.animateToPage(
            target,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
          );
        } else {
          // A pixel animation across many PageView children constructs and
          // lays out intermediate editors. Long-distance navigation should
          // pay only for its destination.
          _pageController.jumpToPage(target);
          await WidgetsBinding.instance.endOfFrame;
        }
        _targetPageIndex = null;
      }
    } finally {
      _targetPageIndex = null;
      _animating = false;
    }
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
  int get _navigationPage =>
      _pendingPageIndex ?? _targetPageIndex ?? _currentPage;

  void _goPrev() => goToPageIndex(_navigationPage - 1);
  void _goNext() => goToPageIndex(_navigationPage + 1);

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

  Future<void> _renamePage(String id, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final editor = _editorViewModels[id];
    if (editor == null) {
      await _journal.renamePage(id, trimmed);
      return;
    }
    if (editor.document.title == trimmed) return;
    await editor.updateMetadata(
      editor.document.copyWith(title: trimmed, modifiedAt: DateTime.now()),
    );
  }

  Future<String?> _promptForTitle() async {
    return showDialog<String>(
      context: context,
      builder: (context) => const _NewPageTitleDialog(),
    );
  }

  Widget _buildEntryPage(EntryDocument document) {
    return EntryPage(
      key: ValueKey(document.id),
      viewModel: _editorFor(document),
      controlsVisible: _entryChromeVisible,
      active: document.id == _activeEntryId,
      musicController: _music,
      imageSource: widget.imageSource,
      onDocumentPreviewChanged: _journal.previewDocument,
      onEditingChanged: (editing) =>
          _handleEditingChanged(document.id, editing),
    );
  }

  EntryEditorViewModel _editorFor(EntryDocument document) {
    return _editorViewModels.putIfAbsent(
      document.id,
      () => widget.editorViewModelFactory(document),
    );
  }

  void _pruneEditorViewModels(Iterable<EntryDocument> documents) {
    final activeIds = documents.map((document) => document.id).toSet();
    final removedIds = _editorViewModels.keys
        .where((id) => !activeIds.contains(id))
        .toList(growable: false);
    for (final id in removedIds) {
      _editorViewModels.remove(id)?.dispose();
    }
  }

  void _handleJournalChanged() {
    _pruneEditorViewModels(_journal.documents);
    final ids = _journal.documents.map((page) => page.id).toList();
    final id = _visiblePageId;
    final orderChanged =
        ids.length != _knownPageIds.length ||
        Iterable<int>.generate(ids.length)
            .any((i) => ids[i] != _knownPageIds[i]);
    _knownPageIds = ids;
    if (id != null && orderChanged) {
      _jumpToDocument(id);
    } else if (mounted && (orderChanged || _currentPage == 0)) {
      // Entry pages listen to their own editor models. Rebuilding the entire
      // journal for every persisted edit makes navigation compete with work
      // that only the table of contents needs.
      setState(() {});
    }
  }

  void _jumpToDocument(String id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      final index = _journal.indexOf(id);
      final page = index < 0 ? 0 : index + 1;
      _visiblePageId = index < 0 ? null : id;
      _currentPageIndex = page;
      _pageController.jumpToPage(page);
      setState(() {});
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _handleSharedPageChanged() {
    if (!mounted) return;
    setState(() {});
    final error = widget.sharedPages.takeError();
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
    final added = widget.sharedPages.takeAddedPageId();
    if (added != null) _jumpToDocument(added);
    final pending = widget.sharedPages.pendingPage;
    if (pending != null && !_confirmationVisible) {
      _confirmationVisible = true;
      unawaited(_confirmSharedPage(pending.title, pending.createdAt));
    }
  }

  Future<void> _confirmSharedPage(String title, DateTime createdAt) async {
    final add = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Do you want to add this page to your journal?'),
        content: Text(
          '${title.isEmpty ? 'Untitled page' : title}\n'
          '${DateFormat.yMMMMd().format(createdAt.toLocal())}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add page'),
          ),
        ],
      ),
    );
    _confirmationVisible = false;
    if (mounted) widget.sharedPages.confirm(add == true);
  }

  Future<void> _activateMusicForPage(int page) async {
    if (page <= 0 || page > _journal.documents.length) {
      await _music.setActivePage(null, null);
      return;
    }
    final document = _journal.documents[page - 1];
    await _music.setActivePage(document.id, document.music);
  }

  void _handleBack() {
    if (_currentPage != 0) _goToToc();
  }

  @override
  Widget build(BuildContext context) {
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
                  PageView.builder(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _pageCount,
                    onPageChanged: (page) {
                      _visiblePageId =
                          page > 0 && page <= _journal.documents.length
                          ? _journal.documents[page - 1].id
                          : null;
                      if (page != _currentPageIndex) {
                        setState(() => _currentPageIndex = page);
                        _chromeTimer?.cancel();
                        _chromeVisible = true;
                        if (page > 0) {
                          _scheduleChromeHide();
                        }
                      }
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && page == _currentPage) {
                          unawaited(_activateMusicForPage(page));
                        }
                      });
                    },
                    itemBuilder: (context, page) {
                      if (page == 0) {
                        return ContentsPage(
                          documents: _journal.documents,
                          readAsset: _journal.readAsset,
                          onOpenPage: goToEntry,
                          onNewPage: _createPage,
                          onRenamePage: _renamePage,
                          onDeletePage: _journal.deletePage,
                          cloudSync: widget.cloudSync,
                        );
                      }
                      return _buildEntryPage(_journal.documents[page - 1]);
                    },
                  ),
                  if (widget.sharedPages.busy &&
                      widget.sharedPages.pendingPage == null)
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(),
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
    final surface = Theme.of(
      context,
    ).colorScheme.surface.withValues(alpha: 0.88);
    return SizedBox(
      width: 48,
      height: 48,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: const EdgeInsets.all(4),
        icon: DecoratedBox(
          decoration: BoxDecoration(
            color: surface,
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 22),
          ),
        ),
      ),
    );
  }
}
