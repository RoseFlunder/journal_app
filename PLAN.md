# Journal App – Implementation Plan

A paper-styled digital journal: swipeable pages, each with a title, creation
date and freely positioned content (text boxes and pictures, drag & drop).
Optional per-page background music with manual play/pause. The first page is
a table of contents for jumping to any page. Everything is stored locally on
device. Targets: **Android, Windows, Web**.

## 1. Data model

```dart
class Entry {
  final String id;          // uuid
  String title;
  final DateTime createdAt; // shown on the page header
  DateTime modifiedAt;
  List<ContentBlock> blocks;  // freely positioned content, z-ordered by list order
  String? music;            // asset id (key into the assets box), nullable
  ViewState? view;          // per-page zoom & pan (null = fit-to-screen)
}

class ViewState {
  double zoom;   // 1.0 == fit-to-screen, clamped ~0.5-3.0
  Offset pan;    // in page units
}

class ContentBlock {
  final String id;
  BlockType type;           // text | image
  String text;              // text blocks (may be '')
  String? assetId;          // image blocks: key into the assets box
  Offset position;          // in *page units* (virtual page = 100 x 141.4)
  Size size;                // in page units
}
```

- Order of `pages` == order of entries in the list; TOC is always page index 0.
- Deleting a page re-orders the PageView indices (TOC must account for that).
- **Coordinate system:** positions/sizes are stored in *page units* on a
  virtual page of fixed aspect (A4-ish, 100 x 141.4 units). At render time
  the page is scaled to fit the screen (`LayoutBuilder` + scale factor), so
  layouts stay consistent across phones, desktop and browsers.
- A page can hold **multiple text blocks** and multiple image blocks, in any
  arrangement. The title stays page chrome (header), not a block.

## 2. Local storage (cross-platform, incl. Web)

Files on disk don't work on the Web, so persistence goes through
**Hive** (`hive`, `hive_flutter`): file-based on Android/Windows, IndexedDB
on Web, one code path everywhere.

```
Hive boxes:
  entries   -> key = entry id, value = Entry JSON (metadata + blocks)
  assets    -> key = asset id (uuid), value = AssetRecord:
               { entryId, kind: image|audio, mime, data: Uint8List }
```

- `JournalStore` is the single writer: load all entries at startup, rewrite
  the affected box entry on every change.
- Picked images are **downscaled** (e.g. max ~1600 px JPEG) before being
  stored — keeps IndexedDB quota usage sane on Web and makes the app feel
  faster.
- Deleting an entry also deletes its `assets` records.
- Web note: persistence lives in the browser profile (IndexedDB, typically
  ~50–500 MB). Fine for a personal journal; mention in README.

## 3. Dependencies (pubspec)

| Package            | Purpose                                    |
|--------------------|--------------------------------------------|
| `hive` + `hive_flutter` | all persistence (files on mobile/desktop, IndexedDB on Web) |
| `image_picker`     | pick/take pictures (gallery + camera)      |
| `file_picker`      | pick a local audio file as background music|
| `just_audio`       | play/pause/loop the music                  |
| `intl`             | date formatting for headers                |
| `uuid`             | entry & asset ids                          |

Web compatibility notes (all three pickers/players work on Web):
- `image_picker`: file/gallery picking works; **camera capture is not
  available** on Web (hide the camera option there).
- `file_picker`: opens the browser file dialog.
- `just_audio`: uses `MediaElement` on Web; no background playback (browser
  limitation, acceptable for a journal).

No state-management package needed: one `JournalStore extends ChangeNotifier`
(entries list + persistence) at the root, consumed with `ListenableBuilder`.
One app-level `AudioService` (single `just_audio` `AudioPlayer`, loop mode)
shared by all pages.

## 4. Architecture / file layout

