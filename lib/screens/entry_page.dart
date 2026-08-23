import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/entry.dart';

/// Shows one [Entry] as a journal page.
///
/// M1: read-only placeholder page with title + date. Free-positioned
/// content blocks arrive in later milestones (see PLAN.md).
class EntryPage extends StatelessWidget {
  const EntryPage({
    super.key,
    required this.entry,
    required this.index,
    required this.total,
    required this.onContents,
    required this.onPrev,
    required this.onNext,
  });

  /// Index of this entry within the journal (0-based).
  final Entry entry;
  final int index;
  final int total;

  final VoidCallback onContents;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final hasContent = entry.blocks.isNotEmpty;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Navigation row (desktop/web affordance).
              Row(
                children: [
                  TextButton.icon(
                    onPressed: onContents,
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('Contents'),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Previous page (PageUp / \u2190)',
                    onPressed: onPrev,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    tooltip: 'Next page (PageDown / \u2192)',
                    onPressed: index + 1 < total ? onNext : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              Text(
                entry.title.isEmpty ? 'Untitled page' : entry.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat.yMMMMd().format(entry.createdAt),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Colors.black54),
              ),
              const Divider(height: 24),
              Expanded(
                child: Center(
                  child: Text(
                    hasContent
                        ? '${entry.blocks.length} content block(s) — rendering arrives in a later milestone.'
                        : 'This page is empty.\nText boxes, pictures and music arrive in later milestones.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: Colors.black38),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
