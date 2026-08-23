import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/entry.dart';
import 'paper_page.dart';

class JournalNavigationDrawer extends StatelessWidget {
  const JournalNavigationDrawer({
    super.key,
    required this.entries,
    required this.currentEntryIndex,
    required this.onOpenContents,
    required this.onOpenEntry,
    required this.onNewPage,
  });

  final List<Entry> entries;
  final int currentEntryIndex;
  final VoidCallback onOpenContents;
  final ValueChanged<int> onOpenEntry;
  final VoidCallback onNewPage;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat.yMMMMd();

    return Drawer(
      backgroundColor: PaperPage.paper,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Journal',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close navigation',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('Contents'),
              selected: currentEntryIndex < 0,
              onTap: onOpenContents,
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: entries.length,
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(dateFormat.format(entry.createdAt)),
                    selected: index == currentEntryIndex,
                    onTap: () => onOpenEntry(index),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: onNewPage,
                icon: const Icon(Icons.add),
                label: const Text('New page'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}