```
lib/
  main.dart
  models/
    entry.dart                  // Entry, ContentBlock + (de)serialization
  services/
    journal_store.dart          // ChangeNotifier: CRUD + Hive persistence
    audio_service.dart          // single AudioPlayer wrapper, loop mode
    image_downscaler.dart       // pick -> downscale -> store as asset
  screens/
    journal_screen.dart         // PageView + PageController over [TOC, ...pages]
    contents_page.dart          // paper-styled TOC: title + date, tap -> jump
    entry_page.dart             // renders one Entry as a paper page
  editor/
    entry_canvas.dart           // Stack of blocks scaled to page size;
                                // handles selection, drag, resize in edit mode
    block_widget.dart           // one text/image block: selection frame,
                                // drag handle, resize handles
    editor_toolbar.dart         // add text, add image, bring to front,
                                // delete selection, edit title, pick music
  widgets/
    page_viewport.dart          // zoom/pan wrapper: pinch, wheel, toolbar
    paper_page.dart             // paper look: color, shadow, rules, margin line
    paper_textfield.dart        // transparent input styled like handwriting
    music_player_bar.dart       // play/pause button (+ position), bottom corner
```

### Entry page rendering

- `EntryPage` = `PaperPage` chrome (title + date header, music bar, edit
  affordance) + `EntryCanvas` filling the page body.
- `EntryCanvas` is a `Stack` of `Positioned` blocks using fractional
  offsets/sizes derived from page units. Read mode: inert. Edit mode:
  - tap block → select (dashed selection frame),
  - drag block body → move,
  - drag corner handles → resize (min size clamps); for images this scales
    the **display only** — the stored asset keeps its downscaled original
    quality (no re-encoding),
  - toolbar: add text box, add image, bring-to-front (re-order list),
    delete selection,
  - text blocks: tap in edit mode focuses a transparent `TextField`.
- New blocks are appended at the end of `blocks` (topmost z-order).

### Page viewport (zoom & pan)

On desktop/Web there is much more screen space than on mobile, so pages are
viewed through a `PageViewport` wrapper that supports zoom in/out and panning
across the page:

- Built on `InteractiveViewer` (pinch/drag) plus a `Listener` for wheel
  events so every input mode works:
  - touch: pinch = zoom, one-finger drag = pan (read mode); in edit mode a
    one-finger drag on a block moves the block, on empty paper it pans,
  - desktop/Web: scroll wheel / trackpad = pan (when zoomed in),
    ctrl+wheel or trackpad pinch = zoom,
  - small on-screen toolbar when zoomed: − / + / "fit" buttons;
    double-click (double-tap on empty paper) toggles fit ↔ 2×.
- Entering a page defaults to fit-to-screen; the user's zoom/pan is stored in
  `Entry.view` and restored when they return to the page.
- All block coordinates are in page units, so drag/resize hit-testing goes
  through the same transform as rendering (one `Matrix4` shared by the
  viewport and the canvas — implement the viewport **before** the block
  editor so the editor is built on it from day one).
- TOC page stays fixed fit-to-screen (no zoom) — it is a list, not a page.

### Navigation flow

1. Root is `JournalScreen`: a `PageView` with
   `children = [ContentsPage(), ...entries.map(EntryPage)]`.
2. `ContentsPage` lists entries (title + `createdAt`), tap →
   `pageController.animateToPage(index + 1)`.
3. Each `EntryPage` has an edit affordance (pencil) toggling edit mode.
4. "New page" (FAB or TOC button) appends an entry, saves, scrolls there.
5. Music (confirmed behavior): **never autoplays.** Each page's music bar has
   a manual play/pause button. When the page is swapped away (PageView page
   changes), `AudioService.stop()` — music is per-page ambience.

## 5. Paper design

- Palette: paper `#F4EDDC`–`#EFE6D0`, ink `#3B3226`, accent red margin `#C97068`.
- `PaperPage` widget:
  - warm paper background + soft outer shadow + hairline border,
  - subtle texture (either a bundled noise PNG or a light `LinearGradient`
    — start with gradient, texture later),
  - optional horizontal rules + red margin line drawn by a `CustomPainter`
    (looks great, cheap to implement),
  - slight corner rounding (2–3 px), not "card"-like.
- Fonts (bundle in `pubspec` `fonts:` section):
  - body/handwriting: *Caveat* or *Kalam*,
  - headings/dates: *Lora* or *EB Garamond*.
- Date format: "Tuesday, 12 August 2025" style, small caps-ish.
- Page transition: stock `PageView` slide first; a page-turn style transform
  (`pageTransformBuilder`) is a nice-to-have later.

## 6. Milestones

