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
    required this.textFormattingAvailable,
    required this.textSelection,
    required this.onDecreaseFontSize,
    required this.onIncreaseFontSize,
    required this.fontFamily,
    required this.onFontFamilyChanged,
    required this.textColorValue,
    required this.onTextColorChanged,
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
  final bool textFormattingAvailable;
  final bool textSelection;
  final VoidCallback? onDecreaseFontSize;
  final VoidCallback? onIncreaseFontSize;
  final String? fontFamily;
  final ValueChanged<String?> onFontFamilyChanged;
  final int? textColorValue;
  final ValueChanged<int?> onTextColorChanged;
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
                if (textFormattingAvailable) ...[
                  _FontPicker(
                    compact: compact,
                    fontFamily: fontFamily,
                    onChanged: onFontFamilyChanged,
                  ),
                  _TextColorPicker(
                    compact: compact,
                    colorValue: textColorValue,
                    onChanged: onTextColorChanged,
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
                ],
                _Action(
                  tooltip: 'More editing tools',
                  icon: Icons.more_horiz,
                  label: compact ? null : 'More',
                  onPressed: onMore,
                ),
                if (hasSelection) ...[
                  _divider(),
                  if (textSelection)
                    _Action(
                      tooltip: 'Edit text',
                      icon: textEditing
                          ? Icons.keyboard_hide
                          : Icons.edit_note,
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

class _TextColorPicker extends StatelessWidget {
  const _TextColorPicker({
    required this.compact,
    required this.colorValue,
    required this.onChanged,
  });

  final bool compact;
  final int? colorValue;
  final ValueChanged<int?> onChanged;

  Color get _color => colorValue == null
      ? const Color(0xFF3B3226)
      : Color(colorValue!);

  Future<void> _open(BuildContext context) async {
    final choice = await showDialog<_ColorChoice>(
      context: context,
      builder: (context) => _ColorPickerDialog(initialValue: colorValue),
    );
    if (choice != null) onChanged(choice.value);
  }

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Text color',
    child: Semantics(
      button: true,
      label: 'Text color',
      child: InkWell(
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.format_color_text, size: 20, color: _color),
              Text(
                compact ? '' : 'Color',
                style: const TextStyle(
                  fontFamily: 'Lora',
                  fontSize: 9,
                  color: Color(0xFF3B3226),
                ),
              ),
              Container(width: 20, height: 3, color: _color),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ColorChoice {
  const _ColorChoice(this.value);

  final int? value;
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({this.initialValue});

  final int? initialValue;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  static const _presets = <({String label, Color color})>[
    (label: 'Ink', color: Color(0xFF3B3226)),
    (label: 'Berry', color: Color(0xFF873F4D)),
    (label: 'Terracotta', color: Color(0xFF9B4B2F)),
    (label: 'Moss', color: Color(0xFF4E684A)),
    (label: 'Teal', color: Color(0xFF286A68)),
    (label: 'Blue', color: Color(0xFF3E5E86)),
    (label: 'Plum', color: Color(0xFF694B78)),
  ];

  late Color _selected;
  late Color _initial;
  late double _hue;
  late double _saturation;
  late double _value;
  late final TextEditingController _hexController;
  String? _hexError;

  @override
  void initState() {
    super.initState();
    _initial = widget.initialValue == null
        ? const Color(0xFF3B3226)
        : Color(widget.initialValue!);
    _selected = _initial;
    final hsv = HSVColor.fromColor(_selected);
    _hue = hsv.hue;
    _saturation = hsv.saturation;
    _value = hsv.value;
    _hexController = TextEditingController(text: _hex(_selected));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  String _hex(Color color) => color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();

  void _setColor(Color color) {
    final hsv = HSVColor.fromColor(color);
    setState(() {
      _selected = color;
      _hue = hsv.hue;
      _saturation = hsv.saturation;
      _value = hsv.value;
      _hexController.text = _hex(color);
      _hexError = null;
    });
  }

  void _setHsv() => _setColor(
        HSVColor.fromAHSV(1, _hue, _saturation, _value).toColor(),
      );

  void _parseHex(String value) {
    final normalized = value.trim().replaceFirst('#', '');
    final withAlpha = normalized.length == 6 ? 'FF$normalized' : normalized;
    final parsed = int.tryParse(withAlpha, radix: 16);
    if (parsed == null || withAlpha.length != 8) {
      setState(() => _hexError = 'Enter 6 or 8 hexadecimal digits.');
      return;
    }
    _setColor(Color(parsed));
  }

  bool get _lowContrast {
    final paper = const Color(0xFFF2E9D5).computeLuminance();
    final ink = _selected.computeLuminance();
    final light = paper > ink ? paper : ink;
    final dark = paper > ink ? ink : paper;
    return (light + 0.05) / (dark + 0.05) < 4.5;
  }

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width - 48)
        .clamp(240.0, 420.0)
        .toDouble();
    return AlertDialog(
      title: const Text('Text color'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Preview(label: 'Current', color: _initial),
                const SizedBox(width: 16),
                _Preview(label: 'New', color: _selected),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Presets'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in _presets)
                  Semantics(
                    button: true,
                    label: preset.label,
                    child: Tooltip(
                      message: preset.label,
                      child: InkWell(
                        onTap: () => _setColor(preset.color),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: preset.color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _selected.toARGB32() ==
                                      preset.color.toARGB32()
                                  ? Colors.white
                                  : Colors.black26,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Hue ${_hue.round()}°'),
            Semantics(
              label: 'Hue',
              child: Slider(
                value: _hue,
                min: 0,
                max: 360,
                onChanged: (value) {
                  _hue = value;
                  _setHsv();
                },
              ),
            ),
            Text('Saturation ${(_saturation * 100).round()}%'),
            Semantics(
              label: 'Saturation',
              child: Slider(
                value: _saturation,
                onChanged: (value) {
                  _saturation = value;
                  _setHsv();
                },
              ),
            ),
            Text('Brightness ${(_value * 100).round()}%'),
            Semantics(
              label: 'Brightness',
              child: Slider(
                value: _value,
                onChanged: (value) {
                  _value = value;
                  _setHsv();
                },
              ),
            ),
            TextField(
              controller: _hexController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Hex color',
                prefixText: '#',
                errorText: _hexError,
              ),
              onChanged: (value) {
                final normalized = value.replaceFirst('#', '');
                if (normalized.isEmpty) {
                  setState(() => _hexError = null);
                } else {
                  _parseHex(normalized);
                }
              },
            ),
            if (_lowContrast)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'This color may be difficult to read on paper.',
                  style: TextStyle(color: Colors.deepOrange),
                ),
              ),
          ],
        ),
      ),
      ),
      actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, const _ColorChoice(null)),
        child: const Text('Default ink'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _hexError == null
            ? () => Navigator.pop(
                  context,
                  _ColorChoice(_selected.toARGB32()),
                )
            : null,
        child: const Text('Apply'),
      ),
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label text color preview',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        const SizedBox(width: 8),
        Container(
          width: 48,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFFF2E9D5),
            border: Border.all(color: color),
          ),
          child: Center(child: Text('Aa', style: TextStyle(color: color))),
        ),
      ],
    ),
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
