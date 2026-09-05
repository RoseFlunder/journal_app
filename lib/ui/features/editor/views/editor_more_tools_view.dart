import 'package:flutter/material.dart';

import '../../../../models/document.dart';

/// Presentation for the editor's secondary actions.
///
/// The view receives a snapshot of editor state and emits intents. It does
/// not know about repositories, persistence, or the controller that handles
/// those intents.
class EditorMoreToolsView extends StatefulWidget {
  const EditorMoreToolsView({
    super.key,
    required this.board,
    required this.canUndo,
    required this.canRedo,
    required this.canGroup,
    required this.canUngroup,
    required this.hasMusic,
    required this.selectMode,
    required this.drawMode,
    required this.onUndo,
    required this.onRedo,
    required this.onExportArchive,
    required this.onImportArchive,
    required this.onGroup,
    required this.onUngroup,
    required this.onToggleSelectMode,
    required this.onToggleDrawMode,
    required this.onInkSettings,
    required this.onMusic,
    required this.onLayers,
    required this.onHistory,
    required this.onSnapToGridChanged,
    required this.onGridVisibilityChanged,
  });

  final BoardSettings board;
  final bool canUndo;
  final bool canRedo;
  final bool canGroup;
  final bool canUngroup;
  final bool hasMusic;
  final bool selectMode;
  final bool drawMode;

  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onExportArchive;
  final VoidCallback onImportArchive;
  final VoidCallback onGroup;
  final VoidCallback onUngroup;
  final VoidCallback onToggleSelectMode;
  final VoidCallback onToggleDrawMode;
  final VoidCallback onInkSettings;
  final VoidCallback onMusic;
  final VoidCallback onLayers;
  final VoidCallback onHistory;
  final ValueChanged<bool> onSnapToGridChanged;
  final ValueChanged<bool> onGridVisibilityChanged;

  @override
  State<EditorMoreToolsView> createState() => _EditorMoreToolsViewState();
}

class _EditorMoreToolsViewState extends State<EditorMoreToolsView> {
  late final bool _selectMode = widget.selectMode;
  late final bool _drawMode = widget.drawMode;
  late bool _snapToGrid = widget.board.snapToGrid;
  late bool _gridVisible = widget.board.gridVisible;

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
          if (_drawMode)
            ListTile(
              key: const ValueKey('ink-settings'),
              leading: const Icon(Icons.tune),
              title: const Text('Ink settings'),
              subtitle: const Text('Color, width, and opacity'),
              onTap: () => _close(widget.onInkSettings),
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
          SwitchListTile(
            secondary: const Icon(Icons.grid_4x4_outlined),
            title: const Text('Snap to grid'),
            value: _snapToGrid,
            onChanged: (value) {
              setState(() => _snapToGrid = value);
              widget.onSnapToGridChanged(value);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.grid_on_outlined),
            title: const Text('Show grid'),
            value: _gridVisible,
            onChanged: (value) {
              setState(() => _gridVisible = value);
              widget.onGridVisibilityChanged(value);
            },
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('History and Recovery'),
            onTap: () => _close(widget.onHistory),
          ),
          ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: const Text('Export'),
            subtitle: const Text('Save a .cozyjournal backup'),
            onTap: () => _close(widget.onExportArchive),
          ),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('Import'),
            subtitle: const Text('Open a .cozyjournal backup'),
            onTap: () => _close(widget.onImportArchive),
          ),
        ],
      ),
    ),
  );
}
