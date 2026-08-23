import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/entry.dart';
import '../services/journal_store.dart';
import '../widgets/paper_page.dart';

/// The table of contents: lists all pages with title and creation date,
/// tapping a row jumps to that page.
class ContentsPage extends StatelessWidget {
  const ContentsPage({
    super.key,
    required this.store,
    required this.onOpenPage,
    required this.onNewPage,
  });

  final JournalStore store;
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
      store.deleteEntry(entry.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = store.entries;
    final dateFormat = DateFormat.yMMMMd();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Journal',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        actions: [
          IconButton(
            onPressed: onNewPage,
            tooltip: 'New page',
            icon: const Icon(Icons.note_add_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: PaperPage.margin,
        foregroundColor: Colors.white,
        onPressed: onNewPage,
        icon: const Icon(Icons.add),
        label: const Text('New page'),
      ),
      body: PaperPage(
        child: entries.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.menu_book_outlined,
                        size: 56,
                        color: Colors.black38,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'This journal is empty.',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Create your first page to start writing.',
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(48, 18, 24, 96),
                itemCount: entries.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  color: PaperPage.ink.withValues(alpha: 0.14),
                ),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: PaperPage.margin,
                      foregroundColor: Colors.white,
                      child: Text('${index + 1}'),
                    ),
                    title: Text(
                      entry.title.isEmpty ? 'Untitled page' : entry.title,
                    ),
                    subtitle: Text(dateFormat.format(entry.createdAt)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete page',
                      onPressed: () => _confirmDelete(context, entry),
                    ),
                    onTap: () => onOpenPage(index),
                  );
                },
              ),
      ),
    );
  }
}
