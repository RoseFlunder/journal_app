import 'package:flutter/material.dart';

import '../../../../models/entry.dart';
import '../../../../widgets/page_viewport.dart';

/// Shared paper, camera, and page-header composition for an entry editor.
///
/// Editor-specific interaction widgets are supplied by [canvas]. Keeping the
/// page host here prevents camera/layout concerns from leaking into the page
/// workflow coordinator.
class EntryEditorSurface extends StatelessWidget {
  const EntryEditorSurface({
    super.key,
    required this.child,
    required this.onScaleChanged,
    required this.canvasSize,
    required this.pageRect,
    required this.controlsBottomInset,
    required this.controlsVisible,
    required this.gesturesEnabled,
    required this.initialView,
    required this.onViewChanged,
  });

  final Widget child;
  final ValueChanged<double> onScaleChanged;
  final Size canvasSize;
  final Rect pageRect;
  final double controlsBottomInset;
  final bool controlsVisible;
  final bool gesturesEnabled;
  final ViewState? initialView;
  final ValueChanged<ViewState> onViewChanged;

  @override
  Widget build(BuildContext context) => PageViewport(
    onScaleChanged: onScaleChanged,
    canvasSize: canvasSize,
    pageRect: pageRect,
    controlsBottomInset: controlsBottomInset,
    controlsVisible: controlsVisible,
    gesturesEnabled: gesturesEnabled,
    initialView: initialView,
    onViewChanged: onViewChanged,
    child: child,
  );
}
