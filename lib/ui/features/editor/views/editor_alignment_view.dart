import 'package:flutter/material.dart';

/// Alignment choices for the current immutable selection.
class EditorAlignmentView extends StatelessWidget {
  const EditorAlignmentView({super.key});

  static const _choices = <({
    String label,
    IconData icon,
    Alignment alignment,
  })>[
    (
      label: 'Align left',
      icon: Icons.format_align_left,
      alignment: Alignment.centerLeft,
    ),
    (
      label: 'Align center',
      icon: Icons.format_align_center,
      alignment: Alignment.center,
    ),
    (
      label: 'Align right',
      icon: Icons.format_align_right,
      alignment: Alignment.centerRight,
    ),
    (
      label: 'Align top',
      icon: Icons.vertical_align_top,
      alignment: Alignment.topCenter,
    ),
    (
      label: 'Align middle',
      icon: Icons.vertical_align_center,
      alignment: Alignment.center,
    ),
    (
      label: 'Align bottom',
      icon: Icons.vertical_align_bottom,
      alignment: Alignment.bottomCenter,
    ),
  ];

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const ListTile(
          leading: Icon(Icons.align_horizontal_center_outlined),
          title: Text('Align selection'),
        ),
        for (final choice in _choices)
          ListTile(
            leading: Icon(choice.icon),
            title: Text(choice.label),
            onTap: () => Navigator.pop(context, choice.alignment),
          ),
      ],
    ),
  );
}
