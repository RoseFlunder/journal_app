# Cozy Bloom Journal

A botanical scrapbook journal for Android, Windows and Web. Cozy Bloom Journal
uses a finite A4 ruled-paper page inside a zoomable workspace, local
persistence, freely positioned text and photos, vector ink drawing, and a
small bundled sticker pack.

## Status

- [x] M1: skeleton, Hive persistence, PageView navigation, create/jump/delete
- [x] M2: paper theme, bundled fonts, ruled pages and styled TOC
- [x] M3: zoom and pan viewport with per-entry view persistence
- [x] M4: PowerPoint-style text block editing, positioning, resizing and persistence
- [x] M5: pictures, branding, scrapbook home, and bundled stickers
- [x] M6: vector drawing, shared color selection, and image adjustments
- [~] M7: per-page Jamendo music and further polish

The active implementation plan is in [PLAN.md](PLAN.md). Pages can attach and
stream Creative Commons music from Jamendo; further polish and creative-tool
work are tracked there.

Shapes are implemented in the editor and persistence layers, but the feature
is intentionally hidden from the user interface until the shape tools are
polished for release.

The text editor bundles Caveat, Lora, Patrick Hand, and Playfair Display.
Patrick Hand and Playfair Display are distributed under the SIL Open Font
License; the corresponding license texts are kept in `assets/fonts/`.

## Run locally

Install Flutter with Android, Windows or Web support enabled, then run:

```text
flutter pub get
flutter run
```

To enable the Jamendo picker, register a noncommercial Jamendo developer app
and put its client ID in the external file
`%USERPROFILE%\.config\cozy_bloom\build-defines.json`:

```json
{
  "JAMENDO_CLIENT_ID": "your_actual_client_id"
}
```

Pass that file during build or run time:

```text
flutter run --dart-define-from-file="C:\Users\Steph\.config\cozy_bloom\build-defines.json"
flutter build appbundle --release --dart-define-from-file="C:\Users\Steph\.config\cozy_bloom\build-defines.json"
flutter build windows --release --dart-define-from-file="C:\Users\Steph\.config\cozy_bloom\build-defines.json"
flutter build web --release --dart-define-from-file="C:\Users\Steph\.config\cozy_bloom\build-defines.json"
```

Or use the repository wrapper, which defaults to that external file:

```powershell
.\tool\build_with_defines.ps1 appbundle
.\tool\build_with_defines.ps1 windows
.\tool\build_with_defines.ps1 web
```

If PowerShell script execution is restricted on Windows, use the equivalent
command wrapper (it does not require changing the execution policy):

```text
tool\build_with_defines.cmd appbundle
tool\build_with_defines.cmd windows
tool\build_with_defines.cmd web
```

Both wrappers accept an optional second argument to select a different defines
file.

The client ID is an application identifier distributed with the client build,
not a user login. Page music is streamed on demand and is not copied into Hive
or `.cozyjournal` backups.

### Optional Google Drive sync

Cloud sync is opt-in and local-first. Without an account, the journal remains
fully available offline. When enabled and connected, committed pages, their
referenced media, page order, and page music references are synchronized to
Google Drive's hidden `appDataFolder` using the narrow `drive.appdata` scope.
The data is protected by Google but is not end-to-end encrypted.

Enable the feature only after configuring OAuth clients for Android, Web, and
Windows. Add the public client IDs to the same defines file and set the feature
flag:

```json
{
  "COZY_BLOOM_CLOUD_SYNC": "true",
  "GOOGLE_WEB_CLIENT_ID": "...",
  "GOOGLE_DESKTOP_CLIENT_ID": "...",
  "GOOGLE_SERVER_CLIENT_ID": "..."
}
```

Android identifies the app by its package name and signing SHA fingerprints;
the Dart configuration uses the Web client as `GOOGLE_SERVER_CLIENT_ID` when
`google-services.json` is not bundled. Web authorization is intentionally a
separate user action after sign-in and may need to be repeated when its
short-lived access token expires.

The first connected Google account permanently binds the local journal to that
account. Signing out keeps local pages; changing accounts requires the
explicit device-reset action. Templates, preferences, checkpoints, recovery
history, credentials, and editor history remain device-local. Sync runs while
the app is open and retries transient failures; there is no background push
while the app is closed.

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

Versioned `cozyBloom.*.v2` Hive boxes store canonical documents, manifests,
content-addressed assets, checkpoints, view preferences, and sync heads.
Feature code should use the narrow repository interfaces; focused Hive
capability sources keep the same path compatible with Web. Pre-freeze records
and version-1 archives are intentionally not imported.

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

- `lib/models/document.dart`: immutable document and canvas-node boundaries
- `lib/models/sticker.dart`: bundled sticker catalog and metadata
- `lib/services/hive_journal_data_source.dart`: raw Hive box access
- `lib/services/hive_capability_sources.dart`: focused document, asset,
  checkpoint, template, preference, and archive data sources
- `lib/services/repositories.dart`: repository capability contracts
- `lib/services/hive_repositories.dart`: Hive repository adapters
- `lib/services/persistence_coordinator.dart`: ordered save/flush lifecycle
- `lib/services/sync_models.dart`: immutable cloud heads, version vectors, and
  asset descriptors
- `lib/services/cloud_sync_coordinator.dart`: local-first merge, retry, and
  lifecycle coordination
- `lib/services/cloud_sync_repository.dart`: immutable sync state and the
  feature-facing synchronization contract
- `lib/services/cloud_gateway.dart`: platform-neutral account and Drive
  capability contracts plus the REST adapter
- `lib/services/platform_cloud_account_gateway_*.dart`: Android/Web/Windows
  authentication implementations
- `lib/platform/cloud_sign_in_button*.dart`: platform presentation adapter for
  the Web sign-in control
- `lib/ui/features/journal/views/journal_screen.dart`: PageView over TOC and entries
- `lib/ui/features/journal/views/contents_page.dart`: table of contents
- `lib/ui/features/journal/view_models/cloud_sync_view_model.dart`: sync
  account/progress state presented to the journal shell
- `lib/ui/features/editor/views/entry_page.dart`: entry page rendering
- `lib/widgets/paper_page.dart`: M2 paper surface and painter
- `lib/widgets/page_viewport.dart`: M3 zoom and pan viewport
- `lib/widgets/camera_controller.dart`: page camera matrix and view state
- `lib/editor/entry_canvas.dart`: M4 free-positioned block canvas
- `lib/editor/block_widget.dart`: selectable, movable and resizable text blocks
- `lib/editor/editor_controller.dart`: editor commands and transactions
- `lib/editor/geometry_services.dart`: transform, hit-test, bounds, and snap policy
- `lib/ui/features/editor/views/editor_toolbar_view.dart`: scrapbook edit-mode
  creation/context bar
- `test/journal_test.dart`: model and persistence tests
- `test/page_viewport_test.dart`: viewport behavior tests
- `test/widget_test.dart`: live-binding navigation, paper-theme and editor tests
- `test/architecture_boundary_test.dart`: UI/data import-boundary checks

The application intentionally avoids direct `dart:io` storage in feature
code, allowing Android, Windows and Web to share the same persistence layer.
