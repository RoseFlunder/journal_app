import 'package:flutter/material.dart';

class EditorToolbar extends StatelessWidget {
  const EditorToolbar({
    super.key,
    required this.editing,
    required this.hasSelection,
    required this.textEditing,
    required this.onToggleEditing,
    required this.onAddText,
    required this.onAddImage,
    required this.onAddSticker,
    required this.onMore,
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
  final VoidCallback onAddImage;
  final VoidCallback onAddSticker;
  final VoidCallback onMore;
  final VoidCallback onEditTitle;
  final VoidCallback onEditText;
  final VoidCallback onDelete;
  final VoidCallback onBringToFront;

  @override
  Widget build(BuildContext context) {
    if (!editing) {
      return _Shell(
        child: _Action(
          tooltip: 'Edit page',
          icon: Icons.edit_outlined,
          label: 'Edit',
          onPressed: onToggleEditing,
        ),
      );
    }

    return _Shell(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = MediaQuery.sizeOf(context).width < 600;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Action(
                tooltip: 'Finish editing',
                icon: Icons.check,
                label: compact ? null : 'Done',
                onPressed: onToggleEditing,
              ),
              _divider(),
              _Action(
                tooltip: 'Add text',
                icon: Icons.text_fields,
                label: compact ? null : 'Text',
                onPressed: onAddText,
              ),
              _Action(
                tooltip: 'Add image',
                icon: Icons.photo_outlined,
                label: compact ? null : 'Photo',
                onPressed: onAddImage,
              ),
              _Action(
                tooltip: 'Add sticker',
                icon: Icons.emoji_emotions_outlined,
                label: compact ? null : 'Sticker',
                onPressed: onAddSticker,
              ),
              _Action(
                tooltip: 'More editing tools',
                icon: Icons.more_horiz,
                label: compact ? null : 'More',
                onPressed: onMore,
              ),
              _Action(
                tooltip: 'Edit title',
                icon: Icons.title,
                label: null,
                onPressed: onEditTitle,
              ),
              if (hasSelection) ...[
                _divider(),
                _Action(
                  tooltip: 'Edit text',
                  icon: textEditing ? Icons.keyboard_hide : Icons.edit_note,
                  label: null,
                  onPressed: onEditText,
                ),
                _Action(
                  tooltip: 'Bring to front',
                  icon: Icons.layers_outlined,
                  label: null,
                  onPressed: onBringToFront,
                ),
                _Action(
                  tooltip: 'Delete block',
                  icon: Icons.delete_outline,
                  label: null,
                  onPressed: onDelete,
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _divider() => Container(
    width: 1,
    height: 28,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: Colors.black.withValues(alpha: 0.14),
  );
}

class _Shell extends StatelessWidget {
  const _Shell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext _) => Material(
    color: const Color(0xFFF4EDDC).withValues(alpha: 0.96),
    elevation: 5,
    shadowColor: const Color(0xFF3B3226).withValues(alpha: 0.18),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: BorderSide(color: const Color(0xFF3B3226).withValues(alpha: 0.13)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: child,
    ),
  );
}

class _Action extends StatelessWidget {
  const _Action({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.label,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final String? label;

  @override
  Widget build(BuildContext _) {
    final child = label == null
        ? IconButton(
            tooltip: tooltip,
            onPressed: onPressed,
            icon: Icon(icon, color: const Color(0xFF3B3226)),
          )
        : InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: const Color(0xFF3B3226)),
                  Text(
                    label!,
                    style: const TextStyle(
                      fontFamily: 'Lora',
                      fontSize: 9,
                      color: Color(0xFF3B3226),
                    ),
                  ),
                ],
              ),
            ),
          );
    final semanticChild = Semantics(button: true, label: tooltip, child: child);
    return label == null
        ? semanticChild
        : Tooltip(message: tooltip, child: semanticChild);
  }
}
