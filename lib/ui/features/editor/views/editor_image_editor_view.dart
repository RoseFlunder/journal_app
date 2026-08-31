import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../models/document.dart';
import '../../../../widgets/paper_page.dart';
import '../view_models/image_filter_preset.dart';

/// Non-destructive image/sticker editor. The view keeps only sheet-local
/// values and emits immutable node previews to the editor view model.
class EditorImageEditorView extends StatefulWidget {
  const EditorImageEditorView({
    super.key,
    required this.node,
    required this.onPreview,
    required this.onPickFrameColor,
  });

  final CanvasNode node;
  final ValueChanged<CanvasNode> onPreview;
  final Future<int?> Function(BuildContext context, int? currentValue)
  onPickFrameColor;

  @override
  State<EditorImageEditorView> createState() => _EditorImageEditorViewState();
}

class _EditorImageEditorViewState extends State<EditorImageEditorView> {
  static const _squareCrop = Rect.fromLTWH(0.125, 0, 0.75, 1);
  static const _portraitCrop = Rect.fromLTWH(0.22, 0, 0.56, 1);
  static const _wideCrop = Rect.fromLTWH(0, 0.2, 1, 0.6);

  late CanvasNode _currentNode = widget.node;
  late Rect? _crop = widget.node.crop;
  late double _opacity = widget.node.opacity;
  late double _brightness = widget.node.brightness;
  late double _contrast = widget.node.contrast;
  late double _saturation = widget.node.saturation;
  late double _warmth = widget.node.warmth;
  late String _imageMask = widget.node.imageMask;
  late int? _frameColorValue = widget.node.frameColorValue;
  late double _frameWidth = widget.node.frameWidth;
  late String? _selectedFilterId = _matchingFilterId();

  bool get _supportsImageAppearance => widget.node.type == BlockType.image;

  CanvasNode _withPayload(CanvasNode node, String key, Object? value) {
    final payload = Map<String, dynamic>.from(node.payload);
    if (value == null) {
      payload.remove(key);
    } else {
      payload[key] = value;
    }
    return node.copyWith(payload: payload);
  }

  CanvasNode _withFrame(
    CanvasNode node, {
    required double width,
    required bool setColor,
    int? color,
  }) {
    final payload = Map<String, dynamic>.from(node.payload)
      ..['frameWidth'] = width;
    if (setColor) {
      if (color == null) {
        payload.remove('frameColorValue');
      } else {
        payload['frameColorValue'] = color;
      }
    }
    return node.copyWith(payload: payload);
  }

  void _preview(CanvasNode Function(CanvasNode node) update) {
    _currentNode = update(_currentNode);
    widget.onPreview(_currentNode);
  }

