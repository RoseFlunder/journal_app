import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/view_state.dart';

/// Pure camera calculations shared by the page viewport and camera tests.
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
      panX: panX.isFinite ? panX : 0,
      panY: panY.isFinite ? panY : 0,
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
    final pageScale = fitScale(viewport, pageRect.size);
    final available = Size(
      (viewport.width - padding * 2).clamp(1, double.infinity),
      (viewport.height - padding * 2).clamp(1, double.infinity),
    );
    final contentScale = fitScale(available, contentRect.size);
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

  static double fitScale(Size viewport, Size content) {
    final widthScale = viewport.width / content.width;
    final heightScale = viewport.height / content.height;
    return widthScale < heightScale ? widthScale : heightScale;
  }
}

/// Owns the page camera matrix and converts it to/from persisted view state.
///
/// Widgets can use [transformation] as the `InteractiveViewer` controller,
/// while camera policy remains independent from the viewport chrome.
class CameraController extends ChangeNotifier {
  CameraController({
    this.minZoom = 0.5,
    this.maxZoom = 3.0,
    this.openingMaxZoom = 2.0,
  }) {
    transformation.addListener(_handleTransformationChanged);
  }

  final double minZoom;
  final double maxZoom;
  final double openingMaxZoom;
  final TransformationController transformation = TransformationController();

  Size _viewportSize = Size.zero;
  Rect _pageRect = Rect.zero;
  Rect _contentRect = Rect.zero;
  Offset? _initialFocus;
  Offset? _fitFocus;
  bool _legacyFocusMode = false;
  double _fitScale = 1;
  double _openingZoom = 1;
  double _zoom = 1;
  bool _initialized = false;

  Size get viewportSize => _viewportSize;
  Rect get pageRect => _pageRect;
  Rect get contentRect => _contentRect;
  double get fitScale => _fitScale;
  double get zoom => _zoom;
  bool get isInitialized => _initialized;

  /// Refreshes the region used by [fitContent] without disturbing the user's
  /// current camera. The next explicit content-fit action uses these bounds.
  void updateContentRect(Rect contentRect) {
    _contentRect = contentRect;
  }

  /// Configures the camera for a viewport and establishes its initial fit.
  void configure({
    required Size viewport,
    required Rect pageRect,
    Rect? contentRect,
    ViewState? initialView,
    Offset? initialFocus,
    Offset? fitFocus,
    bool fitContentOnFirstOpen = true,
    bool legacyFocusMode = false,
  }) {
    _viewportSize = viewport;
    _pageRect = pageRect;
    _contentRect = contentRect ?? pageRect;
    _initialFocus = initialFocus;
    _fitFocus = fitFocus;
    _legacyFocusMode = legacyFocusMode;
    _fitScale = ViewportMath.fitScale(viewport, pageRect.size);
    _openingZoom = ViewportMath.contentFitZoom(
      viewport: viewport,
      pageRect: pageRect,
      contentRect: _contentRect,
      minZoom: minZoom,
      maxZoom: openingMaxZoom,
    );
    final view = ViewportMath.normalize(
      initialView,
      minZoom: minZoom,
      maxZoom: maxZoom,
    );
    _zoom = initialView == null && fitContentOnFirstOpen
        ? _openingZoom
        : initialView == null
        ? 1
        : view.zoom;
    transformation.value = initialView == null
        ? (fitContentOnFirstOpen
              ? _contentTransform(_openingZoom)
              : _fitTransform(1, 0, 0))
        : _fitTransform(view.zoom, view.panX, view.panY);
    _initialized = true;
    notifyListeners();
  }

  /// Returns the current persisted camera state relative to the page fit.
  ViewState get viewState {
    if (!_initialized || _fitScale == 0) return const ViewState();
    final scale = transformation.value.getMaxScaleOnAxis();
    final translation = transformation.value.getTranslation();
    final zoom = (scale / _fitScale).clamp(minZoom, maxZoom).toDouble();
    final baseTranslation = _fitTransform(zoom, 0, 0).getTranslation();
    return ViewState(
      zoom: zoom,
      panX: (translation.x - baseTranslation.x) / (_fitScale * zoom),
      panY: (translation.y - baseTranslation.y) / (_fitScale * zoom),
    );
  }

  void setZoom(double zoom, {Offset? focalPoint}) {
    if (!_initialized || _fitScale == 0) return;
    final nextZoom = zoom.clamp(minZoom, maxZoom).toDouble();
    final currentScale = transformation.value.getMaxScaleOnAxis();
    if (currentScale == 0) return;
    final nextScale = _fitScale * nextZoom;
    final focal =
        focalPoint ?? Offset(_viewportSize.width / 2, _viewportSize.height / 2);
    final matrix = transformation.value.clone();
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
    transformation.value = matrix;
  }

  void fitContent() {
    if (!_initialized || _viewportSize.width <= 0 || _viewportSize.height <= 0) {
      return;
    }
    _openingZoom = ViewportMath.contentFitZoom(
      viewport: _viewportSize,
      pageRect: _pageRect,
      contentRect: _contentRect,
      minZoom: minZoom,
      maxZoom: openingMaxZoom,
    );
    transformation.value = _contentTransform(_openingZoom);
  }

  void fitPage() {
    if (!_initialized) return;
    transformation.value = _fitTransform(1, 0, 0);
  }

  void panBy(Offset delta) {
    if (!_initialized) return;
    final matrix = transformation.value.clone()
      ..translateByDouble(-delta.dx, -delta.dy, 0, 1);
    transformation.value = matrix;
  }

  void _handleTransformationChanged() {
    if (!_initialized || _fitScale == 0) return;
    final scale = transformation.value.getMaxScaleOnAxis();
    final nextZoom = (scale / _fitScale).clamp(minZoom, maxZoom).toDouble();
    if ((nextZoom - _zoom).abs() > 0.001) _zoom = nextZoom;
    notifyListeners();
  }

  Matrix4 _contentTransform(double zoom) => _centeredTransform(_contentRect, zoom);

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
    final focus = _fitFocus ?? _initialFocus;
    if (_legacyFocusMode && focus != null) {
      final baseX = _fitFocus == null
          ? -focus.dx * scale
          : _viewportSize.width / 2 - focus.dx * scale;
      final baseY = _fitFocus == null
          ? 16 - focus.dy * scale
          : _viewportSize.height / 2 - focus.dy * scale;
      return Matrix4.identity()
        ..translateByDouble(baseX + panX * scale, baseY + panY * scale, 0, 1)
        ..scaleByDouble(scale, scale, scale, 1);
    }
    return Matrix4.identity()
      ..translateByDouble(
        _viewportSize.width / 2 - _pageRect.center.dx * scale + panX * scale,
        _viewportSize.height / 2 - _pageRect.center.dy * scale + panY * scale,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, scale, 1);
  }

  @override
  void dispose() {
    transformation.removeListener(_handleTransformationChanged);
    transformation.dispose();
    super.dispose();
  }
}
