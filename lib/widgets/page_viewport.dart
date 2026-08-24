import 'dart:async';
import 'dart:math' as math;

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
    this.onScaleChanged,
    this.interactive = true,
    this.gesturesEnabled = true,
    this.controlsVisible = true,
    this.minZoom = 0.5,
    this.maxZoom = 3.0,
    this.canvasSize = pageSize,
    this.fitSize = pageSize,
    this.pageRect,
    this.contentRect,
    this.openingMaxZoom = 2.0,
    this.controlsBottomInset = 12,
    this.boardMode = false,
    this.boardTopInset = 52,
    // Kept for source compatibility with callers that used the old focused
    // page API. New callers should provide pageRect/contentRect instead.
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

  /// Reports the current canvas-to-screen scale for screen-space controls.
  final ValueChanged<double>? onScaleChanged;
  final bool interactive;
  final bool gesturesEnabled;
  final bool controlsVisible;
  final double minZoom;
  final double maxZoom;
  final Size canvasSize;

  /// Legacy page rectangle shorthand. It is used when [pageRect] is omitted.
  final Size fitSize;

  /// The paper rectangle in canvas coordinates.
  final Rect? pageRect;

  /// The visible content rectangle in canvas coordinates. A null value means
  /// the paper itself is the opening fit region.
  final Rect? contentRect;

  /// Maximum page-relative zoom used by the automatic content fit.
  final double openingMaxZoom;

  /// Extra space reserved below camera controls, for example for the editor
  /// toolbar.
  final double controlsBottomInset;

  /// Presents the shared camera as a paperless infinite board. It keeps the
  /// same persisted transform model while removing page-specific affordances.
  final bool boardMode;

  /// Screen-space breathing room above initial and fit board content.
  final double boardTopInset;

  @Deprecated('Use pageRect/contentRect')
  final Offset? initialFocus;

  @Deprecated('Use pageRect/contentRect')
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

  static double contentFitZoom({
    required Size viewport,
    required Rect pageRect,
    required Rect contentRect,
    required double minZoom,
    required double maxZoom,
    double padding = 24,
  }) {
    final pageScale = _fitScale(viewport, pageRect.size);
    final available = Size(
      (viewport.width - padding * 2).clamp(1, double.infinity),
      (viewport.height - padding * 2).clamp(1, double.infinity),
    );
    final contentScale = _fitScale(available, contentRect.size);
    final zoom = contentScale / pageScale;
    return zoom.clamp(minZoom, maxZoom).toDouble();
  }

  static Rect rotatedRectBounds(Rect rect, double rotation) {
    final sine = math.sin(rotation).abs();
    final cosine = math.cos(rotation).abs();
    final size = Size(
      rect.width * cosine + rect.height * sine,
      rect.width * sine + rect.height * cosine,
    );
    return Rect.fromCenter(
      center: rect.center,
      width: size.width,
      height: size.height,
    );
  }

  static double _fitScale(Size viewport, Size content) {
    final widthScale = viewport.width / content.width;
    final heightScale = viewport.height / content.height;
    return widthScale < heightScale ? widthScale : heightScale;
  }
}

class _PageViewportState extends State<PageViewport> {
  final TransformationController _controller = TransformationController();
  Timer? _persistTimer;
  Size _viewportSize = Size.zero;
  double _fitScale = 1;
  double _openingZoom = 1;
  bool _ready = false;
  double _zoom = 1;

  Rect get _pageRect =>
      widget.pageRect ??
      Rect.fromLTWH(0, 0, widget.fitSize.width, widget.fitSize.height);

