import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import 'canvas.dart';
import 'node_content.dart';
import 'page_music.dart';
import 'view_state.dart';
export 'canvas.dart'
    show
        BlockType,
        BoardSettings,
        CanvasRenderable,
        InkStrokeType,
        InkStrokeTypeLabel,
        JournalFonts,
        inkStrokeTypeFromName;
export 'node_content.dart';

/// Immutable world-space transform shared by every board node.
class Transform2D {
  const Transform2D({
    this.x = 0,
    this.y = 0,
    this.width = 0,
    this.height = 0,
    this.rotation = 0,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final double rotation;

  Transform2D copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
  }) => Transform2D(
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
    rotation: rotation ?? this.rotation,
  );

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'w': width,
    'h': height,
    'rotation': rotation,
  };

  factory Transform2D.fromJson(Map<String, dynamic> json) => Transform2D(
    x: (json['x'] as num?)?.toDouble() ?? 0,
    y: (json['y'] as num?)?.toDouble() ?? 0,
    width: (json['w'] as num?)?.toDouble() ?? 0,
    height: (json['h'] as num?)?.toDouble() ?? 0,
    rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
  );
}

/// Durable page coordinate space. The editor continues to render the A4
/// portrait page at 100 x 141.4 model units on every platform.
class PageSpec {
  const PageSpec({
    this.format = 'a4Portrait',
    this.coordinateSystemVersion = 1,
    this.width = 100,
    this.height = 141.4,
  });

  const PageSpec.a4Portrait() : this();

  final String format;
  final int coordinateSystemVersion;
  final double width;
  final double height;
}

/// Immutable discriminated board node. Payload remains JSON-compatible so
/// RichText Delta, image adjustments, ink strokes, and future node types can
/// evolve without changing the common transform contract.
class CanvasNode implements CanvasRenderable {
  static const _unset = Object();

  CanvasNode({
    required this.id,
    required this.type,
    required this.transform,
    Map<String, dynamic> payload = const {},
    this.opacity = 1,
    this.locked = false,
    this.visible = true,
    this.accessibilityLabel,
    Iterable<CanvasNode> children = const [],
    this.nodeVersion = 1,
    this.opaqueType,
    Map<String, dynamic>? opaqueJson,
    CanvasNodeContent? content,
  }) : payload = _freezeMap(
         payload.isEmpty && content != null ? content.toPayload() : payload,
       ),
       children = UnmodifiableListView(List<CanvasNode>.from(children)),
       opaqueJson = opaqueJson == null ? null : _freezeMap(opaqueJson),
       content = content ?? CanvasNodeContent.fromLegacy(type, payload) {
    if (!isOpaque && this.content.type != type) {
      throw ArgumentError.value(
        content,
        'content',
        'Typed node content must match the node discriminator',
      );
    }
  }

  @override
  final String id;
  @override
  final BlockType type;
  final Transform2D transform;

  /// Read-only compatibility projection used by the renderer while typed
  /// content is consumed throughout the editor.
  final Map<String, dynamic> payload;
  @override
  final double opacity;
  @override
  final bool locked;
  final bool visible;
  final String? accessibilityLabel;
  final List<CanvasNode> children;

  /// Version of the node payload in the permanent storage format.
  final int nodeVersion;

  /// Non-null when the node was written by a newer node kind/version. Opaque
  /// nodes remain locked and are round-tripped without being interpreted.
  final String? opaqueType;
  final Map<String, dynamic>? opaqueJson;
  final CanvasNodeContent content;

  @override
  bool get isOpaque =>
      opaqueType != null || opaqueJson != null || nodeVersion != 1;

  @override
  String get text => content is TextNodeContent
      ? (content as TextNodeContent).plainText
      : payload['text'] as String? ?? '';

  @override
  String? get assetId => payload['assetId'] as String?;

  @override
  String? get stickerId => payload['stickerId'] as String?;

  @override
  double get x => transform.x;

  @override
  double get y => transform.y;

  @override
  double get w => transform.width;

  @override
  double get h => transform.height;

  @override
  double get rotation => transform.rotation;

  @override
  double get fontSize => _number('fontSize', 21);

  @override
  String? get fontFamily => payload['fontFamily'] as String?;

  @override
  int? get textColorValue => _integer('textColorValue');

  @override
  bool get bold => payload['bold'] as bool? ?? false;

