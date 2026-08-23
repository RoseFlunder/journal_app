import 'package:flutter/material.dart';

class EditorToolbar extends StatelessWidget {
  const EditorToolbar({
    super.key,
    required this.editing,
    required this.hasSelection,
    required this.textEditing,
    required this.onToggleEditing,
    required this.onAddText,
    required this.onEditTitle,
    required this.onEditText,
    required this.onDelete,
    required this.onBringToFront,
  });

  final bool editing;
  final bool hasSelection;
  final bool textEditing;
  final VoidCallback onToggleEditing;
  final VoidCallback onAddText;
  final VoidCallback onEditTitle;
  final VoidCallback onEditText;
  final VoidCallback onDelete;
  final VoidCallback onBringToFront;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: editing ? 'Finish editing' : 'Edit page',
            color: Colors.white,
            onPressed: onToggleEditing,
            icon: Icon(editing ? Icons.check : Icons.edit_outlined),
          ),
          if (editing) ...[
            IconButton(
              tooltip: 'Add text',
              color: Colors.white,
              onPressed: onAddText,
              icon: const Icon(Icons.text_fields),
            ),
            IconButton(
              tooltip: 'Edit title',
              color: Colors.white,
              onPressed: onEditTitle,
              icon: const Icon(Icons.title),
            ),
            IconButton(
              tooltip: 'Edit text',
              color: Colors.white,
              onPressed: hasSelection ? onEditText : null,
              icon: Icon(textEditing ? Icons.keyboard_hide : Icons.edit_note),
            ),
            IconButton(
              tooltip: 'Bring to front',
              color: Colors.white,
              onPressed: hasSelection ? onBringToFront : null,
              icon: const Icon(Icons.layers_outlined),
            ),
            IconButton(
              tooltip: 'Delete block',
              color: Colors.white,
              onPressed: hasSelection ? onDelete : null,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ],
      ),
    );
  }
}
