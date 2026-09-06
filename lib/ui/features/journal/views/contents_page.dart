import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../models/document.dart';
import '../../../../widgets/paper_page.dart';
import '../view_models/cloud_sync_view_model.dart';
import '../../../../platform/cloud_sign_in_button.dart';

/// Botanical home/contents page. It intentionally stays focused on the
/// journal list; calendar and search are deferred.
class ContentsPage extends StatefulWidget {
  const ContentsPage({
    super.key,
    required this.documents,
    required this.readAsset,
    required this.onOpenPage,
    required this.onNewPage,
    required this.onRenamePage,
    required this.onDeletePage,
    required this.cloudSync,
  });

  final List<EntryDocument> documents;
  final Uint8List? Function(String id) readAsset;
  final ValueChanged<int> onOpenPage;
  final VoidCallback onNewPage;
  final Future<void> Function(String id, String title) onRenamePage;
  final Future<void> Function(String id) onDeletePage;
  final CloudSyncViewModel cloudSync;

  @override
  State<ContentsPage> createState() => _ContentsPageState();
}

class _ContentsPageState extends State<ContentsPage> {
  final Map<String, ImageProvider<Object>> _previewProviders =
      <String, ImageProvider<Object>>{};

  List<EntryDocument> get documents => widget.documents;
  Uint8List? Function(String id) get readAsset => widget.readAsset;
  ValueChanged<int> get onOpenPage => widget.onOpenPage;
  VoidCallback get onNewPage => widget.onNewPage;
  Future<void> Function(String id, String title) get onRenamePage =>
      widget.onRenamePage;
  Future<void> Function(String id) get onDeletePage => widget.onDeletePage;
  CloudSyncViewModel get cloudSync => widget.cloudSync;
  late final Future<_WelcomeMessage> _welcomeMessage = _loadWelcomeMessage();

  Future<void> _confirmDelete(
    BuildContext context,
    EntryDocument document,
  ) async {
    final title = document.title.isEmpty ? 'Untitled page' : document.title;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete page?'),
        content: Text(
          '“$title” and everything on it will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await onDeletePage(document.id);
    }
  }

