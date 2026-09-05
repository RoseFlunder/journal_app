# Creative Journal Editor — Audited Roadmap

Source of truth for the mobile-first, local-first, paper-style creative journal.
Existing saved pages may be discarded while the document architecture changes.

Last audited: 2026-08-29 after the final persistence contract freeze,
architecture boundary closure, and
local-first cloud synchronization slice. The
editor controller, history,
clipboard, and canvas are document/node native; metadata and workflow
persistence route through feature view models; editor factories, platform
services, use cases, and persistence wiring are owned by the composition root; media
referenced by undo/redo and clipboard snapshots is retained. Production Hive
repositories and storage tests use focused
capability data sources; the mutable `JournalStore` aggregate and its adapters
are removed. Journal contents receives asset reads through its view model
rather than a repository. The journal shell caches one configured editor view
model per entry, and `EntryPage` only renders and dispatches through that
model. Feature-native canvas, toolbar, More tools, layers, image, history,
shape, alignment, transform, ink, music, and settings views are
active, and the obsolete toolbar export and image-editor path are gone.
Platform services do not render presentation UI, and `JournalApp` receives one
configured `AppDependencies` object in production and tests.
Storage shutdown is awaitable, and architecture tests cover both feature views
and the editor core. Fresh production data uses the versioned v2 persistence
namespace; pre-freeze records are not decoded or imported.
Focused editor, repository, boundary, and widget suites pass; the full Flutter
test suite passes after the no-legacy cleanup. Release builds remain the final
environment gate before shipping this follow-up.

Legend: **[x] Done**, **[~] Partial**, **[ ] Missing**, **[!] Fix required**.

## Current Progress

### Foundation and persistence

- [x] Immutable `EntryDocument`, `CanvasNode`, `Transform2D`, and
  `EditorDocumentSnapshot` boundaries are the controller's working state and
  the active renderer consumes immutable world-space node projections.
  `EntryCanvas` now accepts only immutable nodes and emits typed transform and
  ink intents; no mutable entry/block storage adapter remains in production.
- [x] Fresh-data startup; legacy migration is out of scope.
- [x] `EditorController` owns selection, transactions, clipboard, 100-step
  undo/redo, text coalescing, and save state.
- [x] Completed transform gestures produce one undo entry and one save.
- [x] Typed immutable `EditorCommand` values back undo/redo for transform,
  board, insert, delete, style, grouping, reorder, node, and structural edits.
  Every transaction carries an explicit `EditorCommandKind`; no untyped
  whole-document fallback remains.
- [x] Five-minute checkpoint scheduling no longer resets after every save.
- [~] Manual checkpoint creation, pruning, listing, and restore UI exist;
  background checkpoint creation is missing.
- [~] Saving and retryable failure UI exists; Saved feedback, error details,
  and failure integration coverage are missing.
- [x] Journal, asset, and checkpoint repository interfaces have Hive
  implementations backed by direct capability adapters; storage tests exercise
  those same sources without a mutable aggregate facade.
- [x] The composition root owns persistence, music, platform services, and
  editor view-model factory wiring; each entry page receives a cached
  configured editor view model and narrow capability contracts. Platform
  picking UI stays in feature views while services only access platform APIs.
  Production Hive
  adapters depend on focused internal data sources; the obsolete mutable
  `JournalStore` aggregate and its test-only adapters have been removed.
- [x] Asset collection protects live documents, checkpoints,
  immutable undo/redo snapshots, and clipboard references.
- [x] Serialize final text commit, background checkpoint, and storage flush to
  eliminate lifecycle races.
- [x] Freeze the canonical persistence contract: typed immutable node content,
  versioned document/manifest/asset/checkpoint/view records, content-addressed
  assets, strict validation with quarantine, and UTC-normalized metadata.
- [x] Freeze `.cozyjournal` ZIP v2 and the dedicated cloud sync namespace;
  imports validate hashes, references, duplicate paths, and resource limits.
- [x] Keep camera/grid visibility device-local and exclude it from document,
  archive, and cloud fingerprints; retain unsupported nodes as opaque locked
  values.

### Optional Google Drive synchronization

