# Creative Journal Editor — Audited Roadmap

Source of truth for the mobile-first, local-first, paperless creative board.
Existing saved pages may be discarded while the document architecture changes.

Last audited: 2026-08-25 on top of commit `124ec34` (`Add vector ink drawing
mode`). The correctness slice analyzes cleanly, all 55 tests pass, and an
Android release APK remains the validation target.

Legend: **[x] Done**, **[~] Partial**, **[ ] Missing**, **[!] Fix required**.

## Current Progress

### Foundation and persistence

- [~] Immutable `EntryDocument`, `CanvasNode`, and `Transform2D` boundaries
  exist, but the active editor still uses mutable `Entry` and `ContentBlock`
  adapters.
- [x] Fresh-data startup; legacy migration is out of scope.
- [x] `EditorController` owns selection, transactions, clipboard, 100-step
  undo/redo, text coalescing, and save state.
- [x] Completed transform gestures produce one undo entry and one save.
- [!] Replace whole-document `_EditorCommand` snapshots and mutation-oriented
  widget callbacks with typed immutable commands.
- [x] Five-minute checkpoint scheduling no longer resets after every save.
- [~] Manual checkpoint creation, pruning, listing, and restore UI exist;
  background checkpoint creation is missing.
- [~] Saving and retryable failure UI exists; Saved feedback, error details,
  and failure integration coverage are missing.
- [x] Journal, asset, checkpoint, and template repository interfaces have Hive
  implementations.
- [!] Screens still depend directly on `JournalStore`; inject repository
  contracts through the editor/view-model layer.
- [~] Asset collection protects live documents, checkpoints, and templates,
  but not undo/redo or clipboard references.
- [x] Serialize final text commit, background checkpoint, and storage flush to
  eliminate lifecycle races.

### Infinite board and camera

- [x] Continuous ruled-paper background, persisted camera, and centered
  first-open header.
- [~] Coordinates allow negative and large values, and content-fit includes
  rotated bounds.
- [!] Rendering still relies on a 10,000×10,000 `InteractiveViewer` host.
- [x] Resize and rotation controls are inverse-scaled to approximately 48
  logical pixels.
- [!] Move selection borders, handles, lasso, guides, and ink preview into a
  true screen-space overlay.
- [x] Exclude hidden nodes and structural group blocks from content-fit bounds.
- [ ] Add a camera matrix, visible-node culling, overscan, displayed-size image
  decoding, thumbnail caching, and repaint boundaries.
- [ ] Add dedicated camera, hit-testing, transform, bounds, and snapping
  services.

### Direct manipulation

- [x] Selection, movement, rotation, eight resize handles, numeric inspector,
  keyboard nudging, Shift-click, lasso, and multi-object movement.
- [x] Movement accumulates unsnapped deltas and snaps once at gesture
  completion.
- [x] Rotated resizing preserves the opposite world-space anchor.
- [x] Correct the inverted aspect ratio used by vertical-only image and sticker
  resizing; regression coverage now exercises a vertical visual handle.
- [~] Two-finger rotation exists; simultaneous selection scaling and rotation
  is missing.
- [~] Contextual toolbar, scrollable More sheet, duplicate, clipboard, lock,
  layers, groups, and delete exist.
- [x] Single-tap selects text and double-tap enters editing; double-tap visual
  blocks opens the image editor.
- [~] Desktop shortcuts cover common clipboard, history, selection, deletion,
  and nudge actions.
- [ ] Add group/layer shortcuts, Space and middle-button pan, automatic
  marquee, long-press menus, smart guides, distribution, size matching,
  rotation snaps, and haptics.

### Groups and layers

- [x] Structural groups preserve move, align, lock, hide, delete, duplicate,
  clipboard, template insertion, and reorder semantics.
- [~] The immutable adapter nests group children and remaps graph IDs.
- [!] Nested children still retain world coordinates. Convert them to true
  group-local transforms and correct the misleading local-coordinate test.
- [!] Groups remain hidden structural blocks without bounding-box resize,
  rotation, or reliable nested-group behavior.
- [x] Layers support selection, rename, visibility, locking, drag reorder,
  forward, and backward movement.
- [~] Add collapsible hierarchy, nested expansion, front/back actions, and
  accessibility ordering.

### Rich text

- [x] Formatted Quill Delta documents render, edit, persist, coalesce, and
  restore.
- [~] Plain documents still use `TextField`, and formatting controls apply to
  the complete block.
- [ ] Use Quill for all text nodes and add selection/paragraph formatting,
  underline, alignment, spacing, lists, links, backgrounds, borders, and saved
  defaults.