- **[x] M1 – Skeleton & persistence:** pubspec deps, `Entry`/`ContentBlock`
  models, Hive boxes, `JournalStore` (load/save), `JournalScreen` PageView
  with a plain TOC page + plain entry pages, create/jump/delete working.
  (Validate Web build early: `flutter run -d web-server`.)
- **[x] M2 – Paper theme:** `PaperPage`, palette, fonts, rules, shadows, TOC
  styling. (App already "looks like a journal".)
- **M3 – Page viewport:** `PageViewport` with zoom/pan (pinch, wheel,
  ctrl+wheel, toolbar, fit/2× double-click), per-entry view persistence.
- **M4 – Free-positioned text blocks:** `EntryCanvas` + `BlockWidget` with
  select/drag/resize, add/delete text boxes, in-place text editing — built
  on the viewport's transform from M3.
- **M5 – Pictures as blocks:** pick image → downscale → store in assets box;
  add image block, drag/resize like text, tap → full-screen viewer.
- **M6 – Music:** pick audio file → assets box, `AudioService`
  (loop), `MusicPlayerBar` with manual play/pause on the page, stop on
  page swap.
- **M7 – Polish:** empty-state journal (a friendly "start writing" page),
  confirm dialogs for delete, error toasts, app icon/README, Web release
  pass (no-cam image source, audio focus quirks), optional page-turn
  animation.

## 9. M3 implementation plan – page viewport

M3 adds a reusable viewport around entry pages. It must work with touch,
mouse, trackpad and keyboard input on Android, Windows and Web while keeping
the TOC fixed at fit-to-screen. M3 does not add block editing; the viewport
must expose the transform and callbacks that M4 will use later.

### 9.1 Viewport contract

1. Create `lib/widgets/page_viewport.dart` with a small, testable API:
  - `child` for the rendered page/canvas;
  - `initialView` or equivalent `ViewState` input;
  - `ValueChanged<ViewState>` callback for persistence;
  - optional `enabled`/`interactive` flag so the TOC can remain fixed;
  - configurable min/max zoom with defaults around `0.5` and `3.0`.
2. Use `InteractiveViewer` as the transform owner. Keep one
  `TransformationController` per viewport and derive zoom/pan from that
  controller rather than maintaining a second competing transform.
3. Render a stable virtual page surface at the M1 dimensions of `100 x
  141.4` page units, then scale it to the available viewport using
  `LayoutBuilder`. Keep all future block coordinates in this virtual page
  space.
4. Define conversion helpers between the viewport's screen transform and
  `ViewState` page units. Clamp zoom and pan at one boundary so toolbar,
  pointer input and restored state cannot produce divergent values.

### 9.2 Input behavior

1. Touch and pointer drag should pan in read mode; pinch should zoom. Do not
  intercept gestures intended for future M4 block selection when the editor
  is enabled later.
2. Add a `Listener`/pointer-signal layer for desktop and Web wheel input:
  - ordinary wheel or trackpad scroll pans when zoomed in;
  - Ctrl+wheel changes zoom around the pointer position;
  - clamp the resulting transform to the configured bounds.
3. Add a compact overlay toolbar visible when the page is not at fit scale:
  - zoom out;
  - zoom in;
  - fit/reset.
  Use icon buttons with tooltips and stable button sizes so the overlay does
  not change the page layout.
4. Add double-tap/double-click handling on empty page space to toggle between
  fit and 2x. Keep the behavior accessible to touch and mouse users, and do
  not make it the only way to return to fit.
5. Store no viewport state for the TOC. The TOC uses `enabled: false` or an
  equivalent fixed-fit configuration.

### 9.3 Persistence and integration

1. Update `EntryPage` to wrap the entry content in `PageViewport` while
  retaining the existing `PaperPage`, navigation buttons and M2 typography.
2. Initialize each entry viewport from `entry.view`, treating null as fit.
  Normalize invalid persisted values before applying them, including NaN,
  infinity, zoom below the minimum, zoom above the maximum, and excessive
  pan values.
3. On meaningful transform changes, update `entry.view` and call the
  existing `JournalStore.updateEntry` path. Avoid writing on every raw pointer
  event; use a small debounce or update only after a settled controller
  change so dragging remains responsive.
4. Stop listening and dispose the transformation controller when an entry
  page is removed. Ensure PageView rebuilds do not reset a page's controller
  unnecessarily.
