import 'package:flutter/material.dart';

import '../models/entry.dart';

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
    required this.onEditText,
    required this.onDecreaseFontSize,
    required this.onIncreaseFontSize,
    required this.fontFamily,
    required this.onFontFamilyChanged,
    required this.onToggleBold,
    required this.onToggleItalic,
    required this.bold,
    required this.italic,
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
  final VoidCallback onEditText;
  final VoidCallback? onDecreaseFontSize;
  final VoidCallback? onIncreaseFontSize;
  final String? fontFamily;
  final ValueChanged<String?> onFontFamilyChanged;
  final VoidCallback onToggleBold;
  final VoidCallback onToggleItalic;
  final bool bold;
  final bool italic;
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
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
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
                _FontPicker(
                  compact: compact,
                  fontFamily: fontFamily,
                  onChanged: onFontFamilyChanged,
                ),
                _Action(
                  tooltip: 'Decrease font size',
                  icon: Icons.text_decrease,
                  label: null,
                  onPressed: onDecreaseFontSize,
                ),
                _Action(
                  tooltip: 'Increase font size',
                  icon: Icons.text_increase,
                  label: null,
                  onPressed: onIncreaseFontSize,
                ),
                _Action(
                  tooltip: 'Toggle bold',
                  icon: Icons.format_bold,
                  label: null,
                  onPressed: onToggleBold,
                  selected: bold,
                ),
                _Action(
                  tooltip: 'Toggle italic',
                  icon: Icons.format_italic,
                  label: null,
                  onPressed: onToggleItalic,
                  selected: italic,
                ),
                _Action(
                  tooltip: 'More editing tools',
                  icon: Icons.more_horiz,
                  label: compact ? null : 'More',
                  onPressed: onMore,
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
            ),
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

class _FontPicker extends StatelessWidget {
  const _FontPicker({
    required this.compact,
    required this.fontFamily,
    required this.onChanged,
  });

  static const _defaultKey = '__default__';

  final bool compact;
  final String? fontFamily;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Choose font',
    child: PopupMenuButton<String>(
      onSelected: (value) => onChanged(value == _defaultKey ? null : value),
      itemBuilder: (context) => [
        _item(context, _defaultKey, 'Default', null),
        _item(
          context,
          JournalFonts.caveat,
          JournalFonts.caveat,
          JournalFonts.caveat,
        ),
        _item(context, JournalFonts.lora, JournalFonts.lora, JournalFonts.lora),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.font_download_outlined, size: 20),
            Text(
              compact ? '' : 'Font',
              style: const TextStyle(
                fontFamily: 'Lora',
                fontSize: 9,
                color: Color(0xFF3B3226),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  PopupMenuItem<String> _item(
    BuildContext context,
    String value,
    String label,
    String? family,
  ) {
    final selected = family == fontFamily;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: selected ? const Icon(Icons.check, size: 18) : null,
          ),
          Text(label, style: TextStyle(fontFamily: family)),
        ],
      ),
    );
  }
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
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final String? label;
  final bool selected;

  @override
  Widget build(BuildContext _) {
    final child = label == null
        ? IconButton(
            tooltip: tooltip,
            onPressed: onPressed,
            color: selected ? const Color(0xFFC97068) : null,
            icon: Icon(
              icon,
              color: selected
                  ? const Color(0xFFC97068)
                  : const Color(0xFF3B3226),
            ),
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
