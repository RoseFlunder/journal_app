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
            subtitle: Text('Color, opacity, and stroke width'),
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
          const Text('Stroke type'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in InkStrokeType.values)
                ChoiceChip(
                  key: ValueKey('ink-stroke-${type.name}'),
                  label: Text(type.label),
                  selected: _settings.strokeType == type,
                  onSelected: (_) => _changeStrokeType(type),
                ),
            ],
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