  Future<void> _renamePage(
    BuildContext context,
    EntryDocument document,
  ) async {
    final title = await showDialog<String>(
      context: context,
      builder: (context) => _RenamePageDialog(initialTitle: document.title),
    );
    if (title != null && context.mounted) {
      await onRenamePage(document.id, title);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat.yMMMMd();

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(9),
          child: Image.asset('assets/branding/cozy_bloom_icon.png'),
        ),
        title: Text(
          'Cozy Bloom Journal',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        actions: [
          _CloudSyncAction(viewModel: cloudSync),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: PaperPage.sage,
        foregroundColor: PaperPage.ink,
        onPressed: onNewPage,
        icon: const Icon(Icons.add),
        label: const Text('New page'),
      ),
      body: PaperPage(
        showRules: false,
        showMargin: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            return ListView(
              padding: EdgeInsets.fromLTRB(
                wide ? 72 : 22,
                24,
                wide ? 72 : 22,
                110,
              ),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: _WelcomeCard(message: _welcomeMessage),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'My Journals',
                            style: TextStyle(
                              fontFamily: 'Lora',
                              fontWeight: FontWeight.w700,
                              fontSize: 20,
                              color: PaperPage.ink,
                            ),
                          ),
                        ),
                        Text(
                          '${documents.length} ${documents.length == 1 ? 'page' : 'pages'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (documents.isEmpty)
                  const Center(child: _EmptyJournal())
                else
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Column(
                        children: [
                          for (var index = 0; index < documents.length; index++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _EntryCard(
                                document: documents[index],
                                index: index,
                                date: dateFormat.format(
                                  documents[index].createdAt,
                                ),
                                preview: _preview(documents[index]),
                                onTap: () => onOpenPage(index),
                                onRename: () =>
                                    _renamePage(context, documents[index]),
                                onDelete: () =>
                                    _confirmDelete(context, documents[index]),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<_WelcomeMessage> _loadWelcomeMessage() async {
    try {
      final source = await rootBundle.loadString(
        'assets/content/welcome_messages.json',
      );
      final decoded = jsonDecode(source);
      if (decoded is! List) return _WelcomeMessage.fallback;
      final messages = decoded
          .whereType<Map<Object?, Object?>>()
          .map(_WelcomeMessage.fromJson)
          .where((message) => message.isValid)
          .toList(growable: false);
      if (messages.isEmpty) return _WelcomeMessage.fallback;
      return messages[math.Random().nextInt(messages.length)];
    } catch (_) {
      return _WelcomeMessage.fallback;
    }
  }

  ImageProvider<Object>? _preview(EntryDocument document) {
    ImageProvider<Object>? providerFor(CanvasNode node) {
      if (node.type != BlockType.image) return null;
      final assetId = node.assetId;
      if (assetId == null) return null;
      final cached = _previewProviders[assetId];
      if (cached != null) return cached;
      final bytes = readAsset(assetId);
      if (bytes == null) return null;
      return _previewProviders[assetId] = ResizeImage(
        MemoryImage(bytes),
        width: 160,
        height: 160,
        policy: ResizeImagePolicy.fit,
      );
    }

    final selectedId = document.previewImageNodeId;
    if (selectedId != null) {
      final selected = document.nodeById(selectedId);
      if (selected != null) {
        final provider = providerFor(selected);
        if (provider != null) return provider;
      }
    }

    ImageProvider<Object>? visit(Iterable<CanvasNode> nodes) {
      for (final node in nodes) {
        final provider = providerFor(node);
        if (provider != null) return provider;
        final nested = visit(node.children);
        if (nested != null) return nested;
      }
      return null;
    }

    return visit(document.nodes);
  }
}

class _WelcomeMessage {
  const _WelcomeMessage({required this.message, required this.reflection});

  static const fallback = _WelcomeMessage(
    message: 'Capture little moments, cherish big memories.',
    reflection: 'Take a deep breath and let your thoughts bloom.',
  );

  factory _WelcomeMessage.fromJson(Map<Object?, Object?> json) =>
      _WelcomeMessage(
        message: json['message'] is String ? json['message'] as String : '',
        reflection: json['reflection'] is String
            ? json['reflection'] as String
            : '',
      );

  final String message;
  final String reflection;

  bool get isValid => message.trim().isNotEmpty && reflection.trim().isNotEmpty;
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.message});

  final Future<_WelcomeMessage> message;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFFE4EBDD),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: PaperPage.sage.withValues(alpha: 0.45)),
      boxShadow: [
        BoxShadow(
          color: PaperPage.ink.withValues(alpha: 0.08),
          blurRadius: 16,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Stack(
      children: [
        Positioned(
          right: -12,
          bottom: -18,
          width: 138,
          height: 138,
          child: Opacity(
            opacity: 0.18,
            child: Image.asset('assets/stickers/daisy.png'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 100, 16),
          child: FutureBuilder<_WelcomeMessage>(
            future: message,
            initialData: _WelcomeMessage.fallback,
            builder: (context, snapshot) {
              final welcome = snapshot.data ?? _WelcomeMessage.fallback;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    welcome.message,
                    key: const ValueKey('welcome-message'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    welcome.reflection,
                    key: const ValueKey('welcome-reflection'),
                    style: const TextStyle(
                      fontFamily: 'Caveat',
                      fontSize: 18,
                      color: PaperPage.ink,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _EmptyJournal extends StatelessWidget {
  const _EmptyJournal();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('assets/stickers/daisy.png', width: 82, height: 82),
        const SizedBox(height: 12),
        Text(
          'This journal is empty.',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'Create your first page to start writing.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: PaperPage.ink.withValues(alpha: 0.68)),
        ),
      ],
    ),
  );
}

class _RenamePageDialog extends StatefulWidget {
  const _RenamePageDialog({required this.initialTitle});

  final String initialTitle;

  @override
  State<_RenamePageDialog> createState() => _RenamePageDialogState();
}

class _RenamePageDialogState extends State<_RenamePageDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialTitle,
  );

  bool get _canRename => _controller.text.trim().isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_canRename) Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename page'),
    content: TextField(
      key: const ValueKey('rename-page-title'),
      controller: _controller,
      autofocus: true,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.done,
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _submit(),
      decoration: const InputDecoration(labelText: 'Page title'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _canRename ? _submit : null,
        child: const Text('Rename'),
      ),
    ],
  );
}

enum _PageCardAction { rename, delete }

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.document,
    required this.index,
    required this.date,
    required this.preview,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final EntryDocument document;
  final int index;
  final String date;
  final ImageProvider<Object>? preview;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFFFFBF4),
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Container(
              key: ValueKey('page-preview-${document.id}'),
              width: 78,
              height: 74,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: preview == null ? const Color(0xFFF2D7D3) : Colors.white,
                borderRadius: BorderRadius.circular(13),
              ),
              child: preview == null
                  ? const Icon(Icons.auto_awesome, color: PaperPage.margin)
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(7),
                        child: SizedBox.expand(
                          child: Image(
                            key: ValueKey('page-preview-image-${document.id}'),
                            image: preview!,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    document.title.isEmpty ? 'Untitled page' : document.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(date, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Text(
              '${index + 1}',
              style: TextStyle(
                fontFamily: 'Lora',
                color: PaperPage.ink.withValues(alpha: 0.45),
              ),
            ),
            PopupMenuButton<_PageCardAction>(
              tooltip: 'Page actions',
              onSelected: (action) => switch (action) {
                _PageCardAction.rename => onRename(),
                _PageCardAction.delete => onDelete(),
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _PageCardAction.rename,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Rename page'),
                  ),
                ),
                PopupMenuItem(
                  value: _PageCardAction.delete,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.delete_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: Text(
                      'Delete page',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              ],
              icon: const Icon(Icons.more_vert),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CloudSyncAction extends StatelessWidget {
  const _CloudSyncAction({required this.viewModel});

  final CloudSyncViewModel viewModel;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: viewModel,
    builder: (context, _) {
      final state = viewModel.state;
      if (state.phase == CloudSyncPhase.disabled) {
        return const SizedBox.shrink();
      }
      final busy =
          state.phase == CloudSyncPhase.signingIn ||
          state.phase == CloudSyncPhase.initialSync ||
          state.phase == CloudSyncPhase.syncing;
      return IconButton(
        tooltip: _tooltip(state.phase),
        onPressed: busy || state.phase == CloudSyncPhase.disabled
            ? null
            : () => _openPanel(context),
        icon: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(_icon(state.phase)),
      );
    },
  );

  Future<void> _openPanel(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => _CloudSyncPanel(viewModel: viewModel),
    );
  }

  static IconData _icon(CloudSyncPhase phase) => switch (phase) {
    CloudSyncPhase.disabled => Icons.cloud_off_outlined,
    CloudSyncPhase.signedOut => Icons.cloud_outlined,
    CloudSyncPhase.signingIn => Icons.cloud_outlined,
    CloudSyncPhase.initialSync => Icons.cloud_sync_outlined,
    CloudSyncPhase.syncing => Icons.cloud_sync_outlined,
    CloudSyncPhase.synced => Icons.cloud_done_outlined,
    CloudSyncPhase.offline => Icons.cloud_off_outlined,
    CloudSyncPhase.authorizationRequired => Icons.lock_clock_outlined,
    CloudSyncPhase.failed => Icons.cloud_off_outlined,
  };

  static String _tooltip(CloudSyncPhase phase) => switch (phase) {
    CloudSyncPhase.disabled => 'Cloud sync is not configured',
    CloudSyncPhase.signedOut => 'Connect Google Drive',
    CloudSyncPhase.signingIn => 'Connecting Google Drive',
    CloudSyncPhase.initialSync => 'Syncing journal',
    CloudSyncPhase.syncing => 'Syncing journal',
    CloudSyncPhase.synced => 'Google Drive synced',
    CloudSyncPhase.offline => 'Sync offline — tap to retry',
    CloudSyncPhase.authorizationRequired => 'Reconnect Google Drive',
    CloudSyncPhase.failed => 'Sync failed — tap for details',
  };
}

class _CloudSyncPanel extends StatelessWidget {
  const _CloudSyncPanel({required this.viewModel});

  final CloudSyncViewModel viewModel;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) {
          final state = viewModel.state;
          final account = state.account;
          final label = account == null
              ? 'Not connected'
              : account.email.isEmpty
              ? 'Google Drive connected'
              : account.email;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cloud sync', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(label),
              const SizedBox(height: 8),
              if (state.lastSyncedAt != null)
                Text(
                  'Last synced ${DateFormat.Hm().format(state.lastSyncedAt!.toLocal())}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (state.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  cloudSyncErrorMessage(state.error),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              if (state.phase == CloudSyncPhase.signedOut) ...[
                kIsWeb
                    ? buildCloudSignInButton()
                    : FilledButton.icon(
                        onPressed: () async {
                          await viewModel.connect();
                          if (context.mounted) Navigator.pop(context);
                        },
                        icon: const Icon(Icons.login),
                        label: const Text('Connect Google Drive'),
                      ),
                _resetButton(context),
              ] else if (state.phase ==
                  CloudSyncPhase.authorizationRequired) ...[
                FilledButton.icon(
                  onPressed: () => viewModel.reconnect(),
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Enable Google Drive sync'),
                ),
                _resetButton(context),
              ] else ...[
                FilledButton.icon(
                  onPressed: () => viewModel.syncNow(),
                  icon: const Icon(Icons.sync),
                  label: const Text('Sync now'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () async {
                    await viewModel.signOut();
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Sign out (keep local pages)'),
                ),
                TextButton(
                  onPressed: () => _confirmReset(context),
                  child: const Text('Reset this device for another account'),
                ),
              ],
            ],
          );
        },
      ),
    ),
  );

  Future<void> _confirmReset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset this device?'),
        content: const Text(
          'This removes local pages, images, and the account link. Google Drive data is not deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await viewModel.resetLocalData();
      if (context.mounted) Navigator.pop(context);
    }
  }

  Widget _resetButton(BuildContext context) => TextButton(
    onPressed: () => _confirmReset(context),
    child: const Text('Reset this device for another account'),
  );
}
