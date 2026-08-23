import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/entry.dart';
import 'entry_chrome.dart';

class PageViewport extends StatefulWidget {
  const PageViewport({
    super.key,
    required this.child,
    this.initialView,
    this.onViewChanged,
    this.interactive = true,
    this.controlsVisible = true,
    this.minZoom = 0.5,
    this.maxZoom = 3.0,
    this.canvasSize = pageSize,
    this.fitSize = pageSize,
    this.initialFocus,
    this.fitFocus,
  });

  static const pageSize = Size(1000, 1414);
  static const modelPageSize = Size(100, 141.4);
  static const modelToRenderScale = 10.0;

  static Offset modelToRender(Offset point) => point * modelToRenderScale;

  static Size modelSizeToRender(Size size) => size * modelToRenderScale;

  static Offset renderToModel(Offset point) => point / modelToRenderScale;

  static Size renderSizeToModel(Size size) => size / modelToRenderScale;

  final Widget child;
  final ViewState? initialView;
  final ValueChanged<ViewState>? onViewChanged;
  final bool interactive;
  final bool controlsVisible;
  final double minZoom;
  final double maxZoom;
  final Size canvasSize;

  /// The content region that should be fully visible at fit/reset scale.
  final Size fitSize;
  final Offset? initialFocus;

  /// Optional focus used by Fit/reset controls. This lets an entry open near
  /// its header while Fit centers the complete framed page.
  final Offset? fitFocus;

  @override
  State<PageViewport> createState() => _PageViewportState();
}

class ViewportMath {
  const ViewportMath._();

  static ViewState normalize(
    ViewState? value, {
    double minZoom = 0.5,
    double maxZoom = 3.0,
  }) {
    final zoom = value?.zoom ?? 1;
    final panX = value?.panX ?? 0;
    final panY = value?.panY ?? 0;
    return ViewState(
      zoom: zoom.isFinite ? zoom.clamp(minZoom, maxZoom).toDouble() : 1,
      panX: panX.isFinite ? panX.clamp(-10000, 10000).toDouble() : 0,
      panY: panY.isFinite ? panY.clamp(-10000, 10000).toDouble() : 0,
    );
  }
}

