import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/view_state.dart';
import 'camera_controller.dart';
import 'entry_chrome.dart';

export 'camera_controller.dart' show CameraController, ViewportMath;

/// Transient camera information used to avoid building content outside the
/// visible portion of a finite page. This is presentation state only and is
/// never persisted with the document.
class PageViewportSnapshot {
  const PageViewportSnapshot({
    required this.scale,
    required this.visibleCanvasRect,
  });

  final double scale;
  final Rect visibleCanvasRect;
}

class PageViewport extends StatefulWidget {
  const PageViewport({
    super.key,
    required this.child,
    this.initialView,
    this.onViewChanged,
    this.onScaleChanged,
    this.onViewportChanged,
    this.interactive = true,
    this.gesturesEnabled = true,
    this.panEnabled = true,
    this.controlsVisible = true,
    this.minZoom = 0.5,
    this.maxZoom = 3.0,
    this.canvasSize = pageSize,
    this.fitSize = pageSize,
    this.pageRect,
    this.contentRect,
    this.openingMaxZoom = 2.0,
    this.controlsBottomInset = 12,
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
  final ValueChanged<PageViewportSnapshot>? onViewportChanged;
  final bool interactive;
  final bool gesturesEnabled;

  /// Whether pointer gestures may translate the page camera.
  ///
  /// This is independent from [gesturesEnabled] so an editor can suppress
  /// camera panning while retaining other gesture-driven interactions such as
  /// Ctrl+wheel zoom.
  final bool panEnabled;
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

  @Deprecated('Use pageRect/contentRect')
  final Offset? initialFocus;

  @Deprecated('Use pageRect/contentRect')
  final Offset? fitFocus;

  @override
  State<PageViewport> createState() => _PageViewportState();
}

class _PageViewportState extends State<PageViewport> {
  late final CameraController _camera;
  Timer? _persistTimer;
  Timer? _viewportTimer;
  Timer? _doubleTapTimer;
  int? _tapPointer;
  Offset? _tapDownPosition;
  Duration? _lastTapTime;
  Offset? _lastTapPosition;
  bool _tapCandidate = false;
  bool _ready = false;

  Rect get _pageRect =>
      widget.pageRect ??
      Rect.fromLTWH(0, 0, widget.fitSize.width, widget.fitSize.height);

  Rect get _contentRect => widget.contentRect ?? _pageRect;

  @override
  void initState() {
    super.initState();
    _camera = CameraController(
      minZoom: widget.minZoom,
      maxZoom: widget.maxZoom,
      openingMaxZoom: widget.openingMaxZoom,
    );
    _camera.addListener(_handleCameraChanged);
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    _viewportTimer?.cancel();
    _doubleTapTimer?.cancel();
    _camera.removeListener(_handleCameraChanged);
    _camera.dispose();
    super.dispose();
  }

  void _handleCameraChanged() {
    if (!_ready || !widget.interactive) return;
    final scale = _camera.transformation.value.getMaxScaleOnAxis();
    widget.onScaleChanged?.call(scale);
    if (mounted) {
      setState(() {});
    }
    _viewportTimer?.cancel();
    _viewportTimer = Timer(
      const Duration(milliseconds: 50),
      _emitViewportSnapshot,
    );
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 250), _persistView);
  }

  void _persistView() {
    if (!mounted || widget.onViewChanged == null) return;
    widget.onViewChanged!(_camera.viewState);
  }

  void _emitViewportSnapshot() {
    final callback = widget.onViewportChanged;
    final viewport = _camera.viewportSize;
    if (!mounted || callback == null || viewport.isEmpty) return;
    final inverse = Matrix4.copy(_camera.transformation.value);
    if (inverse.invert() == 0) return;
    callback(
      PageViewportSnapshot(
        scale: _camera.transformation.value.getMaxScaleOnAxis(),
        visibleCanvasRect: MatrixUtils.transformRect(
          inverse,
          Offset.zero & viewport,
        ),
      ),
    );
  }

  void _setInitialTransform(Size size) {
    _camera.configure(
      viewport: size,
      pageRect: _pageRect,
      contentRect: _contentRect,
      initialView: widget.initialView,
      initialFocus: widget.initialFocus,
      fitFocus: widget.fitFocus,
      fitContentOnFirstOpen: widget.interactive,
      legacyFocusMode: widget.pageRect == null,
    );
    if (!widget.interactive) {
      _ready = true;
      widget.onScaleChanged?.call(
        _camera.transformation.value.getMaxScaleOnAxis(),
      );
      return;
    }
    _ready = true;
    widget.onScaleChanged?.call(
      _camera.transformation.value.getMaxScaleOnAxis(),
    );
    _emitViewportSnapshot();
    if (mounted) setState(() {});
  }

  void _setZoom(double zoom, {Offset? focalPoint}) {
    _camera.setZoom(zoom, focalPoint: focalPoint);
  }

