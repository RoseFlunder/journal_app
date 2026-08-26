import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/entry.dart';
import '../models/sticker.dart';
import '../services/repositories.dart';
import '../widgets/paper_page.dart';

/// Botanical home/contents page. It intentionally stays focused on the
/// journal list; calendar and search are deferred.
class ContentsPage extends StatelessWidget {
  const ContentsPage({
    super.key,
    required this.repository,
    required this.onOpenPage,
    required this.onNewPage,
  });

  final JournalRepository repository;
  final ValueChanged<int> onOpenPage;
  final VoidCallback onNewPage;

  Future<void> _confirmDelete(BuildContext context, Entry entry) async {
    final title = entry.title.isEmpty ? 'Untitled page' : entry.title;
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
      await repository.deleteDocument(entry.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = repository.documents
        .map((document) => document.toEntry())
        .toList();
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
                          '${entries.length} ${entries.length == 1 ? 'page' : 'pages'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (entries.isEmpty)
                  const Center(child: _EmptyJournal())
                else
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Column(
                        children: [
                          for (var index = 0; index < entries.length; index++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _EntryCard(
                                entry: entries[index],
                                index: index,
                                date: dateFormat.format(
                                  entries[index].createdAt,
                                ),
                                preview: _preview(entries[index]),
                                onTap: () => onOpenPage(index),
                                onDelete: () =>
                                    _confirmDelete(context, entries[index]),
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

  ImageProvider<Object>? _preview(Entry entry) {
    for (final block in entry.blocks) {
      if (block.type == BlockType.sticker) {
        final sticker = StickerCatalog.byId(block.stickerId);
        if (sticker != null) return AssetImage(sticker.assetPath);
      }
      if (block.type == BlockType.image && block.assetId != null) {
        final bytes = repository.readAsset(block.assetId!);
        if (bytes != null) return MemoryImage(bytes);
      }
    }
    return null;
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
    required this.entry,
    required this.index,
    required this.date,
    required this.preview,
    required this.onTap,
    required this.onDelete,
  });

  final Entry entry;
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
                    entry.title.isEmpty ? 'Untitled page' : entry.title,
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
