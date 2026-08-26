import 'dart:math' as math;

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
    this.onTextColorEditStart,
    this.onTextColorEditEnd,
    this.recentColorValues = const <int>[],
    this.favoriteColorValues = const <int>{},
    this.onRecentColorAdded,
    this.onFavoriteColorsChanged,
    this.onSampleColor,
    this.strokeColorValue,
    this.strokeColorAvailable = false,
    this.onStrokeColorChanged,
    this.onStrokeColorEditStart,
    this.onStrokeColorEditEnd,
    this.inkColorValue,
    this.inkColorAvailable = false,
    this.onInkColorChanged,
    required this.onToggleBold,
    required this.onToggleItalic,
    required this.bold,
    required this.italic,
    required this.onDelete,
    required this.onBringToFront,
    this.canUndo = false,
    this.canRedo = false,
    this.onUndo,
    this.onRedo,
    this.onDuplicate,
    this.onSendToBack,
    this.onToggleLock,
    this.locked = false,
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
  final VoidCallback? onTextColorEditStart;
  final VoidCallback? onTextColorEditEnd;
  final List<int> recentColorValues;
  final Set<int> favoriteColorValues;
  final ValueChanged<int>? onRecentColorAdded;
  final ValueChanged<Set<int>>? onFavoriteColorsChanged;
  final Future<Color?> Function()? onSampleColor;
  final int? strokeColorValue;
  final bool strokeColorAvailable;
  final ValueChanged<int?>? onStrokeColorChanged;
  final VoidCallback? onStrokeColorEditStart;
  final VoidCallback? onStrokeColorEditEnd;
  final int? inkColorValue;
  final bool inkColorAvailable;
  final ValueChanged<int?>? onInkColorChanged;
  final VoidCallback onToggleBold;
  final VoidCallback onToggleItalic;
  final bool bold;
  final bool italic;
  final VoidCallback onDelete;
  final VoidCallback onBringToFront;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onDuplicate;
  final VoidCallback? onSendToBack;
  final VoidCallback? onToggleLock;
  final bool locked;

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
          // At tablet widths the contextual text controls already occupy the
          // available bottom bar. Keep power actions in More/Layers there so
          // the essential Edit/Delete actions remain reachable.
          final compact = MediaQuery.sizeOf(context).width < 900;
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
                if (!compact) ...[
                  _Action(
                    tooltip: 'Undo',
                    icon: Icons.undo,
                    label: null,
                    onPressed: canUndo ? onUndo : null,
                  ),
                  _Action(
                    tooltip: 'Redo',
                    icon: Icons.redo,
                    label: null,
                    onPressed: canRedo ? onRedo : null,
                  ),
                ],
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
                  _ColorPickerButton(
                    compact: compact,
                    colorValue: textColorValue,
                    label: 'Text color',
                    toolbarLabel: 'Color',
                    icon: Icons.format_color_text,
                    onChanged: onTextColorChanged,
                    onEditStart: onTextColorEditStart,
                    onEditEnd: onTextColorEditEnd,
                    recentColorValues: recentColorValues,
                    favoriteColorValues: favoriteColorValues,
                    onRecentColorAdded: onRecentColorAdded,
                    onFavoriteColorsChanged: onFavoriteColorsChanged,
                    onSampleColor: onSampleColor,
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
                if (strokeColorAvailable)
                  _ColorPickerButton(
                    compact: compact,
                    colorValue: strokeColorValue,
                    label: 'Stroke color',
                    toolbarLabel: 'Stroke',
                    icon: Icons.brush_outlined,
                    onChanged: onStrokeColorChanged!,
                    onEditStart: onStrokeColorEditStart,
                    onEditEnd: onStrokeColorEditEnd,
                    recentColorValues: recentColorValues,
                    favoriteColorValues: favoriteColorValues,
                    onRecentColorAdded: onRecentColorAdded,
                    onFavoriteColorsChanged: onFavoriteColorsChanged,
                    onSampleColor: onSampleColor,
                  ),
                if (inkColorAvailable)
                  _ColorPickerButton(
                    compact: compact,
                    colorValue: inkColorValue,
                    label: 'Ink color',
                    toolbarLabel: 'Ink',
                    icon: Icons.brush_outlined,
                    onChanged: onInkColorChanged!,
                    recentColorValues: recentColorValues,
                    favoriteColorValues: favoriteColorValues,
                    onRecentColorAdded: onRecentColorAdded,
                    onFavoriteColorsChanged: onFavoriteColorsChanged,
                    onSampleColor: onSampleColor,
                  ),
                _Action(
                  tooltip: 'More editing tools',
                  icon: Icons.more_horiz,
                  label: compact ? null : 'More',
                  onPressed: onMore,
                ),
                _LayerOrderMenu(
                  hasSelection: hasSelection,
                  onBringToFront: onBringToFront,
                  onSendToBack: onSendToBack,
                ),
                if (hasSelection) ...[
                  _divider(),
                  if (textSelection)
                    _Action(
                      tooltip: 'Edit text',
                      icon: textEditing ? Icons.keyboard_hide : Icons.edit_note,
                      label: null,
                      onPressed: onEditText,
                    ),
                  if (!compact && onDuplicate != null)
                    _Action(
                      tooltip: 'Duplicate block',
                      icon: Icons.copy_outlined,
                      label: null,
                      onPressed: onDuplicate,
                    ),
                  if (!compact && onToggleLock != null)
                    _Action(
                      tooltip: locked ? 'Unlock block' : 'Lock block',
                      icon: locked ? Icons.lock : Icons.lock_open_outlined,
                      label: null,
                      selected: locked,
                      onPressed: onToggleLock,
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

enum _LayerOrderAction { bringToFront, bringToBack }

class _LayerOrderMenu extends StatelessWidget {
  const _LayerOrderMenu({
    required this.hasSelection,
    required this.onBringToFront,
    required this.onSendToBack,
  });

  final bool hasSelection;
  final VoidCallback onBringToFront;
  final VoidCallback? onSendToBack;

  @override
  Widget build(BuildContext context) => PopupMenuButton<_LayerOrderAction>(
    tooltip: 'Layer order',
    position: PopupMenuPosition.over,
    offset: const Offset(0, -8),
    onSelected: (action) {
      switch (action) {
        case _LayerOrderAction.bringToFront:
          onBringToFront();
        case _LayerOrderAction.bringToBack:
          onSendToBack?.call();
      }
    },
    itemBuilder: (context) => [
      PopupMenuItem<_LayerOrderAction>(
        value: _LayerOrderAction.bringToFront,
        enabled: hasSelection,
        child: const Row(
          children: [
            Icon(Icons.layers_outlined),
            SizedBox(width: 12),
            Text('Bring to front'),
          ],
        ),
      ),
      PopupMenuItem<_LayerOrderAction>(
        value: _LayerOrderAction.bringToBack,
        enabled: hasSelection && onSendToBack != null,
        child: const Row(
          children: [
            Icon(Icons.flip_to_back_outlined),
            SizedBox(width: 12),
            Text('Bring to back'),
          ],
        ),
      ),
    ],
    icon: const Icon(Icons.layers),
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

/// The result returned by [showVisualColorPicker].
class VisualColorPickerResult {
  const VisualColorPickerResult(this.value, {this.isSample = false});

  const VisualColorPickerResult.sample() : value = null, isSample = true;

  final int? value;
  final bool isSample;
}

/// Presents the shared visual color picker used by text and drawable tools.
Future<VisualColorPickerResult?> showVisualColorPicker(
  BuildContext context, {
  required int? initialValue,
  String dialogTitle = 'Text color',
  List<int> recentColorValues = const <int>[],
  Set<int> favoriteColorValues = const <int>{},
  ValueChanged<int?>? onPreview,
  ValueChanged<Set<int>>? onFavoriteColorsChanged,
  Future<Color?> Function()? onSampleColor,
}) async {
  final choice = await showDialog<_ColorChoice>(
    context: context,
    builder: (context) => _ColorPickerDialog(
      initialValue: initialValue,
      dialogTitle: dialogTitle,
      recentColorValues: recentColorValues,
      favoriteColorValues: favoriteColorValues,
      onPreview: onPreview,
      onFavoriteColorsChanged: onFavoriteColorsChanged,
      onSampleColor: onSampleColor == null
          ? null
          : () => Navigator.pop(context, const _ColorChoice.sample()),
    ),
  );
  if (choice == null) return null;
  return choice.sample
      ? const VisualColorPickerResult.sample()
      : VisualColorPickerResult(choice.value);
}

class _ColorPickerButton extends StatelessWidget {
  const _ColorPickerButton({
    required this.compact,
    required this.colorValue,
    required this.label,
    required this.toolbarLabel,
    required this.icon,
    required this.onChanged,
    this.onEditStart,
    this.onEditEnd,
    this.recentColorValues = const <int>[],
    this.favoriteColorValues = const <int>{},
    this.onRecentColorAdded,
    this.onFavoriteColorsChanged,
    this.onSampleColor,
  });

  final bool compact;
  final int? colorValue;
  final String label;
  final String toolbarLabel;
  final IconData icon;
  final ValueChanged<int?> onChanged;
  final VoidCallback? onEditStart;
  final VoidCallback? onEditEnd;
  final List<int> recentColorValues;
  final Set<int> favoriteColorValues;
  final ValueChanged<int>? onRecentColorAdded;
  final ValueChanged<Set<int>>? onFavoriteColorsChanged;
  final Future<Color?> Function()? onSampleColor;

  Color get _color =>
      colorValue == null ? const Color(0xFF3B3226) : Color(colorValue!);

  Future<void> _open(BuildContext context) async {
    final original = colorValue;
    var dialogInitial = colorValue;
    var finished = false;
    onEditStart?.call();
    while (!finished) {
      if (!context.mounted) break;
      final choice = await showVisualColorPicker(
        context,
        initialValue: dialogInitial,
        dialogTitle: label,
        recentColorValues: recentColorValues,
        favoriteColorValues: favoriteColorValues,
        onPreview: onChanged,
        onFavoriteColorsChanged: onFavoriteColorsChanged,
        onSampleColor: onSampleColor,
      );
      if (choice?.isSample == true) {
        final sampled = await onSampleColor?.call();
        final value = sampled?.toARGB32();
        onChanged(value ?? original);
        if (value != null) onRecentColorAdded?.call(value);
        finished = true;
        continue;
      }
      if (choice == null) {
        onChanged(original);
      } else {
        onChanged(choice.value);
        final value = choice.value;
        if (value != null) onRecentColorAdded?.call(value);
      }
      finished = true;
    }
    onEditEnd?.call();
  }

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: _color),
              Text(
                compact ? '' : toolbarLabel,
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
  const _ColorChoice(this.value) : sample = false;

  const _ColorChoice.sample() : value = null, sample = true;

  final int? value;
  final bool sample;
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({
    this.initialValue,
    this.dialogTitle = 'Text color',
    this.recentColorValues = const <int>[],
    this.favoriteColorValues = const <int>{},
    this.onPreview,
    this.onFavoriteColorsChanged,
    this.onSampleColor,
  });

  final int? initialValue;
  final String dialogTitle;
  final List<int> recentColorValues;
  final Set<int> favoriteColorValues;
  final ValueChanged<int?>? onPreview;
  final ValueChanged<Set<int>>? onFavoriteColorsChanged;
  final VoidCallback? onSampleColor;

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
  late double _alpha;
  late Set<int> _favorites;

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
    _alpha = hsv.alpha;
    _favorites = {...widget.favoriteColorValues};
  }

  void _setColor(Color color) {
    final hsv = HSVColor.fromColor(color);
    setState(() {
      _selected = color;
      _hue = hsv.hue;
      _saturation = hsv.saturation;
      _value = hsv.value;
    });
    widget.onPreview?.call(color.toARGB32());
  }

  void _setHsv() =>
      _setColor(HSVColor.fromAHSV(_alpha, _hue, _saturation, _value).toColor());

  void _setHue(Offset localPosition, Size size) {
    final center = size.center(Offset.zero);
    final offset = localPosition - center;
    final distance = offset.distance;
    final radius = math.min(size.width, size.height) / 2;
    if (distance < radius - 34 || distance > radius + 4) return;
    var hue = (math.atan2(offset.dy, offset.dx) * 180 / math.pi) + 90;
    if (hue < 0) hue += 360;
    _hue = hue % 360;
    _setHsv();
  }

  void _setField(Offset localPosition, Size size) {
    _saturation = (localPosition.dx / size.width).clamp(0.0, 1.0);
    _value = (1 - localPosition.dy / size.height).clamp(0.0, 1.0);
    _setHsv();
  }

  void _setOpacity(Offset localPosition, Size size) {
    _alpha = (localPosition.dx / size.width).clamp(0.0, 1.0);
    _setHsv();
  }

  void _toggleFavorite() {
    final value = _selected.toARGB32();
    setState(() {
      if (!_favorites.add(value)) _favorites.remove(value);
    });
    widget.onFavoriteColorsChanged?.call(Set.unmodifiable(_favorites));
  }

  Widget _swatch({required String label, required Color color}) {
    final selected = color.toARGB32() == _selected.toARGB32();
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Tooltip(
        message: label,
        child: InkWell(
          key: ValueKey('color-swatch-${color.toARGB32()}'),
          onTap: () => _setColor(color),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? Colors.white : Colors.black26,
                width: selected ? 3 : 2,
              ),
              boxShadow: selected
                  ? [const BoxShadow(color: Colors.black26, blurRadius: 2)]
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _swatchSection(String title, Iterable<int> values) {
    final colors = values.map(Color.new).toList(growable: false);
    if (colors.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < colors.length; i++)
                _swatch(label: '$title color ${i + 1}', color: colors[i]),
            ],
          ),
        ],
      ),
    );
  }

  bool get _lowContrast {
    final paper = const Color(0xFFF2E9D5).computeLuminance();
    final ink = Color.alphaBlend(
      _selected,
      const Color(0xFFF2E9D5),
    ).computeLuminance();
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
      title: Row(
        children: [
          Expanded(child: Text(widget.dialogTitle)),
          if (widget.onSampleColor != null)
            IconButton(
              key: const ValueKey('color-eyedropper'),
              tooltip: 'Sample color from page',
              onPressed: widget.onSampleColor,
              icon: const Icon(Icons.colorize),
            ),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Preview(label: 'Current', color: _initial),
                  _Preview(label: 'New', color: _selected),
                  IconButton(
                    key: const ValueKey('toggle-color-favorite'),
                    tooltip: _favorites.contains(_selected.toARGB32())
                        ? 'Remove from favorite colors'
                        : 'Save to favorite colors',
                    onPressed: _toggleFavorite,
                    icon: Icon(
                      _favorites.contains(_selected.toARGB32())
                          ? Icons.star
                          : Icons.star_border,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text('Palette'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in _presets)
                    _swatch(label: preset.label, color: preset.color),
                ],
              ),
              _swatchSection('Favorite colors', _favorites),
              _swatchSection('Recent colors', widget.recentColorValues),
              const SizedBox(height: 16),
              Semantics(
                label: 'Hue wheel',
                child: _HueWheel(
                  hue: _hue,
                  onChanged: (position, size) => _setHue(position, size),
                ),
              ),
              Semantics(
                label: 'Color shade field',
                child: _ColorField(
                  hue: _hue,
                  saturation: _saturation,
                  value: _value,
                  onChanged: (position, size) => _setField(position, size),
                ),
              ),
              Semantics(
                label: 'Opacity control',
                child: _OpacityField(
                  color: _selected,
                  alpha: _alpha,
                  onChanged: (position, size) => _setOpacity(position, size),
                ),
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
          onPressed: () =>
              Navigator.pop(context, _ColorChoice(_selected.toARGB32())),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _HueWheel extends StatelessWidget {
  const _HueWheel({required this.hue, required this.onChanged});

  final double hue;
  final void Function(Offset position, Size size) onChanged;

  @override
  Widget build(BuildContext context) {
    final size = math
        .min((MediaQuery.sizeOf(context).width - 96).clamp(210.0, 280.0), 280.0)
        .toDouble();
    return SizedBox(
      key: const ValueKey('color-wheel'),
      width: size,
      height: size,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wheelSize = Size(constraints.maxWidth, constraints.maxHeight);
          return Stack(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) =>
                    onChanged(details.localPosition, wheelSize),
                onPanStart: (details) =>
                    onChanged(details.localPosition, wheelSize),
                onPanUpdate: (details) =>
                    onChanged(details.localPosition, wheelSize),
                child: CustomPaint(painter: _HueWheelPainter(hue)),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ColorField extends StatelessWidget {
  const _ColorField({
    required this.hue,
    required this.saturation,
    required this.value,
    required this.onChanged,
  });

  final double hue;
  final double saturation;
  final double value;
  final void Function(Offset position, Size size) onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('color-field'),
      width: double.infinity,
      height: 180,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => onChanged(details.localPosition, size),
            onPanStart: (details) => onChanged(details.localPosition, size),
            onPanUpdate: (details) => onChanged(details.localPosition, size),
            child: CustomPaint(
              painter: _ColorFieldPainter(hue, saturation, value),
            ),
          );
        },
      ),
    );
  }
}

class _OpacityField extends StatelessWidget {
  const _OpacityField({
    required this.color,
    required this.alpha,
    required this.onChanged,
  });

  final Color color;
  final double alpha;
  final void Function(Offset position, Size size) onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: SizedBox(
      key: const ValueKey('color-opacity'),
      height: 32,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => onChanged(details.localPosition, size),
            onPanStart: (details) => onChanged(details.localPosition, size),
            onPanUpdate: (details) => onChanged(details.localPosition, size),
            child: CustomPaint(painter: _OpacityPainter(color, alpha)),
          );
        },
      ),
    ),
  );
}

