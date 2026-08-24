# Creative Journal Editor Roadmap

Source of truth for the mobile-first, local-first, paperless creative board.
Existing saved pages may be discarded while the document architecture changes.

Legend: `[x]` done, `[~]` partial, `[ ]` missing, `[!]` fix required.

## Status

### Foundation and persistence

- [~] Mutable `Entry` adapter plus immutable `EntryDocument`, `CanvasNode`,
  and `Transform2D` boundary.
- [x] Fresh-data startup; no legacy migration required.
- [~] Text, image, sticker, ink, shape, and group payload fields.
- [x] `EditorController` selection, transactions, clipboard, undo/redo, and
  save state.
- [~] Snapshot commands and text coalescing; typed immutable commands remain.
- [~] Checkpoints and restore UI.
- [!] Checkpoint cadence must measure five minutes from the first dirty edit,
  not reset on every save.
- [~] Internal save states and visible retry chip; repository error reporting
  and integration coverage remain.
- [ ] `JournalRepository` and asset/checkpoint/template interfaces.
- [ ] Asset garbage collection aware of checkpoints, undo history, clipboard,
  and templates.

### Infinite board and camera

- [~] Continuous ruled board, persisted camera, and centered first-open header.
- [!] Replace the fixed 10,000×10,000 workspace with genuine world coordinates
  and a camera service without artificial bounds.
- [!] Move selection borders and handles to a screen-space overlay so targets
  remain at least 48 logical pixels at every zoom.
- [ ] Visible-node culling, overscan, image thumbnail sizing, repaint
  boundaries, world hit-testing, transform, bounds, and snapping services.

### Direct manipulation and selection

- [x] Selection, movement, rotation, eight resize handles, keyboard nudging,
  numeric inspector, Shift-click, lasso mode, and multi-object movement.
- [x] Grid visibility and snap-at-gesture-end behavior.
- [!] Complete rotated handle resizing around the true opposite anchor and add
  rotated-bounds tests.
- [~] Two-finger rotation; simultaneous group scale/rotation is missing.
- [ ] Smart guides, equal spacing, rotation snaps, haptics, long-press menu,
  double-tap edit/crop, desktop Space/middle-button pan, distribution, and
  size matching.

### Groups and layers

- [~] Persisted group membership with shared move/align/lock/hide behavior.
- [!] Groups are hidden structural blocks rather than nested local-coordinate
  nodes; delete/reorder/duplicate/resize/rotate/clipboard semantics are
  incomplete.
- [ ] Nested group transforms, group bounding-box operations, hierarchy layers,
  rename, drag reorder, front/back, and accessibility ordering.

### Creative tools

- [~] Block-level text styling and basic vector shapes.
- [ ] Quill Delta rich text, selection/paragraph formatting, and links.
- [x] Image insertion, downscaling, persistence, transforms, and viewer.
- [ ] Non-destructive crop, focal position, replace, flip, masks, frames,
  opacity, adjustments, and filters.
- [~] Ink serialization/rendering; [ ] drawing input, pressure, pens,
  highlighters, erasers, and ink lasso.
- [ ] Shape style editor, polygons, optional shape text, templates, thumbnails,
  starter library, and reusable favorites.

### Recovery, accessibility, and portability

- [~] Checkpoint history/restore and numeric transform inspector.
- [ ] Command history sheet, `.cozyjournal` archive, PNG/JPEG/PDF export.
- [~] Tooltips, keyboard shortcuts, and partial semantics.
- [ ] Full node/handle semantics, custom actions, announcements, focus states,
  keyboard-open layout, and platform parity.
- [x] Lifecycle flush hooks and title-dialog ownership.
- [ ] Archive recovery and save-failure integration tests.

## Implementation order

1. Correctness: immutable commands, rotated resize, group semantics,
   checkpoint cadence, save retry, lifecycle flush, and regression tests.
2. True board: world camera services, screen-space overlay, culling, and
   camera/content-fit tests.
3. Groups/layout: nested groups, hierarchy layers, distribution, smart guides,
   rotation snaps, and haptics.
4. Rich text/images: Quill Delta, crop, replace, masks, adjustments, filters.
5. Drawing/export/accessibility: ink/shapes, templates, archive/export,
   semantics, golden tests, and platform integration tests.

## Interfaces and acceptance

- Keep `EntryDocument`, `CanvasNode`, and `Transform2D` immutable at repository
  and command boundaries; widgets must not mutate persisted snapshots directly.
- Add `JournalRepository`, typed `EditorCommand`, `CameraController`,
  `TransformService`, and `SnappingService` before removing the adapter.
- Every completed gesture creates exactly one undo command and one save.
- No supported action is drag-only; every transform has inspector, keyboard, or
  menu alternatives.
- Add unit, widget, semantics, Android-oriented integration, Chrome, and
  Windows coverage before declaring the roadmap complete.

## Assumptions

- Android is first mobile target; Web and Windows remain first-class.
- Board is local-first, ruled, paperless, and effectively unbounded.
- Existing saved-data compatibility is intentionally out of scope.
- Music remains separate page ambience and is deferred.