5. Preserve the PageView's `[ContentsPage, ...EntryPage]` ordering and all M1
  create, jump, swipe and delete flows. Deleting an entry must not leave a
  stale viewport listener or write view state to another entry.

### 9.4 Tests

#### Pure/unit tests

1. Test zoom and pan normalization, including default fit, min/max zoom,
  invalid persisted numbers, and page-unit conversion.
2. Test wheel intent: ordinary wheel pans, Ctrl+wheel zooms, and both paths
  clamp at their limits.
3. Test fit/2x toggle and persistence serialization through `ViewState` and
  `JournalStore`, including reopening an entry with its saved view.

#### Flutter widget tests

1. Add a focused `page_viewport_test.dart` using an injected transformation
  controller where practical. Assert the toolbar appears only after zooming,
  fit restores the default transform, and overlay buttons have tooltips.
2. Add pointer-signal tests for wheel and Ctrl+wheel. Use platform-agnostic
  Flutter pointer events rather than relying on a browser-specific event
  implementation.
3. Extend the existing live-binding `widget_test.dart` to create an entry,
  zoom it, return to the TOC, reopen it, and verify the view is restored.
  Retain the current create/jump/delete regression coverage.
4. Verify TOC behavior remains fixed: no viewport toolbar, no persisted TOC
  state, and normal row tapping still jumps to the correct entry.

#### Android validation

1. Run `flutter test` for unit and widget coverage, then build and launch a
  debug Android target on an emulator or connected device.
2. Manually validate one-finger pan, pinch zoom, fit/2x double-tap, toolbar
  controls, back-and-forth PageView navigation, and restored view state after
  leaving and reopening an entry.
3. Check narrow portrait and wider landscape layouts for clipped controls or
  page content and confirm the TOC remains fixed.

#### Windows validation

1. Run `flutter analyze`, `flutter test`, and `flutter build windows`.
2. Manually validate mouse drag pan, wheel pan, Ctrl+wheel zoom, double-click
  toggle, keyboard focus/tooltips, and toolbar hit targets.
3. Confirm a window resize preserves the virtual-page layout and does not
  reset the saved zoom/pan unexpectedly. Windows plugin builds may require
  Developer Mode as noted in `AGENTS.md`.

#### Web validation

1. Run `flutter build web` and start `flutter run -d web-server` for a browser
  smoke test.
2. Validate pointer drag, wheel pan, Ctrl+wheel zoom, trackpad pinch where
  available, double-click toggle, and browser resize.
3. Reload the browser and confirm Hive restores the entry view state. Check
  that browser scrolling does not move the document instead of the journal
  page, and that the TOC remains fixed.

### 9.5 M3 completion gate

M3 is complete when the viewport is reusable, the same transform drives all
input paths, entry view state survives navigation and reload, the TOC remains
fixed, all unit/widget tests pass, and Android, Windows and Web builds plus
their manual interaction checks succeed. M4 must be able to place and hit-test
blocks through the exposed page-unit transform without redesigning the
viewport.

## 7. Decisions (confirmed)

1. **Audio:** no autoplay; manual play/pause button on the page; music
   stops when the page is swapped.
2. **Page layout:** no fixed layout — text boxes and pictures are freely
   positioned (drag & drop / touch), stored in page units, z-ordered.
3. **Platforms:** Android, Windows, Web.
4. **Multiple text blocks** per page: yes.
5. **Images:** downscaled on save (max side 1600 px, JPEG q ~80) to keep
   storage small; resizable on the page via handles (display scaling only,
   stored original untouched).
6. **Block rotation:** not needed for now.
7. **Zoom & pan:** required — desktop/Web have far more screen space than
   mobile. Pinch/touch drag, scroll-wheel pan, ctrl+wheel zoom, on-screen
   −/+/fit toolbar; default fit-to-screen; per-page zoom/pan persisted in
   `Entry.view`. TOC stays fixed.

## 8. Remaining open points (defaults in brackets)

1. Block "bring to front" trigger? [toolbar button + double-tap in edit mode]
2. Plain scroll wheel over a zoomed page: pan or zoom? [pan; ctrl+wheel =
   zoom — matches map/Canvas conventions]