class _HueWheelPainter extends CustomPainter {
  const _HueWheelPainter(this.hue);

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 14;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final colors = [
      for (var i = 0; i <= 6; i++)
        HSVColor.fromAHSV(1, i * 60 % 360, 1, 1).toColor(),
    ];
    final wheel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 28
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 1.5,
        colors: colors,
      ).createShader(rect);
    canvas.drawCircle(center, radius, wheel);

    final angle = (hue - 90) * math.pi / 180;
    final marker = center + Offset(math.cos(angle), math.sin(angle)) * radius;
    canvas
      ..drawCircle(marker, 10, Paint()..color = Colors.white)
      ..drawCircle(
        marker,
        8,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.black87,
      );
  }

  @override
  bool shouldRepaint(covariant _HueWheelPainter oldDelegate) =>
      oldDelegate.hue != hue;
}

class _ColorFieldPainter extends CustomPainter {
  const _ColorFieldPainter(this.hue, this.saturation, this.value);

  final double hue;
  final double saturation;
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hueColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    canvas.drawRect(rect, Paint()..color = hueColor);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Colors.white, Colors.transparent],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Colors.transparent, Colors.black],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(rect),
    );
    final marker = Offset(saturation * size.width, (1 - value) * size.height);
    canvas
      ..drawCircle(marker, 9, Paint()..color = Colors.white)
      ..drawCircle(
        marker,
        7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.black87,
      );
  }

  @override
  bool shouldRepaint(covariant _ColorFieldPainter oldDelegate) =>
      oldDelegate.hue != hue ||
      oldDelegate.saturation != saturation ||
      oldDelegate.value != value;
}

class _OpacityPainter extends CustomPainter {
  const _OpacityPainter(this.color, this.alpha);

  final Color color;
  final double alpha;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    const tile = 8.0;
    final checker = Paint();
    for (var y = 0.0; y < size.height; y += tile) {
      for (var x = 0.0; x < size.width; x += tile) {
        checker.color = ((x / tile).floor() + (y / tile).floor()).isEven
            ? Colors.white
            : const Color(0xFFD9D2C6);
        canvas.drawRect(Rect.fromLTWH(x, y, tile, tile), checker);
      }
    }
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [color.withValues(alpha: 0), color.withValues(alpha: 1)],
        ).createShader(rect),
    );
    final x = alpha * size.width;
    canvas
      ..drawCircle(Offset(x, size.height / 2), 9, Paint()..color = Colors.white)
      ..drawCircle(
        Offset(x, size.height / 2),
        7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.black87,
      );
  }

  @override
  bool shouldRepaint(covariant _OpacityPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.alpha != alpha;
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
          child: Center(
            child: Text('Aa', style: TextStyle(color: color)),
          ),
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
