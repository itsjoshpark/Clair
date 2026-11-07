# Tasks

Per CLAUDE.md, a task that needs a build is done only once CI passes on it. D3's patch changes the engine key, so `engine.yml` builds the branch's engine (with the owner's go-ahead) before the PR's checks can pass.

## 1. Spike on the published engine

- [x] 1.1 With a scratch `PageTopDragStrip` that logs each `hitTest(_:)` call (event type, event number, location, `NSCursor.current`) and calls `performDrag(with:)` on the first drag from a press under the arrow cursor, load design.md's cases (empty space, selectable and non-selectable text, link, button, image, `draggable` div, range input, an element that cancels `mousedown`, `cursor: text`, `pointer`, `crosshair` and `grab`) plus a cross-site iframe at the top of the page, through `run-local.sh`. Record in design.md, under a new Measurements section: whether `hitTest` runs for drag events through Chromium's hit test, what `NSCursor.current` returns over each case and in an inactive window, whether a click's events share an event number, whether `performDrag(with:)` starts from a drag event and the release then reaches the page, whether a double-click in the top 40 pt zooms the window today, and how `isMovable` false (D3) affects AppKit's title bar and `performDrag(with:)`. Verify that the rule in D1 gives Arc's outcome for every row; if it doesn't, settle the change with the owner before group 2.

- [x] 1.2 Add `patches/clair/page-cannot-move-window.patch` (D3), making `RenderWidgetHostViewCocoa`'s `mouseDownCanMoveWindow` answer NO, at the end of `patches/series`. Verify that the patch check applies it and that `engine.yml` builds the engine.

## 2. Native layer

- [x] 2.1 Add the preference (D4): `ClairDragWindowFromPageTop`, registered as true, read at each press. Verify with `defaults write` in task 2.3; no unit tests.
- [x] 2.2 Add `PageTopWindowDrag`, the state machine of D1, free of AppKit, with a few unit tests for the core rule only: a drag under the arrow moves the window, a drag under another cursor stays with the page, and a click without movement stays a click. The owner wants few tests for this feature: other cases are checked by hand and fixed if they break. Verify that `ClairUI`'s build and tests pass in CI.
- [x] 2.3 Add `PageTopDragStrip` to `PageCardView` above the page view, with its frame from the page view's (D2), and wire it and the safety net through `BrowserWindowController`. Verify with `run-local.sh` on macOS 27, on task 1.2's engine, that every row of design.md's table matches Arc, that the strip ends at 59 pt with the sidebar shown and hidden, that a page with a 120 px header drags only within 59 pt, that a link drag 10 pt below the page's top doesn't move the window while the sidebar's top still does, and that a drag from the strip in an inactive window activates and moves it; with the preference off (`defaults write`, no relaunch), that a drag from the top of the page leaves the window in place; and that tiling and Stage Manager behave as before. Result (2026-11-07): everything above passed; the owner checked tiling by hand, and Stage Manager wasn't checked, since the owner doesn't use it.

## 3. Verification

- [x] 3.1 Check by hand against Arc, side by side, with the XCUITest probe or CGEvents: double-click in the strip, a link click in the strip, a cancelled `mousedown` under the arrow, custom cursors, a tall page header, a drag from below into the strip (Clair stays, Arc moves), a drag over text in an inactive window (Clair moves the window, Arc applies its cursor rule), the find field and the command bar over the strip, docked DevTools, the crashed-page view, window and page full screen, a scrolled page, and the pointer after a window drag (no selection, nothing left pressed). Verify each item and note the results in the PR.
- [x] 3.2 Run `quality.yml` on the branch to confirm the existing runtime suite still passes. No new runtime test.
- [x] 3.3 Add a Changie fragment describing the new behavior and the `defaults write` command that turns it off until the Settings window exists. Verify that `changie batch --dry-run` renders it.

## Workflow follow-up

- Archive this change after `replace-browser-window` is archived, since this delta adds to the `browser-window` capability that change introduces.
- The future Settings window binds a toggle labelled "Allow window dragging from the top of webpages" to `ClairDragWindowFromPageTop`.