  @override
  bool get italic => payload['italic'] as bool? ?? false;

  @override
  bool get hidden => !visible;

  @override
  String? get name => accessibilityLabel;

  @override
  List<dynamic>? get richTextDelta => payload['richTextDelta'] is List
      ? List<dynamic>.from(payload['richTextDelta'] as List)
      : null;

  @override
  Rect? get crop {
    final value = payload['crop'];
    if (value is! Map<Object?, Object?>) return null;
    return Rect.fromLTRB(
      _numberFrom(value['left']),
      _numberFrom(value['top']),
      _numberFrom(value['right'], fallback: 1),
      _numberFrom(value['bottom'], fallback: 1),
    );
  }

  @override
  bool get flipX => payload['flipX'] as bool? ?? false;

  @override
  bool get flipY => payload['flipY'] as bool? ?? false;

  @override
  String get imageMask => payload['imageMask'] as String? ?? 'rectangle';

  @override
  double get cornerRadius => _number('cornerRadius');

  @override
  int? get frameColorValue => _integer('frameColorValue');

  @override
  double get frameWidth => _number('frameWidth');

  @override
  double get brightness => _number('brightness');

  @override
  double get contrast => _number('contrast');

  @override
  double get saturation => _number('saturation', 1);

  @override
  double get warmth => _number('warmth');

  @override
  String get shape => payload['shape'] as String? ?? 'rectangle';

  @override
  int? get strokeColorValue => _integer('strokeColorValue');

  @override
  int? get fillColorValue => _integer('fillColorValue');

  @override
  double get strokeWidth => _number('strokeWidth', 1);

  @override
  String get strokeType => payload['strokeType'] as String? ?? 'pen';

  @override
  List<Map<String, dynamic>>? get inkPoints {
    final value = payload['inkPoints'];
    if (value is! List) return null;
    return value
        .whereType<Map<Object?, Object?>>()
        .map((point) => Map<String, dynamic>.from(point))
        .toList(growable: false);
  }

  @override
  List<String>? get childIds => (payload['childIds'] as List?)
      ?.whereType<String>()
      .toList(growable: false);

  @override
  String? get groupId => payload['groupId'] as String?;

  double _number(String key, [double fallback = 0]) =>
      _numberFrom(payload[key], fallback: fallback);

  int? _integer(String key) => (payload[key] as num?)?.toInt();

  static double _numberFrom(Object? value, {double fallback = 0}) =>
      (value as num?)?.toDouble() ?? fallback;

