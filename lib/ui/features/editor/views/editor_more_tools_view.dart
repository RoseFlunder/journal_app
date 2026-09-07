import 'package:flutter/material.dart';

/// Presentation for the editor's secondary actions.
///
/// The view receives a snapshot of editor state and emits intents. It does
/// not know about repositories, persistence, or the controller that handles
/// those intents.
class EditorMoreToolsView extends StatefulWidget {
  const EditorMoreToolsView({
    super.key,
    required this.canUndo,
    required this.canRedo,
    required this.canGroup,
    required this.canUngroup,
    required this.hasMusic,
    required this.selectMode,
    required this.drawMode,
    required this.onUndo,
    required this.onRedo,
    required this.onShare,
    required this.onGroup,
    required this.onUngroup,
    required this.onToggleSelectMode,
    required this.onToggleDrawMode,
    required this.onMusic,
    required this.onLayers,
  });

  final bool canUndo;
  final bool canRedo;
  final bool canGroup;
  final bool canUngroup;
  final bool hasMusic;
  final bool selectMode;
  final bool drawMode;

  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onShare;
  final VoidCallback onGroup;
  final VoidCallback onUngroup;
  final VoidCallback onToggleSelectMode;
  final VoidCallback onToggleDrawMode;
  final VoidCallback onMusic;
  final VoidCallback onLayers;

  @override
  State<EditorMoreToolsView> createState() => _EditorMoreToolsViewState();
}

class _EditorMoreToolsViewState extends State<EditorMoreToolsView> {
  late final bool _selectMode = widget.selectMode;
  late final bool _drawMode = widget.drawMode;

  void _close(VoidCallback action) {
    Navigator.pop(context);
    action();
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.72,
    minChildSize: 0.35,
    maxChildSize: 0.94,
    builder: (context, scrollController) => SafeArea(
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          ListTile(
            leading: const Icon(Icons.undo),
            title: const Text('Undo'),
            enabled: widget.canUndo,
            onTap: widget.canUndo ? () => _close(widget.onUndo) : null,
          ),
          ListTile(
            leading: const Icon(Icons.redo),
            title: const Text('Redo'),
            enabled: widget.canRedo,
            onTap: widget.canRedo ? () => _close(widget.onRedo) : null,
          ),
          ListTile(
            leading: Icon(_drawMode ? Icons.draw : Icons.draw_outlined),
            title: Text(_drawMode ? 'Exit draw mode' : 'Draw'),
            subtitle: const Text('Draw a vector ink stroke on the board'),
            onTap: () => _close(widget.onToggleDrawMode),
          ),
          ListTile(
            key: const ValueKey('page-music-tool'),
            leading: const Icon(Icons.library_music_outlined),
            title: Text(
              widget.hasMusic ? 'Change page music' : 'Add page music',
            ),
            subtitle: const Text('Stream Creative Commons music from Jamendo'),
            onTap: () => _close(widget.onMusic),
          ),
          ListTile(
            leading: const Icon(Icons.layers_outlined),
            title: const Text('Layers'),
            subtitle: const Text('Reorder, show, hide, and lock content'),
            onTap: () => _close(widget.onLayers),
          ),
          ListTile(
            leading: Icon(
              _selectMode ? Icons.select_all : Icons.select_all_outlined,
            ),
            title: Text(_selectMode ? 'Exit select mode' : 'Select multiple'),
            subtitle: const Text('Drag blank board space to lasso content'),
            onTap: () => _close(widget.onToggleSelectMode),
          ),
          ListTile(
            leading: const Icon(Icons.group_work_outlined),
            title: const Text('Group selection'),
            subtitle: const Text('Keep selected objects together'),
            enabled: widget.canGroup,
            onTap: widget.canGroup ? () => _close(widget.onGroup) : null,
          ),
          ListTile(
            leading: const Icon(Icons.group_off_outlined),
            title: const Text('Ungroup selection'),
            enabled: widget.canUngroup,
            onTap: widget.canUngroup ? () => _close(widget.onUngroup) : null,
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: const Text('Share'),
            subtitle: const Text('Send or save an editable copy of this page'),
            onTap: () => _close(widget.onShare),
          ),
        ],
      ),
    ),
  );
}