- [x] Immutable version vectors, mutation stamps, page tombstones, collection
  ordering heads, content-hashed assets, and exact local sync metadata exist
  below the feature boundary.
- [x] Local-first pull/merge/push coordination is serialized, debounced,
  retry-safe at the gateway boundary, and suppresses preview feedback. New
  devices merge pages and assets; concurrent edits retain deterministic
  conflict copies.
- [x] Android/Web Google Sign-In and Windows PKCE loopback authentication are
  isolated behind platform-neutral account and Drive gateways. The feature is
  disabled by default and configured from public build-time client IDs.
- [x] The journal shell exposes non-blocking sync status, account binding,
  reconnect, sign-out, and confirmed device reset actions.
- [~] OAuth client registration, Google consent-screen verification, privacy
  review, and cross-device smoke validation remain before production enablement.

### A4 paper page and camera

- [x] Finite A4 ruled-paper background, persisted camera, centered title, and
  full-page first-open fit.
- [~] Coordinates retain the page-local model scale, and content-fit includes
  rotated bounds for the optional fit-content action.
- [x] Rendering uses the finite A4 `InteractiveViewer` host instead of an
  infinite board.
- [x] Resize hit targets remain touch-sized while visual markers are subtle;
  desktop/web rotation handles and mobile two-finger rotation are supported.
- [!] Move selection borders, handles, lasso, guides, and ink preview into a
  true screen-space overlay.
- [x] Exclude hidden nodes and structural group blocks from content-fit bounds.
- [x] Add visible-node culling, overscan, displayed-size image decoding,
  thumbnail caching, and repaint boundaries. Page navigation now builds
  editors lazily, uses bounded asset/image caches, and avoids animating through
  intermediate pages.
- [x] Add dedicated camera, hit-testing, transform, bounds, and snapping
  services.

### Direct manipulation

- [x] Selection, movement, rotation, eight resize handles, numeric inspector,
  keyboard nudging, Shift-click, lasso, and multi-object movement.
- [x] Movement accumulates unsnapped deltas and snaps once at gesture
  completion.
- [x] Rotated resizing preserves the opposite world-space anchor.
- [x] Correct the inverted aspect ratio used by vertical-only image and sticker
  resizing; regression coverage now exercises a vertical visual handle.
- [x] Two-finger rotation can start anywhere on the page and rotates only the
  selected unlocked blocks as one transaction; mobile hides the rotate handle.
- [x] Contextual toolbar, scrollable More sheet, duplicate, clipboard, lock,
  layers, groups, and delete exist.
- [x] Single-tap selects text and double-tap enters editing. Imported photos
  retain standard move, rotate, and resize controls without appearance editing.
- [~] Desktop shortcuts cover common clipboard, history, selection, deletion,
  and nudge actions.
- [ ] Add group/layer shortcuts, Space and middle-button pan, automatic
  marquee, long-press menus, smart guides, distribution, size matching,
  rotation snaps, and haptics.

### Groups and layers

- [x] Structural groups preserve move, align, lock, hide, delete, duplicate,
  clipboard insertion, and reorder semantics.
- [x] The immutable document nests group children, remaps graph IDs, and
  applies world-space gesture transforms while retaining parent-local child
  coordinates.
- [x] Group children are serialized as local transforms and flattened into an
  immutable world-space node projection for rendering; no mutable block clone
  is used by the configured editor canvas.
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
- [x] Photos open a temporary import editor before asset persistence. Filters
  and simple frames preview before Add to page; cancellation inserts nothing.
  On-page appearance editing is removed.
- [x] Import uses pro_image_editor for live filter selection/export and
  package:image for baked white, cream, or black frames. Existing saved
  appearance properties remain readable.
- [x] Import, cancel, reset, filter export, frame pixels, and page insertion
  have regression tests.
- [ ] Add image import golden tests.

### Ink and shapes

- [x] Draw mode creates one persisted vector ink block per stroke with live
  preview, color, width, and opacity controls.
- [~] Normalize ink width conversion between model, preview, persisted painter,
  and camera zoom; add visual-width coverage at multiple zooms.
- [ ] Add pressure, pen/highlighter presets, smoothing, erasers, ink lasso, and
  stylus/palm rules.