  Rect get _contentRect => widget.contentRect ?? _pageRect;

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
    widget.onScaleChanged?.call(scale);
    if ((nextZoom - _zoom).abs() > 0.001 && mounted) {
      setState(() => _zoom = nextZoom.toDouble());
    }
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 250), _persistView);
  }

  void _persistView() {
    if (!mounted || widget.onViewChanged == null || _fitScale == 0) return;
    final scale = _controller.value.getMaxScaleOnAxis();
    final translation = _controller.value.getTranslation();
    final zoom = (scale / _fitScale).clamp(widget.minZoom, widget.maxZoom);
    final baseTranslation = _fitTransform(
      zoom.toDouble(),
      0,
      0,
    ).getTranslation();
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
    _fitScale = _fitScaleFor(size, _pageRect.size);
    _openingZoom = ViewportMath.contentFitZoom(
      viewport: size,
      pageRect: _pageRect,
      contentRect: _contentRect,
      minZoom: widget.minZoom,
      maxZoom: widget.openingMaxZoom,
    );
    if (!widget.interactive) {
      _zoom = 1;
      _controller.value = _fitTransform(1, 0, 0);
      _ready = true;
      widget.onScaleChanged?.call(_controller.value.getMaxScaleOnAxis());
      return;
    }
    final view = ViewportMath.normalize(
      widget.initialView,
      minZoom: widget.minZoom,
      maxZoom: widget.maxZoom,
    );
    _zoom = widget.initialView == null ? _openingZoom : view.zoom;
    _controller.value = widget.initialView == null
        ? _contentTransform(_openingZoom)
        : _fitTransform(view.zoom, view.panX, view.panY);
    _ready = true;
    widget.onScaleChanged?.call(_controller.value.getMaxScaleOnAxis());
    if (mounted) setState(() {});
  }

  double _fitScaleFor(Size viewport, Size content) {
    final widthScale = viewport.width / content.width;
    final heightScale = viewport.height / content.height;
    return widthScale < heightScale ? widthScale : heightScale;
  }

  Matrix4 _contentTransform(double zoom) {
    if (!widget.boardMode) return _centeredTransform(_contentRect, zoom);
    final scale = _fitScale * zoom;
    return Matrix4.identity()
      ..translateByDouble(
        _viewportSize.width / 2 - _contentRect.center.dx * scale,
        widget.boardTopInset - _contentRect.top * scale,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, scale, 1);
  }

  Matrix4 _centeredTransform(Rect rect, double zoom) {
    final scale = _fitScale * zoom;
    return Matrix4.identity()
      ..translateByDouble(
        _viewportSize.width / 2 - rect.center.dx * scale,
        _viewportSize.height / 2 - rect.center.dy * scale,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, scale, 1);
  }

  Matrix4 _fitTransform(double zoom, double panX, double panY) {
    final scale = _fitScale * zoom;
    final focus = widget.fitFocus ?? widget.initialFocus;
    if (widget.pageRect == null && focus != null) {
      final baseX = widget.fitFocus == null
          ? -focus.dx * scale
          : _viewportSize.width / 2 - focus.dx * scale;
      final baseY = widget.fitFocus == null
          ? 16 - focus.dy * scale
          : _viewportSize.height / 2 - focus.dy * scale;
      return Matrix4.identity()
        ..translateByDouble(baseX + panX * scale, baseY + panY * scale, 0, 1)
        ..scaleByDouble(scale, scale, scale, 1);
    }
    final page = _pageRect;
    return Matrix4.identity()
      ..translateByDouble(
        _viewportSize.width / 2 - page.center.dx * scale + panX * scale,
        _viewportSize.height / 2 - page.center.dy * scale + panY * scale,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, scale, 1);
  }

  void _setZoom(double zoom, {Offset? focalPoint}) {
    if (_fitScale == 0) return;
    final nextZoom = zoom.clamp(widget.minZoom, widget.maxZoom).toDouble();
    final currentScale = _controller.value.getMaxScaleOnAxis();
    if (currentScale == 0) return;
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
    _controller.value = matrix;
  }

  void _fitContent() {
    if (_viewportSize.width <= 0 || _viewportSize.height <= 0) return;
    _openingZoom = ViewportMath.contentFitZoom(
      viewport: _viewportSize,
      pageRect: _pageRect,
      contentRect: _contentRect,
      minZoom: widget.minZoom,
      maxZoom: widget.openingMaxZoom,
    );
    _controller.value = _contentTransform(_openingZoom);
  }

  void _fitPage() => _controller.value = _fitTransform(1, 0, 0);

  void _handlePointerSignal(PointerSignalEvent event) {
    if (!widget.interactive ||
        !widget.gesturesEnabled ||
        event is! PointerScrollEvent) {
      return;
    }
    final isZoom = HardwareKeyboard.instance.logicalKeysPressed.contains(
      LogicalKeyboardKey.control,
    );
    if (isZoom) {
      final box = context.findRenderObject() as RenderBox?;
      final focal = box?.globalToLocal(event.position);
      final factor = event.scrollDelta.dy < 0 ? 1.12 : 0.89;
      _setZoom(_zoom * factor, focalPoint: focal);
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
        final minScale = _fitScale * widget.minZoom;
        final maxScale = _fitScale * widget.maxZoom;
        return Listener(
          onPointerSignal: _handlePointerSignal,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                onDoubleTap: widget.interactive && widget.gesturesEnabled
                    ? _fitContent
                    : null,
                child: InteractiveViewer(
                  transformationController: _controller,
                  minScale: minScale > 0 ? minScale : widget.minZoom,
                  maxScale: maxScale > 0 ? maxScale : widget.maxZoom,
                  constrained: false,
                  panEnabled: widget.interactive && widget.gesturesEnabled,
                  scaleEnabled: widget.interactive && widget.gesturesEnabled,
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
                  right: 16,
                  bottom: widget.controlsBottomInset,
                  child: EntryChrome(
                    visible: widget.controlsVisible,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Zoom out',
                            color: Colors.white,
                            onPressed: _zoom <= widget.minZoom + 0.001
                                ? null
                                : () => _setZoom(_zoom / 1.2),
                            icon: const Icon(Icons.remove),
                          ),
                          Semantics(
                            label: 'Zoom ${(_zoom * 100).round()} percent',
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Text(
                                '${(_zoom * 100).round()}%',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Fit content',
                            color: Colors.white,
                            onPressed: _fitContent,
                            icon: const Icon(Icons.center_focus_strong),
                          ),
                          IconButton(
                            tooltip: widget.boardMode
                                ? 'Center board'
                                : 'Fit page',
                            color: Colors.white,
                            onPressed: _fitPage,
                            icon: Icon(
                              widget.boardMode
                                  ? Icons.filter_center_focus_outlined
                                  : Icons.fit_screen_outlined,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Zoom in',
                            color: Colors.white,
                            onPressed: _zoom >= widget.maxZoom - 0.001
                                ? null
                                : () => _setZoom(_zoom * 1.2),
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