  CanvasNode copyWith({
    String? id,
    BlockType? type,
    Transform2D? transform,
    Map<String, dynamic>? payload,
    double? opacity,
    bool? locked,
    bool? visible,
    Object? accessibilityLabel = _unset,
    Iterable<CanvasNode>? children,
    int? nodeVersion,
    Object? opaqueType = _unset,
    Object? opaqueJson = _unset,
    Object? content = _unset,
  }) {
    final nextContent = identical(content, _unset)
        ? (payload == null ? this.content : null)
        : content as CanvasNodeContent?;
    final nextPayload =
        payload ??
        (identical(content, _unset)
            ? this.payload
            : nextContent?.toPayload() ?? const <String, dynamic>{});
    return CanvasNode(
      id: id ?? this.id,
      type: type ?? this.type,
      transform: transform ?? this.transform,
      payload: nextPayload,
      opacity: opacity ?? this.opacity,
      locked: locked ?? this.locked,
      visible: visible ?? this.visible,
      accessibilityLabel: identical(accessibilityLabel, _unset)
          ? this.accessibilityLabel
          : accessibilityLabel as String?,
      children: children ?? this.children,
      nodeVersion: nodeVersion ?? this.nodeVersion,
      opaqueType: identical(opaqueType, _unset)
          ? this.opaqueType
          : opaqueType as String?,
      opaqueJson: identical(opaqueJson, _unset)
          ? this.opaqueJson
          : opaqueJson as Map<String, dynamic>?,
      content: nextContent,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    if (isOpaque && opaqueJson != null) {
      return _thawMap(opaqueJson!);
    }
    return {
      'id': id,
      'type': type.name,
      'transform': transform.toJson(),
      'payload': payload,
      'opacity': opacity,
      'locked': locked,
      'visible': visible,
      'accessibilityLabel': accessibilityLabel,
      'children': children.map((node) => node.toJson()).toList(),
    };
  }

  factory CanvasNode.fromJson(Map<String, dynamic> json) {
    final transform = json['transform'] is Map
        ? Transform2D.fromJson(
            Map<String, dynamic>.from(json['transform'] as Map),
          )
        : Transform2D.fromJson(json);
    final rawType = json['kind'] as String? ?? json['type'] as String?;
    final type = switch (rawType) {
      'text' => BlockType.text,
      'image' => BlockType.image,
      'sticker' => BlockType.sticker,
      'ink' => BlockType.ink,
      'shape' => BlockType.shape,
      'group' => BlockType.group,
      _ => BlockType.text,
    };
    final rawVersion = json['version'];
    final version = rawVersion == null
        ? 1
        : rawVersion is num &&
              rawVersion.isFinite &&
              rawVersion == rawVersion.toInt()
        ? rawVersion.toInt()
        : -1;
    final isKnown =
        rawType == 'text' ||
        rawType == 'image' ||
        rawType == 'sticker' ||
        rawType == 'ink' ||
        rawType == 'shape' ||
        rawType == 'group';
    final rawPayload = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : json['payload'] is Map
        ? Map<String, dynamic>.from(json['payload'] as Map)
        : const <String, dynamic>{};
    if (json['kind'] != null && json['data'] != null && json['data'] is! Map) {
      throw const FormatException('Canvas node data must be an object');
    }
    final rawOpacity = json['opacity'];
    final opacity = rawOpacity == null
        ? 1.0
        : rawOpacity is num &&
              rawOpacity.isFinite &&
              rawOpacity >= 0 &&
              rawOpacity <= 1
        ? rawOpacity.toDouble()
        : double.nan;
    final rawChildren = json['children'];
    if (rawChildren != null && rawChildren is! List) {
      throw const FormatException('Canvas node children must be a list');
    }
    return CanvasNode(
      id: json['id'] as String,
      type: type,
      transform: transform,
      payload: rawPayload,
      opacity: opacity,
      locked: (json['locked'] as bool? ?? false) || !isKnown || version != 1,
      visible: json['visible'] as bool? ?? true,
      accessibilityLabel: json['accessibilityLabel'] as String?,
      children: (rawChildren as List<dynamic>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map(
            (child) => CanvasNode.fromJson(Map<String, dynamic>.from(child)),
          ),
      nodeVersion: version,
      opaqueType: isKnown && version == 1 ? null : (rawType ?? 'unknown'),
      opaqueJson: isKnown && version == 1 ? null : json,
      content: isKnown && version == 1 ? null : OpaqueNodeContent(json),
    );
  }
}

Map<String, dynamic> _thawMap(Map<String, dynamic> source) => {
  for (final entry in source.entries) entry.key: _thawValue(entry.value),
};

Object? _thawValue(Object? value) => switch (value) {
  Map<Object?, Object?> map => _thawMap(Map<String, dynamic>.from(map)),
  List<Object?> list => [for (final item in list) _thawValue(item)],
  _ => value,
};

/// Immutable document boundary for repository, editor, archive, and sync
/// code. It is the only durable document shape exposed to repositories,
/// editor state, archives, and synchronization.
class EntryDocument {
  static const _copyWithUnset = Object();

  EntryDocument({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.modifiedAt,
    Iterable<CanvasNode> nodes = const [],
    this.pageSpec = const PageSpec.a4Portrait(),
    this.board = const BoardSettings(),
    this.view,
    this.music,
    this.titleFontSize = 28,
    this.titleFontFamily,
    this.titleTextColorValue,
    this.titleBold = true,
    this.titleItalic = false,
    this.previewImageNodeId,
    this.revision = 0,
    this.schemaVersion = 1,
  }) : nodes = UnmodifiableListView(List<CanvasNode>.from(nodes));

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final List<CanvasNode> nodes;
  final PageSpec pageSpec;
  final BoardSettings board;

  /// Compatibility projection of device-local view preferences. It is not
  /// included in canonical document records.
  final ViewState? view;
  final PageMusicTrack? music;
  final double titleFontSize;
  final String? titleFontFamily;
  final int? titleTextColorValue;
  final bool titleBold;
  final bool titleItalic;

  /// The photo node explicitly chosen for the journal contents thumbnail.
  /// A missing or stale reference falls back to the first available photo.
  final String? previewImageNodeId;

  /// Local storage metadata retained for compatibility projections only.
  /// Canonical codecs store both values outside the durable document tree.
  final int revision;
  final int schemaVersion;

  EntryDocument copyWith({
    String? title,
    DateTime? modifiedAt,
    Iterable<CanvasNode>? nodes,
    PageSpec? pageSpec,
    BoardSettings? board,
    Object? view = _copyWithUnset,
    Object? music = _copyWithUnset,
    double? titleFontSize,
    Object? titleFontFamily = _copyWithUnset,
    Object? titleTextColorValue = _copyWithUnset,
    bool? titleBold,
    bool? titleItalic,
    Object? previewImageNodeId = _copyWithUnset,
    int? revision,
    int? schemaVersion,
  }) => EntryDocument(
    id: id,
    title: title ?? this.title,
    createdAt: createdAt,
    modifiedAt: modifiedAt ?? this.modifiedAt,
    nodes: nodes ?? this.nodes,
    pageSpec: pageSpec ?? this.pageSpec,
    board: board ?? this.board,
    view: identical(view, _copyWithUnset) ? this.view : view as ViewState?,
    music: identical(music, _copyWithUnset)
        ? this.music
        : music as PageMusicTrack?,
    titleFontSize: titleFontSize ?? this.titleFontSize,
    titleFontFamily: identical(titleFontFamily, _copyWithUnset)
        ? this.titleFontFamily
        : titleFontFamily as String?,
    titleTextColorValue: identical(titleTextColorValue, _copyWithUnset)
        ? this.titleTextColorValue
        : titleTextColorValue as int?,
    titleBold: titleBold ?? this.titleBold,
    titleItalic: titleItalic ?? this.titleItalic,
    previewImageNodeId: identical(previewImageNodeId, _copyWithUnset)
        ? this.previewImageNodeId
        : previewImageNodeId as String?,
    revision: revision ?? this.revision,
    schemaVersion: schemaVersion ?? this.schemaVersion,
  );

  factory EntryDocument.fromJson(Map<String, dynamic> json) => EntryDocument(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    createdAt: DateTime.parse(json['createdAt'] as String),
    modifiedAt: DateTime.parse(
      json['modifiedAt'] as String? ?? json['createdAt'] as String,
    ),
    nodes: (json['nodes'] as List<dynamic>? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map((node) => CanvasNode.fromJson(Map<String, dynamic>.from(node))),
    pageSpec: _pageSpecFromJson(json['page']),
    board: BoardSettings.fromJson(
      json['board'] is Map
          ? Map<String, dynamic>.from(json['board'] as Map)
          : null,
    ),
    view: json['view'] is Map
        ? ViewState.fromJson(Map<String, dynamic>.from(json['view'] as Map))
        : null,
    music: PageMusicTrack.decode(json['music']),
    titleFontSize: (json['titleFontSize'] as num?)?.toDouble() ?? 28,
    titleFontFamily: json['titleFontFamily'] as String?,
    titleTextColorValue: (json['titleTextColorValue'] as num?)?.toInt(),
    titleBold: json['titleBold'] as bool? ?? true,
    titleItalic: json['titleItalic'] as bool? ?? false,
    previewImageNodeId: json['previewImageNodeId'] as String?,
    revision: (json['revision'] as num?)?.toInt() ?? 0,
    schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
  );

  /// Finds a node anywhere in the immutable document tree.
  CanvasNode? nodeById(String id) {
    CanvasNode? visit(Iterable<CanvasNode> candidates) {
      for (final node in candidates) {
        if (node.id == id) return node;
        final nested = visit(node.children);
        if (nested != null) return nested;
      }
      return null;
    }

    return visit(nodes);
  }

  /// Returns a node's world-space transform, resolving every parent in its
  /// path. The node itself remains stored in parent-local coordinates.
  Transform2D? worldTransformFor(String id) {
    Transform2D? visit(Iterable<CanvasNode> candidates, Transform2D? parent) {
      for (final node in candidates) {
        final world = parent == null
            ? node.transform
            : _worldTransform(node.transform, parent);
        if (node.id == id) return world;
        final nested = visit(node.children, world);
        if (nested != null) return nested;
      }
      return null;
    }

    return visit(nodes, null);
  }

  /// Returns the drawable leaf nodes in page/world coordinates.
  ///
  /// Group structure remains owned by the document tree; this projection is
  /// read-only and is intended for renderers that should not depend on the
  /// mutable storage adapter. Group containers are not themselves drawable,
  /// while their visible descendants are flattened with resolved world
  /// transforms.
  List<CanvasNode> get renderNodes {
    final rendered = <CanvasNode>[];

    void visit(Iterable<CanvasNode> candidates, Transform2D? parentWorld) {
      for (final node in candidates) {
        if (!node.visible) continue;
        final world = parentWorld == null
            ? node.transform
            : _worldTransform(node.transform, parentWorld);
        if (node.type != BlockType.group) {
          rendered.add(
            node.copyWith(transform: world, children: const <CanvasNode>[]),
          );
        }
        if (node.children.isNotEmpty) visit(node.children, world);
      }
    }

    visit(nodes, null);
    return List<CanvasNode>.unmodifiable(rendered);
  }

  /// Replaces one node without exposing mutable compatibility adapters.
  EntryDocument replaceNode(CanvasNode replacement) {
    var replaced = false;

    List<CanvasNode> visit(Iterable<CanvasNode> candidates) => candidates
        .map((node) {
          if (node.id == replacement.id) {
            replaced = true;
            return replacement;
          }
          if (node.children.isEmpty) return node;
          return node.copyWith(children: visit(node.children));
        })
        .toList(growable: false);

    final next = visit(nodes);
    return replaced ? copyWith(nodes: next) : this;
  }

  /// Inserts nodes at the root or as children of [parentId].
  EntryDocument insertNodes(
    Iterable<CanvasNode> additions, {
    String? parentId,
    int? index,
  }) {
    final incoming = List<CanvasNode>.unmodifiable(additions);
    if (incoming.isEmpty) return this;
    if (parentId == null) {
      final next = List<CanvasNode>.from(nodes);
      final insertion = (index ?? next.length).clamp(0, next.length).toInt();
      next.insertAll(insertion, incoming);
      return copyWith(nodes: next);
    }

    var inserted = false;
    List<CanvasNode> visit(Iterable<CanvasNode> candidates) => candidates
        .map((node) {
          if (node.id == parentId) {
            inserted = true;
            final children = List<CanvasNode>.from(node.children);
            final insertion = (index ?? children.length)
                .clamp(0, children.length)
                .toInt();
            children.insertAll(insertion, incoming);
            return node.copyWith(children: children);
          }
          if (node.children.isEmpty) return node;
          return node.copyWith(children: visit(node.children));
        })
        .toList(growable: false);

    final next = visit(nodes);
    return inserted ? copyWith(nodes: next) : this;
  }

  /// Removes nodes by ID, including all descendants of a removed node.
  EntryDocument removeNodes(Iterable<String> ids) {
    final removals = ids.toSet();
    if (removals.isEmpty) return this;
    List<CanvasNode> visit(Iterable<CanvasNode> candidates) => candidates
        .where((node) => !removals.contains(node.id))
        .map(
          (node) => node.children.isEmpty
              ? node
              : node.copyWith(children: visit(node.children)),
        )
        .toList(growable: false);

    return copyWith(nodes: visit(nodes));
  }

  /// Reorders a node among its current siblings without changing its parent.
  EntryDocument reorderNode(String id, int targetIndex) {
    ({List<CanvasNode> nodes, bool changed}) visit(
      Iterable<CanvasNode> candidates,
    ) {
      final siblings = List<CanvasNode>.from(candidates);
      final currentIndex = siblings.indexWhere((node) => node.id == id);
      if (currentIndex >= 0) {
        final node = siblings.removeAt(currentIndex);
        final insertion = targetIndex.clamp(0, siblings.length).toInt();
        siblings.insert(insertion, node);
        return (nodes: siblings, changed: currentIndex != insertion);
      }
      for (var index = 0; index < siblings.length; index++) {
        final node = siblings[index];
        if (node.children.isEmpty) continue;
        final result = visit(node.children);
        if (!result.changed) continue;
        siblings[index] = node.copyWith(children: result.nodes);
        return (nodes: siblings, changed: true);
      }
      return (nodes: siblings, changed: false);
    }

    final result = visit(nodes);
    return result.changed ? copyWith(nodes: result.nodes) : this;
  }

  /// Moves the selected sibling nodes to the front or back of their current
  /// sibling list, preserving their relative order.
  EntryDocument reorderNodes(Iterable<String> ids, {required bool toEnd}) {
    final selectedIds = ids.toSet();
    if (selectedIds.isEmpty) return this;

    ({List<CanvasNode> nodes, bool changed}) visit(
      Iterable<CanvasNode> candidates,
    ) {
      final siblings = List<CanvasNode>.from(candidates);
      final selected = siblings
          .where((node) => selectedIds.contains(node.id))
          .toList(growable: false);
      if (selected.isNotEmpty) {
        final remaining = siblings
            .where((node) => !selectedIds.contains(node.id))
            .toList();
        if (toEnd) {
          remaining.addAll(selected);
        } else {
          remaining.insertAll(0, selected);
        }
        return (nodes: remaining, changed: true);
      }
      for (var index = 0; index < siblings.length; index++) {
        final node = siblings[index];
        if (node.children.isEmpty) continue;
        final result = visit(node.children);
        if (!result.changed) continue;
        siblings[index] = node.copyWith(children: result.nodes);
        return (nodes: siblings, changed: true);
      }
      return (nodes: siblings, changed: false);
    }

    final result = visit(nodes);
    return result.changed ? copyWith(nodes: result.nodes) : this;
  }

  /// Creates a root group from existing nodes while converting their world
  /// transforms into coordinates local to the new group.
  EntryDocument groupNodes(
    Iterable<String> ids, {
    required String groupId,
    String name = 'Group',
  }) {
    final selectedIds = ids.toSet();
    if (selectedIds.isEmpty || nodeById(groupId) != null) return this;
    final selected = selectedIds
        .map(nodeById)
        .whereType<CanvasNode>()
        .where((node) => node.id != groupId)
        .toList(growable: false);
    if (selected.isEmpty) return this;
    final world = <String, Transform2D>{
      for (final node in selected)
        node.id: worldTransformFor(node.id) ?? node.transform,
    };
    var bounds = Rect.fromLTWH(
      world[selected.first.id]!.x,
      world[selected.first.id]!.y,
      world[selected.first.id]!.width,
      world[selected.first.id]!.height,
    );
    for (final node in selected.skip(1)) {
      final transform = world[node.id]!;
      bounds = bounds.expandToInclude(
        Rect.fromLTWH(
          transform.x,
          transform.y,
          transform.width,
          transform.height,
        ),
      );
    }
    final groupWorld = Transform2D(
      x: bounds.left,
      y: bounds.top,
      width: bounds.width,
      height: bounds.height,
    );
    final children = selected
        .map(
          (node) =>
              node.copyWith(transform: _toLocal(world[node.id]!, groupWorld)),
        )
        .toList(growable: false);
    final group = CanvasNode(
      id: groupId,
      type: BlockType.group,
      transform: groupWorld,
      accessibilityLabel: name,
      children: children,
    );
    return removeNodes(selectedIds).insertNodes([group]);
  }

  /// Removes groups and promotes their children to root nodes while
  /// preserving each child's world-space transform.
  EntryDocument ungroupNodes(Iterable<String> ids) {
    final groups = ids
        .map(nodeById)
        .whereType<CanvasNode>()
        .where((node) => node.type == BlockType.group)
        .toList(growable: false);
    if (groups.isEmpty) return this;
    final promoted = <CanvasNode>[];
    for (final group in groups) {
      final groupWorld = worldTransformFor(group.id) ?? group.transform;
      promoted.addAll(
        group.children.map(
          (child) => child.copyWith(
            transform: _worldTransform(child.transform, groupWorld),
          ),
        ),
      );
    }
    return removeNodes(groups.map((group) => group.id)).insertNodes(promoted);
  }

  /// Applies world-space transforms while retaining each node's local
  /// transform relative to its parent. Unspecified descendants inherit any
  /// parent movement without being rewritten as world-space values.
  EntryDocument replaceWorldTransforms(Map<String, Transform2D> transforms) {
    if (transforms.isEmpty) return this;

    List<CanvasNode> visit(
      Iterable<CanvasNode> candidates,
      Transform2D? parentWorld,
    ) => candidates
        .map((node) {
          final currentWorld = parentWorld == null
              ? node.transform
              : _worldTransform(node.transform, parentWorld);
          final desiredWorld = transforms[node.id] ?? currentWorld;
          final local = parentWorld == null
              ? desiredWorld
              : _toLocal(desiredWorld, parentWorld);
          final children = node.children.isEmpty
              ? node.children
              : visit(node.children, desiredWorld);
          return node.copyWith(transform: local, children: children);
        })
        .toList(growable: false);

    return copyWith(nodes: visit(nodes, null));
  }

  /// Applies parent-local transforms directly. This is used by immutable
  /// history commands, whose deltas are captured from the node tree rather
  /// than from a flattened world-space adapter.
  EntryDocument replaceLocalTransforms(Map<String, Transform2D> transforms) {
    if (transforms.isEmpty) return this;
    List<CanvasNode> visit(Iterable<CanvasNode> candidates) => candidates
        .map(
          (node) => node.copyWith(
            transform: transforms[node.id] ?? node.transform,
            children: node.children.isEmpty
                ? node.children
                : visit(node.children),
          ),
        )
        .toList(growable: false);

    return copyWith(nodes: visit(nodes));
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'modifiedAt': modifiedAt.toIso8601String(),
    'nodes': nodes.map((node) => node.toJson()).toList(),
    'page': <String, dynamic>{
      'format': pageSpec.format,
      'coordinateSystemVersion': pageSpec.coordinateSystemVersion,
      'width': pageSpec.width,
      'height': pageSpec.height,
    },
    'board': board.toJson(),
    'view': view?.toJson(),
    'music': music?.toJson(),
    'titleFontSize': titleFontSize,
    'titleFontFamily': titleFontFamily,
    'titleTextColorValue': titleTextColorValue,
    'titleBold': titleBold,
    'titleItalic': titleItalic,
    'previewImageNodeId': previewImageNodeId,
    'revision': revision,
    'schemaVersion': schemaVersion,
  };

  static Transform2D _toLocal(Transform2D world, Transform2D parent) {
    final parentCenter = Offset(parent.width / 2, parent.height / 2);
    final worldParentCenter = Offset(
      parent.x + parentCenter.dx,
      parent.y + parentCenter.dy,
    );
    final worldCenter = Offset(
      world.x + world.width / 2,
      world.y + world.height / 2,
    );
    final localCenter =
        parentCenter +
        _rotate(worldCenter - worldParentCenter, -parent.rotation);
    return Transform2D(
      x: localCenter.dx - world.width / 2,
      y: localCenter.dy - world.height / 2,
      width: world.width,
      height: world.height,
      rotation: world.rotation - parent.rotation,
    );
  }

  static Transform2D _worldTransform(Transform2D local, Transform2D parent) {
    final parentCenter = Offset(parent.width / 2, parent.height / 2);
    final localCenter = Offset(
      local.x + local.width / 2,
      local.y + local.height / 2,
    );
    final worldParentCenter = Offset(
      parent.x + parentCenter.dx,
      parent.y + parentCenter.dy,
    );
    final worldCenter =
        worldParentCenter +
        _rotate(localCenter - parentCenter, parent.rotation);
    return Transform2D(
      x: worldCenter.dx - local.width / 2,
      y: worldCenter.dy - local.height / 2,
      width: local.width,
      height: local.height,
      rotation: parent.rotation + local.rotation,
    );
  }

  static Offset _rotate(Offset point, double angle) {
    final cosine = math.cos(angle);
    final sine = math.sin(angle);
    return Offset(
      point.dx * cosine - point.dy * sine,
      point.dx * sine + point.dy * cosine,
    );
  }
}

Map<String, dynamic> _freezeMap(Map<Object?, Object?> source) =>
    UnmodifiableMapView(<String, dynamic>{
      for (final entry in source.entries)
        entry.key.toString(): _freezeValue(entry.value),
    });

Object? _freezeValue(Object? value) => switch (value) {
  Map<Object?, Object?> map => _freezeMap(map),
  List<Object?> list => UnmodifiableListView<Object?>(
    list.map(_freezeValue).toList(growable: false),
  ),
  _ => value,
};

PageSpec _pageSpecFromJson(Object? value) {
  if (value is! Map) return const PageSpec.a4Portrait();
  return PageSpec(
    format: value['format'] as String? ?? 'a4Portrait',
    coordinateSystemVersion:
        (value['coordinateSystemVersion'] as num?)?.toInt() ?? 1,
    width: (value['width'] as num?)?.toDouble() ?? 100,
    height: (value['height'] as num?)?.toDouble() ?? 141.4,
  );
}
