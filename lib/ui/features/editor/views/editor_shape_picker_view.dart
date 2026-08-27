import 'package:flutter/material.dart';

/// Shape choices shown by the editor's More tools menu.
class EditorShapePickerView extends StatelessWidget {
  const EditorShapePickerView({super.key});

  static const _shapes = <({String value, String label, IconData icon})>[
    (value: 'rectangle', label: 'Rectangle', icon: Icons.rectangle_outlined),
    (value: 'ellipse', label: 'Ellipse', icon: Icons.circle_outlined),
    (value: 'line', label: 'Line', icon: Icons.horizontal_rule),
    (value: 'arrow', label: 'Arrow', icon: Icons.arrow_right_alt),
  ];

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const ListTile(
          leading: Icon(Icons.category_outlined),
          title: Text('Add shape'),
        ),
        for (final option in _shapes)
          ListTile(
            leading: Icon(option.icon),
            title: Text(option.label),
            onTap: () => Navigator.pop(context, option.value),
          ),
      ],
    ),
  );
}