  void _fitContent() {
    _camera.fitContent();
  }

  void _fitPage() {
    _camera.fitPage();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (!widget.interactive ||
        !widget.gesturesEnabled ||
        event is! PointerScrollEvent) {
      return;
    }
    final isZoom = HardwareKeyboard.instance.isControlPressed;
    if (isZoom) {
      final box = context.findRenderObject() as RenderBox?;
      final focal = box?.globalToLocal(event.position);
      final factor = event.scrollDelta.dy < 0 ? 1.12 : 0.89;
      _setZoom(_camera.zoom * factor, focalPoint: focal);
      return;
    }
    if (!widget.panEnabled) return;
    _camera.panBy(event.scrollDelta);
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!_canHandleTap(event) || _tapPointer != null) return;
    _tapPointer = event.pointer;
    _tapDownPosition = event.localPosition;
    _tapCandidate = true;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_tapPointer != event.pointer || _tapDownPosition == null) return;
    if ((event.localPosition - _tapDownPosition!).distance > kTouchSlop) {
      _tapCandidate = false;
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_tapPointer != event.pointer) return;
    final downPosition = _tapDownPosition;
    final isTap =
        _tapCandidate &&
        downPosition != null &&
        (event.localPosition - downPosition).distance <= kTouchSlop;
    _tapPointer = null;
    _tapDownPosition = null;
    _tapCandidate = false;
    if (!isTap || !widget.interactive || !widget.gesturesEnabled) return;

    final lastTime = _lastTapTime;
    final lastPosition = _lastTapPosition;
    final isDoubleTap =
        lastTime != null &&
        lastPosition != null &&
        event.timeStamp - lastTime <= kDoubleTapTimeout &&
        (event.localPosition - lastPosition).distance <= kDoubleTapSlop;
    if (isDoubleTap) {
      _doubleTapTimer?.cancel();
      _lastTapTime = null;
      _lastTapPosition = null;
      _fitContent();
      return;
    }

    _lastTapTime = event.timeStamp;
    _lastTapPosition = event.localPosition;
    _doubleTapTimer?.cancel();
    _doubleTapTimer = Timer(kDoubleTapTimeout, () {
      _lastTapTime = null;
      _lastTapPosition = null;
    });
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_tapPointer != event.pointer) return;
    _tapPointer = null;
    _tapDownPosition = null;
    _tapCandidate = false;
  }

  bool _canHandleTap(PointerDownEvent event) =>
      widget.interactive &&
      widget.gesturesEnabled &&
      event.buttons == kPrimaryButton &&
      event.kind != PointerDeviceKind.trackpad;

  bool get _desktopWheelMode =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.windows;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (size != _camera.viewportSize && size.width > 0 && size.height > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _setInitialTransform(size);
          });
        }
        final minScale = _camera.fitScale * widget.minZoom;
        final maxScale = _camera.fitScale * widget.maxZoom;
        final boundaryMargin = _desktopWheelMode
            ? const EdgeInsets.all(double.infinity)
            : const EdgeInsets.all(64);
        return Listener(
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerUp: _handlePointerUp,
          onPointerCancel: _handlePointerCancel,
          onPointerSignal: _handlePointerSignal,
          child: Stack(
            fit: StackFit.expand,
            children: [
              InteractiveViewer(
                transformationController: _camera.transformation,
                minScale: minScale > 0 ? minScale : widget.minZoom,
                maxScale: maxScale > 0 ? maxScale : widget.maxZoom,
                constrained: false,
                panEnabled:
                    widget.interactive &&
                    widget.gesturesEnabled &&
                    widget.panEnabled,
                // InteractiveViewer scales every mouse-wheel event by
                // default. Windows and Web use the explicit handler above
                // so only Ctrl+wheel zooms; plain wheel input pans.
                scaleEnabled:
                    widget.interactive &&
                    widget.gesturesEnabled &&
                    !_desktopWheelMode,
                boundaryMargin: boundaryMargin,
                child: SizedBox(
                  width: widget.canvasSize.width,
                  height: widget.canvasSize.height,
                  child: widget.child,
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
                            onPressed: _camera.zoom <= widget.minZoom + 0.001
                                ? null
                                : () => _setZoom(_camera.zoom / 1.2),
                            icon: const Icon(Icons.remove),
                          ),
                          Semantics(
                            label:
                                'Zoom ${(_camera.zoom * 100).round()} percent',
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Text(
                                '${(_camera.zoom * 100).round()}%',
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
                            tooltip: 'Fit page',
                            color: Colors.white,
                            onPressed: _fitPage,
                            icon: Icon(Icons.fit_screen_outlined),
                          ),
                          IconButton(
                            tooltip: 'Zoom in',
                            color: Colors.white,
                            onPressed: _camera.zoom >= widget.maxZoom - 0.001
                                ? null
                                : () => _setZoom(_camera.zoom * 1.2),
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