class _PageViewportState extends State<PageViewport> {
  final TransformationController _controller = TransformationController();
  Timer? _persistTimer;
  Size _viewportSize = Size.zero;
  double _fitScale = 1;
  bool _ready = false;
  double _zoom = 1;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleTransformChanged);
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    _controller
      ..removeListener(_handleTransformChanged)
      ..dispose();
    super.dispose();
  }

  void _handleTransformChanged() {
    if (!_ready || !widget.interactive) return;
    final scale = _controller.value.getMaxScaleOnAxis();
    if (_fitScale == 0) return;
    final nextZoom = (scale / _fitScale).clamp(widget.minZoom, widget.maxZoom);
    if ((nextZoom - _zoom).abs() > 0.001) {
      setState(() => _zoom = nextZoom.toDouble());
    }
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 250), _persistView);
  }

  void _persistView() {
    if (!mounted || widget.onViewChanged == null) return;
    final scale = _controller.value.getMaxScaleOnAxis();
    final translation = _controller.value.getTranslation();
    final zoom = (scale / _fitScale).clamp(widget.minZoom, widget.maxZoom);
    final baseTransform = _fitTransform(zoom.toDouble(), 0, 0);
    final baseTranslation = baseTransform.getTranslation();
    widget.onViewChanged!(
      ViewState(
        zoom: zoom.toDouble(),
        panX: (translation.x - baseTranslation.x) / (_fitScale * zoom),
        panY: (translation.y - baseTranslation.y) / (_fitScale * zoom),
      ),
    );
  }

  void _setInitialTransform(Size size) {
    _viewportSize = size;
    final widthScale = size.width / widget.fitSize.width;
    final heightScale = size.height / widget.fitSize.height;
    _fitScale = widthScale < heightScale ? widthScale : heightScale;
    if (!widget.interactive) {
      _zoom = 1;
      _controller.value = _resetTransform();
      _ready = true;
      return;
    }
    final view = ViewportMath.normalize(
      widget.initialView,
      minZoom: widget.minZoom,
      maxZoom: widget.maxZoom,
    );
    _zoom = view.zoom;
    _controller.value = widget.initialView == null
        ? _resetTransform(zoom: view.zoom, focus: widget.initialFocus)
        : _fitTransform(view.zoom, view.panX, view.panY);
    _ready = true;
  }

  Matrix4 _resetTransform({double zoom = 1, Offset? focus}) {
    final scale = _fitScale * zoom;
    final target = focus ?? widget.initialFocus;
    if (target == null) return _fitTransform(zoom, 0, 0);
    if (focus == widget.fitFocus && widget.fitFocus != null) {
      return Matrix4.identity()
        ..translateByDouble(
          _viewportSize.width / 2 - target.dx * scale,
          _viewportSize.height / 2 - target.dy * scale,
          0,
          1,
        )
        ..scaleByDouble(scale, scale, scale, 1);
    }
    return Matrix4.identity()
      ..translateByDouble(-target.dx * scale, 16 - target.dy * scale, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  Matrix4 _fitTransform(double zoom, double panX, double panY) {
    final scale = _fitScale * zoom;
    final focus = widget.fitFocus ?? widget.initialFocus;
    final double baseX;
    final double baseY;
    if (focus == null) {
      baseX = (_viewportSize.width - widget.canvasSize.width * scale) / 2;
      baseY = (_viewportSize.height - widget.canvasSize.height * scale) / 2;
    } else if (widget.fitFocus == null) {
      baseX = -focus.dx * scale;
      baseY = 16 - focus.dy * scale;
    } else {
      baseX = _viewportSize.width / 2 - focus.dx * scale;
      baseY = _viewportSize.height / 2 - focus.dy * scale;
    }
    return Matrix4.identity()
      ..translateByDouble(baseX + panX * scale, baseY + panY * scale, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  void _setZoom(double zoom, {Offset? focalPoint}) {
    final nextZoom = zoom.clamp(widget.minZoom, widget.maxZoom).toDouble();
    final currentScale = _controller.value.getMaxScaleOnAxis();
    final nextScale = _fitScale * nextZoom;
    final focal =
        focalPoint ?? Offset(_viewportSize.width / 2, _viewportSize.height / 2);
    final matrix = _controller.value.clone();
    final before = matrix.clone()..invert();
    final contentPoint = MatrixUtils.transformPoint(before, focal);
    matrix
      ..setEntry(0, 0, nextScale)
      ..setEntry(1, 1, nextScale)
      ..setEntry(2, 2, nextScale)
      ..setTranslationRaw(
        focal.dx - contentPoint.dx * nextScale,
        focal.dy - contentPoint.dy * nextScale,
        0,
      );
    if (currentScale == 0) return;
    _controller.value = matrix;
  }

  void _fit() => _controller.value = _resetTransform(focus: widget.fitFocus);

  void _resetView() =>
      _controller.value = _resetTransform(focus: widget.fitFocus);

  void _handlePointerSignal(PointerSignalEvent event) {
    if (!widget.interactive || event is! PointerScrollEvent) return;
    final isZoom = HardwareKeyboard.instance.logicalKeysPressed.contains(
      LogicalKeyboardKey.control,
    );
    if (isZoom) {
      final factor = event.scrollDelta.dy < 0 ? 1.12 : 0.89;
      _setZoom(_zoom * factor, focalPoint: event.position);
      return;
    }
    final matrix = _controller.value.clone();
    final delta = event.scrollDelta;
    matrix.translateByDouble(-delta.dx, -delta.dy, 0, 1);
    _controller.value = matrix;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (size != _viewportSize && size.width > 0 && size.height > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _setInitialTransform(size);
          });
        }
        return Listener(
          onPointerSignal: _handlePointerSignal,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                onDoubleTap: widget.interactive ? _resetView : null,
                child: InteractiveViewer(
                  transformationController: _controller,
                  minScale: widget.minZoom,
                  maxScale: widget.maxZoom * 2,
                  constrained: false,
                  panEnabled: widget.interactive,
                  scaleEnabled: widget.interactive,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  child: SizedBox(
                    width: widget.canvasSize.width,
                    height: widget.canvasSize.height,
                    child: widget.child,
                  ),
                ),
              ),
              if (widget.interactive)
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: EntryChrome(
                    visible: widget.controlsVisible,
                    child: IconButton(
                      tooltip: 'Reset view',
                      color: Colors.white,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.55),
                      ),
                      onPressed: _resetView,
                      icon: const Icon(Icons.center_focus_strong),
                    ),
                  ),
                ),
              if (widget.interactive && _zoom > 1.001)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: EntryChrome(
                    visible: widget.controlsVisible,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Zoom out',
                            color: Colors.white,
                            onPressed: () => _setZoom(_zoom / 1.2),
                            icon: const Icon(Icons.remove),
                          ),
                          IconButton(
                            tooltip: 'Fit page',
                            color: Colors.white,
                            onPressed: _fit,
                            icon: const Icon(Icons.fit_screen_outlined),
                          ),
                          IconButton(
                            tooltip: 'Zoom in',
                            color: Colors.white,
                            onPressed: () => _setZoom(_zoom * 1.2),
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
