import 'package:flutter/material.dart';

/// Fades entry-page controls while keeping their layout stable.
class EntryChrome extends StatelessWidget {
  const EntryChrome({super.key, required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: visible ? 1 : 0,
    duration: const Duration(milliseconds: 220),
    curve: Curves.easeOut,
    child: IgnorePointer(
      ignoring: !visible,
      child: ExcludeFocus(
        excluding: !visible,
        child: ExcludeSemantics(excluding: !visible, child: child),
      ),
    ),
  );
}
