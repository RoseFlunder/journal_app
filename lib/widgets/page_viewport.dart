import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/entry.dart';

class PageViewport extends StatefulWidget {
  const PageViewport({
    super.key,
    required this.child,
    this.initialView,
    this.onViewChanged,
    this.interactive = true,
    this.minZoom = 0.5,
    this.maxZoom = 3.0,
  });

  static const pageSize = Size(1000, 1414);

  final Widget child;
  final ViewState? initialView;
  final ValueChanged<ViewState>? onViewChanged;
  final bool interactive;
  final double minZoom;
  final double maxZoom;

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
      panX: panX.isFinite ? panX.clamp(-100, 100).toDouble() : 0,
      panY: panY.isFinite ? panY.clamp(-141.4, 141.4).toDouble() : 0,
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
    final nextZoom = (scale / _fitScale).clamp(
      widget.minZoom,
      widget.maxZoom,
    );
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
    widget.onViewChanged!(
      ViewState(
        zoom: zoom.toDouble(),
        panX: translation.x / (_fitScale * zoom),
        panY: translation.y / (_fitScale * zoom),
      ),
    );
  }

  void _setInitialTransform(Size size) {
    _viewportSize = size;
    _fitScale = math.min(
      size.width / PageViewport.pageSize.width,
      size.height / PageViewport.pageSize.height,
    );
    if (!widget.interactive) {
      _zoom = 1;
      _controller.value = _fitTransform(1, 0, 0);
      _ready = true;
      return;
    }
    final view = ViewportMath.normalize(
      widget.initialView,
      minZoom: widget.minZoom,
      maxZoom: widget.maxZoom,
    );
    _zoom = view.zoom;
    _controller.value = _fitTransform(view.zoom, view.panX, view.panY);
    _ready = true;
  }

  Matrix4 _fitTransform(double zoom, double panX, double panY) {
    final scale = _fitScale * zoom;
    final centeredX = (_viewportSize.width - PageViewport.pageSize.width * scale) / 2;
    final centeredY = (_viewportSize.height - PageViewport.pageSize.height * scale) / 2;
    return Matrix4.identity()
      ..translateByDouble(centeredX + panX * scale, centeredY + panY * scale, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  void _setZoom(double zoom, {Offset? focalPoint}) {
    final nextZoom = zoom.clamp(widget.minZoom, widget.maxZoom).toDouble();
    final currentScale = _controller.value.getMaxScaleOnAxis();
    final nextScale = _fitScale * nextZoom;
    final focal = focalPoint ?? Offset(_viewportSize.width / 2, _viewportSize.height / 2);
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

  void _fit() => _controller.value = _fitTransform(1, 0, 0);

  void _toggleDoubleTap() => _setZoom(_zoom == 1 ? 2 : 1);

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
                onDoubleTap: widget.interactive ? _toggleDoubleTap : null,
                child: InteractiveViewer(
                  transformationController: _controller,
                  minScale: widget.minZoom,
                  maxScale: widget.maxZoom * 2,
                  constrained: false,
                  panEnabled: widget.interactive,
                  scaleEnabled: widget.interactive,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  child: SizedBox(
                    width: PageViewport.pageSize.width,
                    height: PageViewport.pageSize.height,
                    child: widget.child,
                  ),
                ),
              ),
              if (widget.interactive && _zoom > 1.001)
                Positioned(
                  right: 16,
                  bottom: 16,
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
            ],
          ),
        );
      },
    );
  }
}