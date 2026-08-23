# Project Instructions

Flutter journal app. Plan and architecture: `PLAN.md`.

## Running tests

```sh
flutter test
```

## Running the analyzer from Codex

```sh
flutter analyze
```

Run this command with sandbox escalation (outside the workspace filesystem
restriction). Flutter needs access to its SDK cache and lock files under the
user's Flutter installation. Inside the workspace-only sandbox, even
`flutter --version` can hang without producing output; this is not an analyzer
or output-capture problem. With escalation, `flutter analyze` returns its
normal output in a few seconds.

If a sandboxed attempt hangs, interrupt only that recorded command session.
Do not terminate unrelated `dart.exe` processes, because they may belong to
the VS Code Flutter extension.

Reference tests:

- `test/journal_test.dart` — pure unit tests (plain `test()`, no widget
  binding, real async, direct awaits on Hive are fine)
- `test/widget_test.dart` — widget test that builds the app and touches
  Hive, using the **live binding** pattern (see below)

## Rules for writing widget tests in this repo

The app persists to **real files via Hive** (`lib/services/journal_store.dart`).

1. **Any `testWidgets` test that builds `JournalApp` (i.e. touches Hive) must
   start its `main()` with the live binding:**

   ```dart
   void main() {
     LiveTestWidgetsFlutterBinding.ensureInitialized();
     // ...
   }
   ```

2. **Why:** the default (automated) binding runs the test body in a
   FakeAsync zone. Hive does real `dart:io` file I/O; its continuations get
   stranded in the fake zone, so writes never drain and `Hive.close()` hangs
   *silently* (suite freezes, usually at `tearDownAll`, with no error
   message). The live binding runs everything on the real event loop, so
   plain `await`s just work. Cost: animations take real wall-clock time
   (test runs a few seconds slower).

3. **With the live binding, write tests plainly:**
   `await store.init();`, `await tester.tap(...)`,
   `await tester.pumpAndSettle();` — no `runAsync`, no custom settle
   helpers, and `await Hive.close()` is safe in `tearDownAll`.

4. **Use a fresh temp dir per run:** `Directory.systemTemp.createTempSync(...)`
   + `Hive.init(temp.path)` in `setUpAll`; `await Hive.close()` and delete the
   dir in `tearDownAll`.

5. **If `flutter test` appears to hang with no output**, check for and kill
   only the process/session started for that test run, then retry. Record its
   PID/session ID when starting it. Do not kill `dart.exe` processes merely
   because they exist; inspect their command lines first, since they may belong
   to the VS Code Flutter extension. (Windows: inspect with
   `Get-CimInstance Win32_Process -Filter "Name='dart.exe'"`, and kill a
   verified stale process with `taskkill /T /F /PID <pid>`.)

## Other repo notes

- Windows desktop builds require Windows **Developer Mode** (plugin symlinks).
- Web is a first-class target; keep storage on Hive (never raw `dart:io` paths
  in feature code) so Web keeps working.
