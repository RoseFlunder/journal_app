import '../ui/features/editor/views/editor_toolbar_view.dart';

/// Transitional export for callers that still import the pre-feature toolbar
/// path. Production editor code uses [EditorToolbarView] directly.
export '../ui/features/editor/views/editor_toolbar_view.dart'
    show EditorToolbarView;

/// Compatibility name retained while downstream tests and embedders migrate.
typedef EditorToolbar = EditorToolbarView;
