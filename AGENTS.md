# Project Instructions

Cozy Bloom Journal is a Flutter journal app for Android, Windows, and Web.
`PLAN.md` is the current architecture and product roadmap.

## Architecture boundaries

- `lib/app/` is the composition root. Construct dependencies there and pass
  repository capabilities into features.
- `lib/ui/features/` contains feature view models and feature-facing views.
- `lib/services/` owns Hive, archives, assets, checkpoints, and persistence
  coordination. Feature code must not access raw `dart:io` storage paths.
- Screens and view models depend on narrow repository interfaces from
  `lib/services/repositories.dart`; they must not depend directly on raw Hive
  data sources or mutable storage records.
- `EntryDocument`, `CanvasNode`, `Transform2D`, and editor snapshots are
  immutable boundaries. `Entry` and `ContentBlock` are legacy mutable
  adapters and should stay at compatibility edges while the editor migrates.
- `EditorController` owns selection, transactions, undo/redo, and save state.
  Continuous gestures must begin and commit one transaction, producing one
  undo command and one persistence write.
- `CameraController`, `TransformService`, `HitTestService`,
  `BoundsService`, and `SnappingService` own page-camera and geometry policy;
  do not duplicate those calculations in widgets.

Keep the finite A4 paper page and page-local model coordinates intact. Web is
a first-class target, so storage and feature behavior must remain platform
neutral.

## Validation commands

Run these from the repository root:

```text
flutter pub get
flutter analyze
flutter test
flutter build appbundle --release
flutter build web --release
```

When using Codex on Windows, Flutter commands may need sandbox escalation so
Flutter can access its SDK and Gradle caches. If a command appears to hang,
interrupt only the recorded command session. Do not terminate unrelated
`dart.exe` processes; they may belong to the VS Code Flutter extension.

Windows desktop plugin builds may require Developer Mode for plugin symlinks.

## Test conventions

All tests use `flutter_test`; this project does not require a separate
`package:test` runner. The focused suites are:

- `test/journal_test.dart` — model serialization and Hive storage behavior;
  it uses real asynchronous storage I/O without widget binding.
- `test/editor_controller_test.dart` and `test/editor_history_test.dart` —
  editor commands, transactions, selection, and undo/redo.
- `test/entry_editor_view_model_test.dart` and
  `test/journal_view_model_test.dart` — view-model/repository boundaries.
- `test/canvas_geometry_test.dart` and `test/page_viewport_test.dart` —
  geometry services, camera state, page fitting, and viewport behavior.
- `test/widget_test.dart` — live-binding integration coverage for the app,
  Hive-backed navigation, paper page, editor, and touch interactions.

Any `testWidgets` test that builds `JournalApp` or otherwise touches Hive must
start with the live binding:

```dart
void main() {
  LiveTestWidgetsFlutterBinding.ensureInitialized();
  // ...
}
```

The default automated binding runs test bodies in a `FakeAsync` zone. Real
Hive file I/O can then strand continuations and make `Hive.close()` hang.
With the live binding, use ordinary `await`s, `tester.pumpAndSettle()`, and
`await Hive.close()`; do not add `runAsync` or custom settle helpers.

For Hive-backed widget tests, use a fresh temporary directory in `setUpAll`:

```dart
final temp = Directory.systemTemp.createTempSync('journal_widget_test');
Hive.init(temp.path);
```

Close Hive and delete that exact temporary directory in `tearDownAll`.

Avoid direct filesystem access in feature code. Hive uses local files on
Android and Windows and IndexedDB on Web.
