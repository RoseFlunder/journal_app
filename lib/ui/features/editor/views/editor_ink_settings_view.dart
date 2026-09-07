import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../models/canvas.dart';
import '../view_models/editor_tool_state.dart';
import 'ink_stroke_renderer.dart';

/// Bottom-sheet content for the vector ink tool.
///
/// The view owns only sheet-local values and emits immutable previews. Color
/// sampling and persistence stay with the configured editor view model/page
/// callback because they require the captured paper surface and preferences.
class EditorInkSettingsView extends StatefulWidget {
  const EditorInkSettingsView({
    super.key,
    required this.initial,
    required this.onPreview,
    required this.onPickColor,
  });

  final InkSettings initial;
  final ValueChanged<InkSettings> onPreview;
  final Future<InkSettings?> Function(BuildContext, InkSettings) onPickColor;

  @override
  State<EditorInkSettingsView> createState() => _EditorInkSettingsViewState();
}

class _EditorInkSettingsViewState extends State<EditorInkSettingsView> {
  late InkSettings _settings = widget.initial;

  Future<void> _pickColor() async {
    final next = await widget.onPickColor(context, _settings);
    if (!mounted || next == null) return;
    setState(() => _settings = next);
    widget.onPreview(next);
  }

  void _changeWidth(double width) {
    final next = _settings.copyWith(width: width);
    setState(() => _settings = next);
    widget.onPreview(next);
  }

  void _changeStrokeType(InkStrokeType strokeType) {
    final next = _settings.copyWith(strokeType: strokeType);
    setState(() => _settings = next);
    widget.onPreview(next);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(
            leading: Icon(Icons.draw_outlined),
            title: Text('Ink settings'),
            subtitle: Text('Color, brush type, opacity, and width'),
          ),
          ListTile(
            key: const ValueKey('ink-color'),
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: Color(_settings.colorValue)
                  .withValues(alpha: _settings.opacity),
              child: const Icon(Icons.brush_outlined),
            ),
            title: const Text('Ink color'),
            subtitle: const Text('Open the visual color picker'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickColor,
          ),
          const SizedBox(height: 8),
          Text('Stroke style', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) => GridView.count(
              key: const ValueKey('ink-stroke-options'),
              crossAxisCount: constraints.maxWidth >= 520 ? 4 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.8,
              children: [
                for (final type in InkStrokeType.values)
                  _StrokeTypeOption(
                    type: type,
                    selected: type == _settings.strokeType,
                    onTap: () => _changeStrokeType(type),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text('Stroke size ${_settings.width.toStringAsFixed(1)}'),
          Slider(
            min: 0.8,
            max: 8,
            value: _settings.width,
            onChanged: _changeWidth,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, _settings),
                child: const Text('Apply'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Compact preview of the same stroke preset used by the ink renderer.
class InkStrokePreview extends StatelessWidget {
  const InkStrokePreview({
    super.key,
    required this.strokeType,
    required this.color,
    this.width = 72,
  });

  final InkStrokeType strokeType;
  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: 28,
    child: CustomPaint(
      painter: _InkStrokePreviewPainter(strokeType: strokeType, color: color),
    ),
  );
}

class _InkStrokePreviewPainter extends CustomPainter {
  const _InkStrokePreviewPainter({
    required this.strokeType,
    required this.color,
  });

  final InkStrokeType strokeType;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final points = <InkStrokePoint>[];
    for (var index = 0; index <= 48; index++) {
      final t = index / 48;
      final x = 3 + (size.width - 6) * t;
      final y = size.height * (.52 + .22 * math.sin(t * math.pi * 2.2));
      points.add(InkStrokePoint(Offset(x, y)));
    }
    InkStrokeRenderer.paint(
      canvas,
      points: points,
      color: color,
      width: 2.6,
      opacity: 1,
      strokeType: strokeType,
    );
  }

  @override
  bool shouldRepaint(covariant _InkStrokePreviewPainter oldDelegate) =>
      oldDelegate.strokeType != strokeType || oldDelegate.color != color;
}

class _StrokeTypeOption extends StatelessWidget {
  const _StrokeTypeOption({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final InkStrokeType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: type.label,
      child: Material(
        color: selected ? colors.primaryContainer : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? colors.primary : colors.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('ink-stroke-option-${type.name}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        type.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (selected)
                      Icon(Icons.check, size: 18, color: colors.primary),
                  ],
                ),
                const SizedBox(height: 4),
                InkStrokePreview(
                  strokeType: type,
                  color: colors.onSurface,
                  width: double.infinity,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