- [!] Add interaction tests that apply formatting through the real toolbar.

### Images and stickers

- [x] Image insertion, downscaling, immutable asset persistence, transforms,
  sticker rendering, and full-screen viewing.
- [~] Preset crop, opacity, 90-degree rotation, flipping, masks, brightness,
  contrast, and saturation are stored and rendered.
- [~] Image sliders and crop choices now use sheet-local preview state and
  commit each continuous slider gesture once; dedicated editor interaction
  coverage remains.
- [ ] Add free crop, focal repositioning, replace-with-layout-retention,
  frames, warmth, filter presets, and original/edited comparison.
- [ ] Add image-editor interaction and golden tests.

### Ink, shapes, and templates

- [x] Draw mode creates one persisted vector ink block per stroke with live
  preview, color, width, and opacity controls.
- [~] Normalize ink width conversion between model, preview, persisted painter,
  and camera zoom; add visual-width coverage at multiple zooms.
- [ ] Add pressure, pen/highlighter presets, smoothing, erasers, ink lasso, and
  stylus/palm rules.
- [~] Rectangle, ellipse, line, and arrow shapes serialize and render.
- [ ] Add shape styling, polygons, configurable corners, optional text, and
  shape-specific resize rules.
- [~] Templates persist, insert as one undoable command, and preserve group
  IDs.
- [~] “Save selection as template” now saves the selected structural graph and
  inserts near the board center; camera-state placement and UI coverage remain.
- [ ] Add template thumbnails, rename/delete, starter content, favorites, and
  explicit board-versus-selection templates.

### Recovery, export, and accessibility

- [~] Checkpoint history and numeric transform controls provide recovery and
  non-drag precision.
- [ ] Add command-history labels and undo/redo cursor UI.
- [x] Versioned `.cozyjournal` archive import/export includes documents,
  assets, and templates.
- [ ] Add pre-import checkpoints, corrupt-asset recovery, and platform
  file-picker integration tests.
- [ ] Add PNG, JPEG, and PDF export for full board, current view, and selection.
- [~] Tooltips, keyboard shortcuts, nudge semantics, and partial toolbar
  semantics exist.
- [ ] Add node/handle custom semantics, focus styling, announcements, drag
  alternatives, and accessible Layers ordering.
- [!] Verify that the software keyboard never covers active text or editor
  controls.
- [x] Page creation requires a title, and dialog controllers are safely
  disposed.

## Next Implementation Order

1. **Correctness hardening**
   - Fix image edge resizing, image-sheet state, lifecycle ordering, visible
     content bounds, template scope, and ink width conversion.
   - Add regression tests for the text Done sequence and scrollable More sheet.
   - Replace snapshot commands with typed immutable commands.

2. **True document and group model**
   - Make immutable documents the editor's working state.
   - Inject repository interfaces instead of `JournalStore`.
   - Convert groups to nested local-coordinate nodes.
   - Account for undo and clipboard during asset retention.

3. **True board and interaction overlay**
   - Remove the fixed canvas and introduce camera, transform, and snapping
     services.
   - Render visible nodes and interaction chrome in their correct coordinate
     spaces.
   - Add culling, smart guides, distribution, haptics, and platform gesture
     parity.

4. **Complete creative editing**
   - Use Quill for every text node.
   - Complete image crop, replacement, adjustments, and filters.
   - Complete ink, shape, and template workflows.

5. **Export, accessibility, and performance**
   - Add image/PDF export, semantics, keyboard parity, goldens, and integration
     tests.
   - Profile Android, Chrome, and Windows for 60-fps manipulation with 100
     mixed nodes.

## Public Interfaces and Acceptance

- Add typed immutable `EditorCommand`, `CameraController`, `TransformService`,
  and `SnappingService`.
- Make `EntryDocument` and `CanvasNode` immutable across UI, undo, repository,
  archive, and clipboard boundaries.
- Every completed gesture produces exactly one command and one save;
  cancellation restores the exact previous document.
- No supported operation is exclusively drag- or mouse-driven.
- Controls remain at least 48 logical pixels at minimum and maximum zoom.
- New documents round-trip without layout, group, Delta, ink, or asset loss.
- Require unit, widget, semantics, golden, Android integration, Chrome, and
  Windows test gates before declaring the roadmap complete.

## Assumptions

- Android remains the first mobile target; Web and Windows are first-class.
- The board remains ruled, local-first, paperless, and effectively unbounded.
- Existing saved-data compatibility remains out of scope.
- Cloud sync, collaboration, generative AI, marketplace features, and rich
  embedded media remain deferred.
- Music remains separate page ambience and is deferred until editor
  correctness and creative tools are stable.
