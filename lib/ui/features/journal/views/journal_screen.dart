import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../models/document.dart';
import '../../../../models/page_music.dart';
import '../../../../services/audio_playback.dart';
import '../../../../services/repositories.dart';
import '../view_models/journal_view_model.dart';
import '../../editor/view_models/entry_editor_view_model.dart';
import '../../music/view_models/page_music_controller.dart';
import '../../../../widgets/entry_chrome.dart';
import 'contents_page.dart';
import '../../editor/views/entry_page.dart';

/// Root of the journal: a [PageView] over
/// `[table of contents, ...one page per entry]`.
class JournalScreen extends StatefulWidget {
  const JournalScreen({
    super.key,
    required this.repositories,
    required this.musicCatalog,
    required this.audioPlaybackFactory,
    required this.editorViewModelFactory,
  });

  final JournalRepositories repositories;
  final MusicCatalogRepository musicCatalog;
  final AudioPlaybackFactory audioPlaybackFactory;
  final EntryEditorViewModelFactory editorViewModelFactory;

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  final PageController _pageController = PageController();
  late final JournalViewModel _journal;
  late final PageMusicController _music;
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
    _journal = JournalViewModel(
      repository: widget.repositories.documentRepository,
      assetRepository: widget.repositories.assetRepository,
    );
    _music = PageMusicController(
      catalog: widget.musicCatalog,
      playback: widget.audioPlaybackFactory(),
      persistResolvedTrack: _persistResolvedTrack,
    );
  }

  @override
  void dispose() {
    _chromeTimer?.cancel();
    _pageController.dispose();
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

  Widget _buildEntryPage(EntryDocument document) {
    return EntryPage(
      document: document,
      editorViewModelFactory: widget.editorViewModelFactory,
      controlsVisible: _entryChromeVisible,
      active: document.id == _activeEntryId,
      musicController: _music,
      onDocumentPreviewChanged:
          widget.repositories.documentRepository.previewDocument,
      onEditingChanged: (editing) =>
          _handleEditingChanged(document.id, editing),
    );
  }

  Future<void> _persistResolvedTrack(
    String pageId,
    PageMusicTrack track,
  ) async {
    final document = widget.repositories.documentRepository.documents
        .where((candidate) => candidate.id == pageId)
        .firstOrNull;
    if (document == null) return;
    await widget.repositories.documentRepository.saveDocument(
      document.copyWith(music: track, modifiedAt: DateTime.now()),
    );
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
                          unawaited(_activateMusicForPage(page));
                        },
                        children: [
                          ContentsPage(
                            documents: _journal.documents,
                            readAsset: _journal.readAsset,
                            onOpenPage: goToEntry,
                            onNewPage: _createPage,
                            onDeletePage: _journal.deletePage,
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