  String? _matchingFilterId() {
    for (final preset in ImageFilterPreset.values) {
      if (preset.matches(
        brightness: widget.node.brightness,
        contrast: widget.node.contrast,
        saturation: widget.node.saturation,
        warmth: widget.node.warmth,
      )) {
        return preset.id;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.72,
    minChildSize: 0.48,
    maxChildSize: 0.94,
    builder: (context, scrollController) => SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: const Text('Edit image'),
                  subtitle: Text(
                    _supportsImageAppearance
                        ? 'Crop, adjust, filter, and frame'
                        : 'Non-destructive crop and presentation',
                  ),
                ),
                const Divider(),
                Text('Crop', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _cropChoice(
                      label: 'Original',
                      selected: _crop == null,
                      onTap: () {
                        setState(() => _crop = null);
                        _preview((next) => _withPayload(next, 'crop', null));
                      },
                    ),
                    _cropChoice(
                      label: 'Square',
                      selected: _crop == _squareCrop,
                      onTap: () => _setCrop(_squareCrop),
                    ),
                    _cropChoice(
                      label: 'Portrait',
                      selected: _crop == _portraitCrop,
                      onTap: () => _setCrop(_portraitCrop),
                    ),
                    _cropChoice(
                      label: 'Wide',
                      selected: _crop == _wideCrop,
                      onTap: () => _setCrop(_wideCrop),
                    ),
                  ],
                ),
                if (_supportsImageAppearance) ...[
                  const SizedBox(height: 18),
                  _buildFilters(context),
                  const SizedBox(height: 18),
                  _buildBorder(context),
                ],
                const SizedBox(height: 18),
                Text(
                  'Opacity ${(_opacity * 100).round()}%',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Slider(
                  key: const ValueKey('image-opacity'),
                  min: 0.1,
                  max: 1,
                  value: _opacity.clamp(0.1, 1).toDouble(),
                  label: '${(_opacity * 100).round()}%',
                  onChanged: (value) {
                    setState(() => _opacity = value);
                    _preview((next) => next.copyWith(opacity: value));
                  },
                ),
                _adjustmentSlider(
                  context,
                  label: 'Brightness',
                  value: _brightness,
                  min: -1,
                  max: 1,
                  key: const ValueKey('image-brightness'),
                  onChanged: (value) => _setFilterValue(brightness: value),
                ),
                _adjustmentSlider(
                  context,
                  label: 'Contrast',
                  value: _contrast,
                  min: -1,
                  max: 1,
                  key: const ValueKey('image-contrast'),
                  onChanged: (value) => _setFilterValue(contrast: value),
                ),
                _adjustmentSlider(
                  context,
                  label: 'Saturation',
                  value: _saturation,
                  min: 0,
                  max: 2,
                  key: const ValueKey('image-saturation'),
                  onChanged: (value) => _setFilterValue(saturation: value),
                ),
                if (_supportsImageAppearance)
                  _adjustmentSlider(
                    context,
                    label: 'Warmth',
                    value: _warmth,
                    min: -1,
                    max: 1,
                    key: const ValueKey('image-warmth'),
                    onChanged: (value) => _setFilterValue(warmth: value),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () => _preview(
                        (next) => next.copyWith(
                          transform: next.transform.copyWith(
                            rotation: next.transform.rotation + math.pi / 2,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.rotate_90_degrees_ccw),
                      label: const Text('Rotate 90°'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _preview(
                        (next) => _withPayload(
                          next,
                          'flipX',
                          next.payload['flipX'] != true,
                        ),
                      ),
                      icon: const Icon(Icons.flip),
                      label: const Text('Flip horizontal'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _preview(
                        (next) => _withPayload(
                          next,
                          'flipY',
                          next.payload['flipY'] != true,
                        ),
                      ),
                      icon: const Icon(Icons.flip_camera_android),
                      label: const Text('Flip vertical'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text('Mask', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'rectangle', label: Text('Square')),
                    ButtonSegment(value: 'rounded', label: Text('Rounded')),
                    ButtonSegment(value: 'circle', label: Text('Circle')),
                  ],
                  selected: {_imageMask},
                  onSelectionChanged: (selection) {
                    final nextMask = selection.first;
                    setState(() => _imageMask = nextMask);
                    _preview(
                      (next) => _withPayload(next, 'imageMask', nextMask),
                    );
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    key: const ValueKey('image-editor-cancel'),
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('image-editor-apply'),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildFilters(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Filters', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final preset in ImageFilterPreset.values)
            ChoiceChip(
              key: ValueKey('image-filter-${preset.id}'),
              avatar: _filterSwatch(preset),
              label: Text(preset.label),
              selected: _selectedFilterId == preset.id,
              onSelected: (_) => _setFilterPreset(preset),
            ),
        ],
      ),
    ],
  );

  Widget _filterSwatch(ImageFilterPreset preset) => Container(
    width: 18,
    height: 18,
    decoration: BoxDecoration(
      color: switch (preset.id) {
        'soft' => const Color(0xFFD5C7B0),
        'warm' => const Color(0xFFC9855B),
        'cool' => const Color(0xFF7896B3),
        'vintage' => const Color(0xFF9C7658),
        'mono' => const Color(0xFF777777),
        _ => PaperPage.paper,
      },
      shape: BoxShape.circle,
      border: Border.all(color: PaperPage.ink.withValues(alpha: 0.25)),
    ),
  );

  Widget _buildBorder(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Border', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _borderChoice(label: 'None', value: 'none', width: 0),
          _borderChoice(label: 'Thin', value: 'thin', width: 1.5),
          _borderChoice(label: 'Medium', value: 'medium', width: 3),
        ],
      ),
      const SizedBox(height: 8),
      ListTile(
        key: const ValueKey('image-frame-color'),
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          backgroundColor: Color(_frameColorValue ?? PaperPage.ink.toARGB32()),
          child: const Icon(Icons.border_color_outlined),
        ),
        title: const Text('Frame color'),
        subtitle: const Text('Choose a custom border color'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _pickFrameColor,
      ),
      Text(
        'Custom width ${_frameWidth.toStringAsFixed(1)}',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      Slider(
        key: const ValueKey('image-frame-width'),
        min: 0,
        max: 8,
        divisions: 16,
        value: _frameWidth.clamp(0, 8).toDouble(),
        label: _frameWidth.toStringAsFixed(1),
        onChanged: (value) {
          setState(() => _frameWidth = value);
          _preview((next) => _withFrame(next, width: value, setColor: false));
        },
      ),
    ],
  );

  Widget _borderChoice({
    required String label,
    required String value,
    required double width,
  }) => ChoiceChip(
    key: ValueKey('image-border-$value'),
    label: Text(label),
    selected: _borderPreset == value,
    onSelected: (_) {
      setState(() {
        _frameWidth = width;
        if (value == 'none') _frameColorValue = null;
      });
      _preview(
        (next) => _withFrame(
          next,
          width: width,
          setColor: value == 'none',
          color: value == 'none' ? null : _frameColorValue,
        ),
      );
    },
  );

  String get _borderPreset {
    if (_frameWidth.abs() < 0.001) return 'none';
    if ((_frameWidth - 1.5).abs() < 0.001) return 'thin';
    if ((_frameWidth - 3).abs() < 0.001) return 'medium';
    return 'custom';
  }

  Future<void> _pickFrameColor() async {
    final color = await widget.onPickFrameColor(context, _frameColorValue);
    if (!mounted || color == null) return;
    setState(() => _frameColorValue = color);
    _preview(
      (next) =>
          _withFrame(next, width: _frameWidth, setColor: true, color: color),
    );
  }

  void _setFilterPreset(ImageFilterPreset preset) {
    setState(() {
      _selectedFilterId = preset.id;
      _brightness = preset.brightness;
      _contrast = preset.contrast;
      _saturation = preset.saturation;
      _warmth = preset.warmth;
    });
    _preview(
      (next) => _withFilterValues(
        next,
        brightness: preset.brightness,
        contrast: preset.contrast,
        saturation: preset.saturation,
        warmth: preset.warmth,
      ),
    );
  }

  void _setFilterValue({
    double? brightness,
    double? contrast,
    double? saturation,
    double? warmth,
  }) {
    setState(() {
      _selectedFilterId = null;
      if (brightness != null) _brightness = brightness;
      if (contrast != null) _contrast = contrast;
      if (saturation != null) _saturation = saturation;
      if (warmth != null) _warmth = warmth;
    });
    _preview(
      (next) => _withFilterValues(
        next,
        brightness: brightness,
        contrast: contrast,
        saturation: saturation,
        warmth: warmth,
      ),
    );
  }

  CanvasNode _withFilterValues(
    CanvasNode node, {
    double? brightness,
    double? contrast,
    double? saturation,
    double? warmth,
  }) {
    final payload = Map<String, dynamic>.from(node.payload);
    if (brightness != null) payload['brightness'] = brightness;
    if (contrast != null) payload['contrast'] = contrast;
    if (saturation != null) payload['saturation'] = saturation;
    if (warmth != null) payload['warmth'] = warmth;
    return node.copyWith(payload: payload);
  }

  void _setCrop(Rect crop) {
    setState(() => _crop = crop);
    _preview(
      (next) => _withPayload(next, 'crop', {
        'left': crop.left,
        'top': crop.top,
        'right': crop.right,
        'bottom': crop.bottom,
      }),
    );
  }

  Widget _cropChoice({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onTap(),
  );

  Widget _adjustmentSlider(
    BuildContext context, {
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    required Key key,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.titleMedium),
      Slider(
        key: key,
        min: min,
        max: max,
        value: value.clamp(min, max).toDouble(),
        onChanged: onChanged,
      ),
    ],
  );
}
