import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../models/document.dart';

/// Layers sheet for the editor. It receives an immutable structural node
/// projection and emits layer intents; repository and controller state stay in
/// the feature view model.
class EditorLayersView extends StatelessWidget {
  const EditorLayersView({
    super.key,
    required this.nodes,
    required this.selectedId,
    required this.onSelect,
    required this.onToggleHidden,
    required this.onToggleLocked,
    required this.onReorder,
    required this.onMoveForward,
    required this.onMoveBackward,
    required this.onRename,
  });

  final List<CanvasNode> nodes;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onToggleHidden;
  final ValueChanged<String> onToggleLocked;
  final void Function(String id, int targetIndex) onReorder;
  final ValueChanged<String> onMoveForward;
  final ValueChanged<String> onMoveBackward;
  final Future<void> Function(String id, String name) onRename;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.62,
      child: Column(
        children: [
          const ListTile(
            leading: Icon(Icons.layers_outlined),
            title: Text('Layers'),
            subtitle: Text('Top layers appear first'),
          ),
          const Divider(height: 1),
          Expanded(
            child: ReorderableListView.builder(
              itemCount: nodes.length,
              onReorderItem: (oldIndex, newIndex) {
                final visible = nodes.reversed.toList(growable: false);
                if (oldIndex < 0 || oldIndex >= visible.length) return;
                final targetIndex = (nodes.length - newIndex - 1).clamp(
                  0,
                  nodes.length,
                );
                onReorder(visible[oldIndex].id, targetIndex);
              },
              itemBuilder: (context, index) {
                final node = nodes[nodes.length - index - 1];
                final selected = selectedId == node.id;
                final label = node.name ?? _nodeLabel(node);
                return ListTile(
                  key: ValueKey('layer-${node.id}'),
                  contentPadding: EdgeInsets.only(
                    left: node.groupId == null ? 16 : 40,
                    right: 8,
                  ),
                  selected: selected,
                  leading: Icon(_nodeIcon(node.type)),
                  title: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: node.hidden ? 'Show layer' : 'Hide layer',
                        onPressed: () => onToggleHidden(node.id),
                        icon: Icon(
                          node.hidden
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                      ),
                      IconButton(
                        tooltip: node.locked ? 'Unlock layer' : 'Lock layer',
                        onPressed: () => onToggleLocked(node.id),
                        icon: Icon(
                          node.locked ? Icons.lock : Icons.lock_open_outlined,
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Layer actions',
                        onSelected: (action) {
                          switch (action) {
                            case 'rename':
                              unawaited(_promptRename(context, node));
                            case 'forward':
                              onMoveForward(node.id);
                            case 'backward':
                              onMoveBackward(node.id);
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'rename',
                            child: Text('Rename layer'),
                          ),
                          PopupMenuItem(
                            value: 'forward',
                            child: Text('Bring forward'),
                          ),
                          PopupMenuItem(
                            value: 'backward',
                            child: Text('Send backward'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  onTap: () {
                    onSelect(node.id);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _promptRename(BuildContext context, CanvasNode node) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameLayerDialog(initial: node.name ?? ''),
    );
    if (context.mounted && name != null) await onRename(node.id, name);
  }

}

String _nodeLabel(CanvasNode node) => switch (node.type) {
  BlockType.text => node.text.isEmpty ? 'Text' : node.text.split('\n').first,
  BlockType.image => 'Photo',
  BlockType.sticker => 'Sticker',
  BlockType.ink => 'Drawing',
  BlockType.shape => 'Shape',
  BlockType.group => 'Group',
};

IconData _nodeIcon(BlockType type) => switch (type) {
  BlockType.text => Icons.text_fields,
  BlockType.image => Icons.photo_outlined,
  BlockType.sticker => Icons.emoji_emotions_outlined,
  BlockType.ink => Icons.draw_outlined,
  BlockType.shape => Icons.category_outlined,
  BlockType.group => Icons.folder_copy_outlined,
};

class _RenameLayerDialog extends StatefulWidget {
  const _RenameLayerDialog({this.initial = ''});

  final String initial;

  @override
  State<_RenameLayerDialog> createState() => _RenameLayerDialogState();
}

class _RenameLayerDialogState extends State<_RenameLayerDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename layer'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      textInputAction: TextInputAction.done,
      onSubmitted: (value) => Navigator.pop(context, value),
      decoration: const InputDecoration(labelText: 'Layer name'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('Rename'),
      ),
    ],
  );
}
