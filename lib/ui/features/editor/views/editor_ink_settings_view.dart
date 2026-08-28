import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../models/canvas.dart';
import '../view_models/editor_tool_state.dart';

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

  Future<void> _pickStrokeType() async {
    final selected = await showDialog<InkStrokeType>(
      context: context,
      builder: (context) => _StrokeTypeGallery(selected: _settings.strokeType),
    );
    if (!mounted || selected == null) return;
    _changeStrokeType(selected);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
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
          ListTile(
            key: const ValueKey('ink-stroke-selector'),
            contentPadding: EdgeInsets.zero,
            leading: InkStrokePreview(
              strokeType: _settings.strokeType,
              color: Theme.of(context).colorScheme.onSurface,
              width: 64,
            ),
            title: Text(_settings.strokeType.label),
            subtitle: const Text('Choose a brush style'),
            trailing: const Icon(Icons.expand_more),
            onTap: _pickStrokeType,
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
    final path = ui.Path()
      ..moveTo(3, size.height * .62)
      ..cubicTo(
        size.width * .24,
        size.height * .05,
        size.width * .42,
        size.height * .95,
        size.width * .62,
        size.height * .45,
      )
      ..cubicTo(
        size.width * .76,
        size.height * .1,
        size.width * .88,
        size.height * .8,
        size.width - 3,
        size.height * .35,
      );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = strokeType.strokeCap
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = (2.6 * strokeType.widthMultiplier).clamp(1.2, 7.0)
      ..color = color.withValues(
        alpha: strokeType.opacityMultiplier.clamp(0.0, 1.0),
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _InkStrokePreviewPainter oldDelegate) =>
      oldDelegate.strokeType != strokeType || oldDelegate.color != color;
}

class _StrokeTypeGallery extends StatelessWidget {
  const _StrokeTypeGallery({required this.selected});

  final InkStrokeType selected;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * .72;
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 380,
          maxHeight: maxHeight.clamp(280.0, 620.0),
        ),
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          shrinkWrap: true,
          itemCount: InkStrokeType.values.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final type = InkStrokeType.values[index];
            final isSelected = type == selected;
            return Semantics(
              button: true,
              selected: isSelected,
              label: type.label,
              child: InkWell(
                key: ValueKey('ink-stroke-option-${type.name}'),
                onTap: () => Navigator.pop(context, type),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 150,
                        child: Text(
                          type.label,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      Expanded(
                        child: InkStrokePreview(
                          strokeType: type,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      SizedBox(
                        width: 28,
                        child: isSelected
                            ? Icon(
                                Icons.check,
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
