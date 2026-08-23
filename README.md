# Journal App

A paper-styled digital journal for Android, Windows and Web. The journal uses
swipeable pages, a table of contents, local persistence, and a virtual page
coordinate system designed for freely positioned text and image content.

## Status

- [x] M1: skeleton, Hive persistence, PageView navigation, create/jump/delete
- [x] M2: paper theme, bundled fonts, ruled pages and styled TOC
- [ ] M3: zoom and pan viewport with per-entry view persistence
- [ ] M4-M7: editing, images, music and final polish

The active implementation plan is in [PLAN.md](PLAN.md). M3 is planned next.

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

- Android supports touch pan and pinch interactions planned for M3.
- Windows supports mouse, wheel and keyboard interactions planned for M3.
- Web supports browser file dialogs and IndexedDB. Camera capture through
  `image_picker` is unavailable on Web and will be hidden in the image flow.
- `just_audio` uses browser media facilities on Web and cannot provide
  background playback there.

## Architecture

- `lib/models/entry.dart`: entry, block and view-state serialization models
- `lib/services/journal_store.dart`: Hive-backed journal and asset storage
- `lib/screens/journal_screen.dart`: PageView over TOC and entries
- `lib/screens/contents_page.dart`: table of contents
- `lib/screens/entry_page.dart`: entry page rendering
- `lib/widgets/paper_page.dart`: M2 paper surface and painter
- `test/journal_test.dart`: model and persistence tests
- `test/widget_test.dart`: live-binding navigation and paper-theme tests

The application intentionally avoids direct `dart:io` storage in feature
code, allowing Android, Windows and Web to share the same persistence layer.
