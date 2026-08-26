/// Per-page camera state. `zoom == 1` means the default readable scale.
/// Pan offsets are world-space units and are intentionally not page-bounded.
class ViewState {
  const ViewState({this.zoom = 1, this.panX = 0, this.panY = 0});

  final double zoom;
  final double panX;
  final double panY;

  ViewState copyWith({double? zoom, double? panX, double? panY}) => ViewState(
    zoom: zoom ?? this.zoom,
    panX: panX ?? this.panX,
    panY: panY ?? this.panY,
  );

  Map<String, dynamic> toJson() => {'zoom': zoom, 'panX': panX, 'panY': panY};

  factory ViewState.fromJson(Map<String, dynamic> json) => ViewState(
    zoom: (json['zoom'] as num?)?.toDouble() ?? 1,
    panX: (json['panX'] as num?)?.toDouble() ?? 0,
    panY: (json['panY'] as num?)?.toDouble() ?? 0,
  );
}
