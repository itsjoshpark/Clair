# Tasks

Per CLAUDE.md, a task that needs a build is done only once CI passes on it. This change touches only `ClairUI` and the runtime suite, so the engine key doesn't change and no `engine.yml` run is needed.

## 1. Settings window

- [x] 1.1 Add `SettingsWindowController` with the menu takeover (D1) and the one-window lifecycle (D7), and start it from `NativeLayer` after About. The project's folder reference compiles new files in `native/ClairUI/` and `native/ClairUITests/`, so `project.xcproj` needs no change. Add `SettingsTests.swift` with unit tests that `install(in:)` retargets the item tagged 40015 and retitles it "Settings…", that a menu without that tag is left alone and `install(in:)` returns false, and that choosing the item twice shows the same, visible window. Verify that `ClairUI`'s build and unit tests pass in CI.
- [x] 1.2 Add the `NSTabViewController` in toolbar style with the `SettingsPage` enum, General then Advanced, each an `NSHostingController` around a grouped `Form` sized to its content at a fixed width of 520 points, the title following the selected page, and the selection stored under `ClairSettingsPage` (D2, D3). Add a unit test that the window opens on the stored page and falls back to General for a missing or unknown value. Verify that `ClairUI`'s build and unit tests pass in CI.
- [x] 1.3 Add the General page's Default Browser row (D4): the state from the `https` handler's bundle identifier, "Make Default" through `setDefaultApplication(at:toOpenURLsWithScheme:)` with `http`, and a refresh when the call completes and whenever the window becomes key. No unit test (D8). Verify by hand in task 3.1.
- [x] 1.4 Add the Advanced page: the "Allow window dragging from the top of webpages" toggle bound to `WindowDragPreference.key` with a default of true (D5), and "More Settings…" calling `host.open` with `chrome://settings` (D6). The button also closes the Settings window. Add a unit test that the button opens `chrome://settings` on `FakeHost` and closes the window. Verify that `ClairUI`'s build and unit tests pass in CI.

## 2. Runtime check

- [x] 2.1 Extend `testApplicationMenuNamesClair` in `tests/runtime/ClairRuntimeTests/RuntimeTests.swift` and rename it `testApplicationMenu` (D8): exactly one Clair menu item titled "Settings…" and none titled "Preferences…"; choosing Settings… shows a window titled "General" with General and Advanced toolbar items; and afterwards no page target's URL starts with `chrome://settings`. Verify that it passes in a `quality.yml` run on the branch, along with the rest of the runtime suite.

## 3. Verification and release notes

- [x] 3.1 Check by hand with `scripts/run-local.sh`, and note the results in the PR: Cmd+, opens the window with a browser window key, and Settings… opens it with no browser window open; choosing Settings… again brings the same window forward; switching pages changes the content and the title, with the window resizing to each page; the window reopens on the last page after a relaunch; turning the toggle off stops a drag from the top of an open window's page from moving the window, and turning it on restores it, without relaunching; "More Settings…" closes the Settings window and opens `chrome://settings` in a new tab of the last active window, and in a new window when none is open; Cmd+W and the close button close the Settings window (if Cmd+W doesn't, apply the fallback in design.md's risks); the window looks right in Light and Dark. For the Default Browser row, note the current default browser first, then check the row's state, "Make Default" and macOS's prompt, a change made in System Settings showing up when the window comes forward, and restore the original default at the end.
- [x] 3.2 Add a Changie fragment (kind New) saying that Settings… (Cmd+,) opens Clair's own Settings window, with the default browser, the window dragging toggle, and "More Settings…" for Chromium's settings. Verify that `changie batch --dry-run` renders it.

## Workflow follow-up

- Archive this change once the PR is merged and quality checks pass on `main`.
- Later features add their pages or rows to `SettingsPage`: Peek a Links page, Spaces and profiles a Profiles page and Chromium's per-profile preferences.
