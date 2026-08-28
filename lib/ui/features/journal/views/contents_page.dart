import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../../../../models/document.dart';
import '../../../../models/sticker.dart';
import '../../../../widgets/paper_page.dart';
import '../view_models/cloud_sync_view_model.dart';
import '../../../../platform/cloud_sign_in_button.dart';

/// Botanical home/contents page. It intentionally stays focused on the
/// journal list; calendar and search are deferred.
class ContentsPage extends StatelessWidget {
  const ContentsPage({
    super.key,
    required this.documents,
    required this.readAsset,
    required this.onOpenPage,
    required this.onNewPage,
    required this.onDeletePage,
    required this.cloudSync,
  });

  final List<EntryDocument> documents;
  final Uint8List? Function(String id) readAsset;
  final ValueChanged<int> onOpenPage;
  final VoidCallback onNewPage;
  final Future<void> Function(String id) onDeletePage;
  final CloudSyncViewModel cloudSync;

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
                    child: const _WelcomeCard(),
                  ),
                ),
                const SizedBox(height: 26),
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

  ImageProvider<Object>? _preview(EntryDocument document) {
    ImageProvider<Object>? visit(Iterable<CanvasNode> nodes) {
      for (final node in nodes) {
        if (node.type.name == 'sticker') {
          final stickerId = node.payload['stickerId'];
          final sticker = stickerId is String
              ? StickerCatalog.byId(stickerId)
              : null;
          if (sticker != null) return AssetImage(sticker.assetPath);
        }
        if (node.type.name == 'image') {
          final assetId = node.payload['assetId'];
          if (assetId is String) {
            final bytes = readAsset(assetId);
            if (bytes != null) return MemoryImage(bytes);
          }
        }
        final nested = visit(node.children);
        if (nested != null) return nested;
      }
      return null;
    }

    return visit(document.nodes);
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard();

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
          padding: const EdgeInsets.fromLTRB(24, 22, 110, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cozy Bloom Journal',
                style: TextStyle(
                  fontFamily: 'Lora',
                  fontWeight: FontWeight.w700,
                  fontSize: 25,
                  color: PaperPage.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Capture little moments, cherish big memories.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                'Take a deep breath and let your thoughts bloom.',
                style: TextStyle(
                  fontFamily: 'Caveat',
                  fontSize: 22,
                  color: PaperPage.ink,
                ),
              ),
            ],
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

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.document,
    required this.index,
    required this.date,
    required this.preview,
    required this.onTap,
    required this.onDelete,
  });

  final EntryDocument document;
  final int index;
  final String date;
  final ImageProvider<Object>? preview;
  final VoidCallback onTap;
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
              width: 78,
              height: 74,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xFFF2D7D3),
                borderRadius: BorderRadius.circular(13),
              ),
              child: preview == null
                  ? const Icon(Icons.auto_awesome, color: PaperPage.margin)
                  : Padding(
                      padding: const EdgeInsets.all(7),
                      child: Image(image: preview!, fit: BoxFit.contain),
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
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete page',
              onPressed: onDelete,
            ),
            Text(
              '${index + 1}',
              style: TextStyle(
                fontFamily: 'Lora',
                color: PaperPage.ink.withValues(alpha: 0.45),
              ),
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
          final busy = state.phase == CloudSyncPhase.signingIn ||
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
                      state.error.toString(),
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (state.phase == CloudSyncPhase.signedOut)
                    ...[
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
                    ]
                  else if (state.phase == CloudSyncPhase.authorizationRequired)
                    ...[
                      FilledButton.icon(
                        onPressed: () => viewModel.reconnect(),
                        icon: const Icon(Icons.lock_open),
                        label: const Text('Reconnect'),
                      ),
                      _resetButton(context),
                    ]
                  else ...[
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
