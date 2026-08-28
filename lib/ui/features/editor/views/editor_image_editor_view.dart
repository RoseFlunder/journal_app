import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../models/document.dart';

/// Non-destructive image/sticker editor. The view keeps only sheet-local
/// slider state and emits immutable node updates to the editor view model.
class EditorImageEditorView extends StatefulWidget {
  const EditorImageEditorView({
    super.key,
    required this.node,
    required this.onCommit,
    required this.onPreview,
    required this.onBeginTransaction,
    required this.onEndTransaction,
  });

  final CanvasNode node;
  final void Function(CanvasNode node, String label) onCommit;
  final void Function(CanvasNode node, String label) onPreview;
  final ValueChanged<String> onBeginTransaction;
  final VoidCallback onEndTransaction;

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
  late String _imageMask = widget.node.imageMask;

  CanvasNode _withPayload(CanvasNode node, String key, Object? value) {
    final payload = Map<String, dynamic>.from(node.payload);
    if (value == null) {
      payload.remove(key);
    } else {
      payload[key] = value;
    }
    return node.copyWith(payload: payload);
  }

  void _commit(
    CanvasNode Function(CanvasNode node) update, {
    String label = 'Edit image',
  }) {
    _currentNode = update(_currentNode);
    widget.onCommit(_currentNode, label);
  }

  void _preview(
    CanvasNode Function(CanvasNode node) update, {
    required String label,
  }) {
    _currentNode = update(_currentNode);
    widget.onPreview(_currentNode, label);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.42,
      maxChildSize: 0.9,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          const ListTile(
            leading: Icon(Icons.tune),
            title: Text('Edit image'),
            subtitle: Text('Non-destructive crop and presentation'),
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
                  _commit((next) => _withPayload(next, 'crop', null));
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
          const SizedBox(height: 18),
          Text(
            'Opacity ${(_opacity * 100).round()}%',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Slider(
            min: 0.1,
            max: 1,
            value: _opacity,
            label: '${(_opacity * 100).round()}%',
            onChangeStart: (_) => widget.onBeginTransaction('Image opacity'),
            onChanged: (value) {
              setState(() => _opacity = value);
              _preview((next) => next.copyWith(opacity: value), label: 'Image opacity');
            },
            onChangeEnd: (_) => widget.onEndTransaction(),
          ),
          _adjustmentSlider(
            context,
            label: 'Brightness',
            value: _brightness,
            min: -1,
            max: 1,
            onStart: () => widget.onBeginTransaction('Image brightness'),
            onChanged: (value) {
              setState(() => _brightness = value);
              _preview(
                (next) => _withPayload(next, 'brightness', value),
                label: 'Image brightness',
              );
            },
            onEnd: widget.onEndTransaction,
          ),
          _adjustmentSlider(
            context,
            label: 'Contrast',
            value: _contrast,
            min: -1,
            max: 1,
            onStart: () => widget.onBeginTransaction('Image contrast'),
            onChanged: (value) {
              setState(() => _contrast = value);
              _preview(
                (next) => _withPayload(next, 'contrast', value),
                label: 'Image contrast',
              );
            },
            onEnd: widget.onEndTransaction,
          ),
          _adjustmentSlider(
            context,
            label: 'Saturation',
            value: _saturation,
            min: 0,
            max: 2,
            onStart: () => widget.onBeginTransaction('Image saturation'),
            onChanged: (value) {
              setState(() => _saturation = value);
              _preview(
                (next) => _withPayload(next, 'saturation', value),
                label: 'Image saturation',
              );
            },
            onEnd: widget.onEndTransaction,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => _commit(
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
                onPressed: () => _commit(
                  (next) => _withPayload(next, 'flipX', next.payload['flipX'] != true),
                ),
                icon: const Icon(Icons.flip),
                label: const Text('Flip horizontal'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _commit(
                  (next) => _withPayload(next, 'flipY', next.payload['flipY'] != true),
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
              _commit((next) => _withPayload(next, 'imageMask', nextMask));
            },
          ),
        ],
      ),
    ),
  );

  void _setCrop(Rect crop) {
    setState(() => _crop = crop);
    _commit(
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
    required VoidCallback onStart,
    required ValueChanged<double> onChanged,
    required VoidCallback onEnd,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.titleMedium),
      Slider(
        min: min,
        max: max,
        value: value.clamp(min, max).toDouble(),
        onChangeStart: (_) => onStart(),
        onChanged: onChanged,
        onChangeEnd: (_) => onEnd(),
      ),
    ],
  );
}
