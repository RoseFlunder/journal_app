import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../models/document.dart';

/// Numeric transform editor. It owns only its text controllers and emits an
/// immutable transform plus opacity when the user applies the values.
class EditorTransformInspectorView extends StatefulWidget {
  const EditorTransformInspectorView({
    super.key,
    required this.node,
    required this.onApply,
    required this.onNudge,
  });

  final CanvasNode node;
  final Future<void> Function(Transform2D transform, double opacity) onApply;
  final ValueChanged<Offset> onNudge;

  @override
  State<EditorTransformInspectorView> createState() =>
      _EditorTransformInspectorViewState();
}

class _EditorTransformInspectorViewState
    extends State<EditorTransformInspectorView> {
  late final TextEditingController _x =
      TextEditingController(text: widget.node.x.toStringAsFixed(1));
  late final TextEditingController _y =
      TextEditingController(text: widget.node.y.toStringAsFixed(1));
  late final TextEditingController _width =
      TextEditingController(text: widget.node.w.toStringAsFixed(1));
  late final TextEditingController _height =
      TextEditingController(text: widget.node.h.toStringAsFixed(1));
  late final TextEditingController _rotation = TextEditingController(
    text: (widget.node.rotation * 180 / math.pi).toStringAsFixed(1),
  );
  late final TextEditingController _opacity = TextEditingController(
    text: (widget.node.opacity * 100).round().toString(),
  );

  @override
  void dispose() {
    _x.dispose();
    _y.dispose();
    _width.dispose();
    _height.dispose();
    _rotation.dispose();
    _opacity.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final x = double.tryParse(_x.text);
    final y = double.tryParse(_y.text);
    final width = double.tryParse(_width.text);
    final height = double.tryParse(_height.text);
    final degrees = double.tryParse(_rotation.text);
    final opacity = double.tryParse(_opacity.text);
    if ([x, y, width, height, degrees, opacity].any((value) => value == null)) {
      return;
    }
    await widget.onApply(
      Transform2D(
        x: x!,
        y: y!,
        width: math.max(16, width!),
        height: math.max(10, height!),
        rotation: degrees! * math.pi / 180,
      ),
      (opacity! / 100).clamp(0.0, 1.0).toDouble(),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Precise transform', style: TextStyle(fontSize: 22)),
          if (widget.node.locked)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Unlock this block before editing its transform.'),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _numberField('X', _x)),
              const SizedBox(width: 12),
              Expanded(child: _numberField('Y', _y)),
            ],
          ),
          Row(
            children: [
              Expanded(child: _numberField('Width', _width)),
              const SizedBox(width: 12),
              Expanded(child: _numberField('Height', _height)),
            ],
          ),
          Row(
            children: [
              Expanded(child: _numberField('Rotation °', _rotation)),
              const SizedBox(width: 12),
              Expanded(child: _numberField('Opacity %', _opacity)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            children: [
              _nudgeButton('←', const Offset(-1, 0)),
              _nudgeButton('↑', const Offset(0, -1)),
              _nudgeButton('↓', const Offset(0, 1)),
              _nudgeButton('→', const Offset(1, 0)),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: widget.node.locked ? null : _apply,
              child: const Text('Apply'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _numberField(String label, TextEditingController controller) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          decoration: InputDecoration(labelText: label),
        ),
      );

  Widget _nudgeButton(String label, Offset delta) => Semantics(
    button: true,
    label: 'Nudge $label',
    child: OutlinedButton(
      onPressed: () => widget.onNudge(delta),
      child: Text(label),
    ),
  );
}
