# Cozy Bloom Journal

A botanical scrapbook journal for Android, Windows and Web. Cozy Bloom Journal
uses a framed paper page inside a Figma-like infinite workspace, local
persistence, freely positioned text and photos, and a small bundled sticker
pack.

## Status

- [x] M1: skeleton, Hive persistence, PageView navigation, create/jump/delete
- [x] M2: paper theme, bundled fonts, ruled pages and styled TOC
- [x] M3: zoom and pan viewport with per-entry view persistence
- [x] M4: PowerPoint-style text block editing, positioning, resizing and persistence
- [x] M5: pictures, branding, scrapbook home, and bundled stickers
- [ ] M6-M7: music, drawing, photo adjustments, and further polish

The active implementation plan is in [PLAN.md](PLAN.md). Music, drawing, and
photo adjustments are intentionally deferred.

## Run locally

Install Flutter with Android, Windows or Web support enabled, then run:

```text
flutter pub get
flutter run
```

Useful checks:

```text
flutter analyze
flutter test
flutter build web
flutter build windows
```

For a browser smoke test:

```text
flutter run -d web-server
```

Windows desktop plugin builds may require Windows Developer Mode for plugin
symlinks.

## Storage

All journal data is stored through Hive. Android and Windows use local files;
Web uses IndexedDB in the browser profile. The Web database is normally
limited by the browser, commonly around 50-500 MB, and is tied to that
browser profile rather than being synced to a server.

The `entries` box stores serialized entries and the `assets` box stores image
and audio records. Feature code should use `JournalStore` rather than direct
filesystem access so the same path remains compatible with Web.

## Platform notes

- Android supports touch pan, pinch zoom, block movement, resizing and text
  editing.
- Windows supports mouse, wheel, keyboard, block movement, resizing and text
  editing.
- Web supports browser file dialogs and IndexedDB. Camera capture through
  `image_picker` is unavailable on Web and will be hidden in the image flow.
- `just_audio` uses browser media facilities on Web and cannot provide
  background playback there.

## Architecture

- `lib/models/entry.dart`: entry, block and view-state serialization models
- `lib/models/sticker.dart`: bundled sticker catalog and metadata
- `lib/services/journal_store.dart`: Hive-backed journal and asset storage
- `lib/screens/journal_screen.dart`: PageView over TOC and entries
- `lib/screens/contents_page.dart`: table of contents
- `lib/screens/entry_page.dart`: entry page rendering
- `lib/widgets/paper_page.dart`: M2 paper surface and painter
- `lib/widgets/page_viewport.dart`: M3 zoom and pan viewport
- `lib/editor/entry_canvas.dart`: M4 free-positioned block canvas
- `lib/editor/block_widget.dart`: selectable, movable and resizable text blocks
- `lib/editor/editor_toolbar.dart`: scrapbook edit-mode creation/context bar
- `test/journal_test.dart`: model and persistence tests
- `test/page_viewport_test.dart`: viewport behavior tests
- `test/widget_test.dart`: live-binding navigation, paper-theme and editor tests

The application intentionally avoids direct `dart:io` storage in feature
code, allowing Android, Windows and Web to share the same persistence layer.