- [~] Rectangle, ellipse, line, and arrow shapes serialize and render.
- [ ] Add shape styling, polygons, configurable corners, optional text, and
  shape-specific resize rules.

### Recovery, export, and accessibility

- [~] Checkpoint history and numeric transform controls provide recovery and
  non-drag precision.
- [ ] Add command-history labels and undo/redo cursor UI.
- [x] Share sends an editable version-2 `.cozyjournal` page and its assets
  through the system share sheet (browser download fallback).
- [x] Add shared page is available from contents, with confirmation before
  adding an independent copy and preserving the original creation date.
- [x] Android queues file-open/share deliveries through startup and presents
  the same confirmation flow. Windows/Web use the file picker to receive pages.
- [x] Pages use original creation date ascending, then ID, across reload and sync.
- [ ] Verify WhatsApp/Drive attachment handoffs on physical Android devices;
  Windows file associations and Web file-launch integration remain deferred.
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

1. **Preserve the frozen persistence contract**
   - Treat `cozy-bloom-storage-v2`, archive v2, and sync v2 as permanent
     formats. Any incompatible change requires a new decoder and explicit
     migration with golden fixtures; never reset the namespace again.
   - Do not decode or import pre-freeze `Entry`/`ContentBlock` records. Any
     future incompatible format requires an explicit versioned migration.

2. **Complete the document-model and composition migration**
   - [x] Editor-page cross-repository workflows are delegated to focused
     use cases through the configured view model; the page retains only
     platform picking, dialogs, lifecycle, and layout concerns.
   - [x] Canvas implementations live under the editor feature, platform
     services are injected from the app composition root, editor capabilities
     are required rather than nullable, and storage shutdown is awaitable.

3. **Correctness hardening**
   - Fix image edge resizing, image-sheet state, lifecycle ordering, visible
     content bounds, and ink width conversion.
   - Add regression tests for the text Done sequence and scrollable More sheet.

4. **Enable and validate cloud synchronization**
   - Register the Google OAuth clients, complete consent/privacy review, and
     run two-account/two-device Android, Web, and Windows smoke tests.
   - Enable `COZY_BLOOM_CLOUD_SYNC` for production only after the local-first
     merge, tombstone, asset, and account-reset flows pass validation.

5. **Complete page interaction overlay**
   - Render visible nodes and interaction chrome in their correct coordinate
     spaces.
   - Add culling, smart guides, distribution, haptics, and platform gesture
     parity.

6. **Complete creative editing**
   - Use Quill for every text node.
   - Complete image crop, replacement, adjustments, and filters.
   - Complete ink and shape workflows.

7. **Export, accessibility, and performance**
   - Add image/PDF export, semantics, keyboard parity, goldens, and integration
     tests.
   - Profile Android, Chrome, and Windows for 60-fps manipulation with 100
     mixed nodes.

## Public Interfaces and Acceptance

- Add typed immutable `EditorCommand`, `CameraController`, `TransformService`,
  and `SnappingService`.
- Make `EntryDocument` and `CanvasNode` immutable across UI, undo, repository,
  archive, and clipboard boundaries.
- Keep `JournalRepositories` as the only UI-facing repository bundle; concrete
  Hive adapters and mutable storage records remain data-layer details.
- Every completed gesture produces exactly one command and one save;
  cancellation restores the exact previous document.
- No supported operation is exclusively drag- or mouse-driven.
- Controls remain at least 48 logical pixels at minimum and maximum zoom.
- New documents round-trip without layout, group, Delta, ink, or asset loss.
- Require unit, widget, semantics, golden, Android integration, Chrome, and
  Windows test gates before declaring the roadmap complete.

## Assumptions

- Android remains the first mobile target; Web and Windows are first-class.
- The editor remains ruled and local-first, with one finite A4 paper page per
  journal entry.
- Existing saved-data compatibility remains out of scope.
- Real-time collaboration, generative AI, marketplace features, and rich
  embedded media remain deferred. Cloud sync is implemented behind its
  production configuration and validation gate.
- Music remains separate page ambience. The picker searches immediately with
  loading/retry states, shares the single page player for previews, and
  preserves playback when a preview is selected.
