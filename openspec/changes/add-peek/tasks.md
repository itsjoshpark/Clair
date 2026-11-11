# Tasks

Group 1 changes the engine key, so build the engine first and push docs afterwards, as `CLAUDE.md` describes. "CI" is the merge gate in `ci.yml`. "By hand" means the owner launches a test build of the branch; behaviour driven by the pointer or compared with Arc is checked there. `quality.yml` runs on the branch before merging (`gh workflow run quality.yml --ref <branch>`).

Suggested order: 1, then 2 and 3 (2 can start in `ClairUI` against `FakeBrowser` while the engine builds), then 4, 5 and 6.

## 1. Contract and engine

- [ ] 1.1 Add `peekParentID` and `peekID` to `ClairTab`, `closePeekOfTab:` and `expandPeekOfTab:` to `ClairBrowser`, and `opensPeekOnShiftClick` and `peekDidKeepEscape:` to `ClairWindow` in `native/ClairHost.h` (D3). Update `FakeBrowser`, `FakeHost` and their tests. Verify in CI that ClairUI builds and its unit tests pass.
- [ ] 1.2 Add the Peek table to the bridge in `overlay/chrome/browser/clair/window/` (D1): fill the two `ClairTab` fields in the tab snapshot, implement `closePeekOfTab:` (closing the Peek and activating its parent) and `expandPeekOfTab:` (unlinking), and report both pages visible while a Peek is active (D4). Add the `TabStripModelObserver` that closes a parent's Peek with it, moves it with it, and unlinks a Peek moved or detached on its own (D8). Verify by the engine build in 1.6 and the runtime tests in 2.6.
- [ ] 1.3 Add `clair::MaybeOpenPeek` to `clair_window_hooks` and its calls at the start of `BrowserWebContentsDelegate::OpenURLFromTab` and `AddNewContents` in `patches/clair/native-window-hook.patch` (D2). Cover: native window, `NEW_WINDOW`, renderer-initiated with a user gesture, the preference, a source that is a Peek (new tab at the top), and a source that already has a Peek (navigate it). Verify that `./build.sh fetch prepare` applies the patch in CI's patch check, and by the runtime tests in 2.6.
- [ ] 1.4 Handle `IDC_SELECT_NEXT_TAB`, `IDC_SELECT_PREVIOUS_TAB`, `IDC_SELECT_TAB_0`…`7` and `IDC_SELECT_LAST_TAB` over the tabs that aren't Peeks, and `IDC_DUPLICATE_TAB` and `IDC_MOVE_TAB_TO_NEW_WINDOW` on the parent, in `ExecuteCommand` in `clair_native_window.mm` (D7). Verify by the runtime tests in 2.6.
- [ ] 1.5 Add Esc handling for an active Peek to `ClairBrowserWindow` (D6): an Esc the page didn't use closes the Peek; an observer of the Peek's main-frame widget arms Confirm for 1 s on a consumed Esc and calls `peekDidKeepEscape:`; Esc while armed closes the Peek before the page sees it. Verify by the runtime tests in 3.2.
- [ ] 1.6 Close a window's Peeks before its tabs close, and every window's Peeks before quitting (D9). Verify by the runtime test in 5.1.
- [ ] 1.7 Build the engine with `gh workflow run engine.yml -f ref=<branch>`. Verify that `chromium-engine-<key>` is published and CI's engine check passes.
- [ ] 1.8 Fix the code review's findings (D4, D7, D8, D9): a parent made active any other way shows its Peek; a Peek moved away on its own hides its parent; Peeks are tagged in the saved session and left out of session restore and Reopen Closed Window (D9, `patches/clair/peek-session.patch`), so a close or quit a page cancels keeps them; Move Tab to New Window closes the Peek once; only an adjacent tab is linked; and the fake browser, `tabsBelow` and the sidebar's list follow the engine. Verify that CI's patch check applies the new patch, with unit tests in CI, the engine build, and the runtime tests `testThePeekComesBackSurvivesACancelledCloseAndStaysBehindAMove` (with Reopen Closed Window) and `testEscapeTheLinksSettingAndQuitting` (quit and relaunch) in a `quality.yml` run on the branch.

## 2. Sidebar and the Peek card

- [ ] 2.1 Add pure helpers to `TabListLogic.swift`: the rows (tabs that aren't Peeks), the row to highlight for an active Peek, the tab to activate for a row (its Peek, if any), and the badge favicon. Verify with unit tests in CI: a Peek is never a row, its parent's row is highlighted while the Peek is active, a click on that row targets the Peek, and expanding gives the Peek a row directly below its parent.
- [ ] 2.2 Use them in `SidebarView.swift`: no row for a Peek, the badge at the trailing end of its parent's row, and a click on that row showing the Peek. Copy Link and Duplicate use the parent's snapshot. Verify by hand against Arc: the badge's size and place, with and without a favicon.
- [ ] 2.3 Add a pure helper for the Peek's geometry: card 80% of the page card's width and its height less 2 pt at top and bottom, centred; parent inset 9 pt per side; buttons 34.5×33.5 pt, 13 pt beside the card, 7.5 pt down, 43.5 pt apart, clear of the title bar's safe area, with 12 pt and 14 pt glyphs. Lay out the Peek in `PageCardView.swift` from it (D4): the parent scaled behind the wash and the click catcher, the Peek's page view in a rounded, shadowed container, and `pageContainerView` returning that container. The status capsule follows the Peek's corner (D11). Verify with unit tests of the helper at Arc's 1723×1030 card (1386×1026), passing in CI, and by hand side by side with Arc in Light and Dark Mode, including the wash's colour.
- [ ] 2.4 Add the Close and Expand buttons and the Confirm pill, wired to `closePeekOfTab:` and `expandPeekOfTab:`, with tooltips in Arc's wording (read from Arc by hovering) and VoiceOver labels. Verify by hand against Arc: the highlight under the pointer, the tooltips, and the pill's look.
- [ ] 2.5 Add the opening and closing animations from the last mouse-down in the card, the Reduce Motion fades, and Expand moving the Peek into the full card (D5). Verify by hand with 60 fps recordings of Clair and Arc side by side: Arc's ease-out, about 190 ms to open and 150 ms to close, growing from and shrinking to the click point, the buttons riding the card's corner, and no frame without the card while a closing Peek's page goes.
- [ ] 2.6 Add runtime tests to `tests/runtime/` with a local page of links:
  - Shift+click opens a Peek: no new window and no new row, the parent's row badged and highlighted, the URL field showing the Peek's host.
  - A `target="_blank"` link opens a Peek too.
  - Close, Cmd+W and a click outside each close it and leave the parent active.
  - Expand gives a new row directly below the parent, with back returning through the Peek's history.
  - Ctrl+Tab and Cmd+number leave the Peek open, and selecting the parent shows it again.
  - Closing the parent's row closes both.
  - Shift+click inside a Peek opens a tab at the top.
  - `document.visibilityState` over CDP for both pages, with the Peek shown and with another tab active.

  Verify with a `quality.yml` run on the branch.
- [ ] 2.7 Turn reload into stop only once a load has run 750 ms, and crossfade the two glyphs (D12). Verify with unit tests of `ReloadStopMode` in CI, and by hand with 60 fps recordings of Clair and Arc opening Peeks on pages a local server delays by 200 ms to 3 s.

## 3. Esc and Confirm

- [ ] 3.1 Show the Confirm pill on `peekDidKeepEscape:` for the given duration: it grows from the ×, holds, and returns to the ×. A click on the pill closes the Peek. Verify by hand against Arc with a 60 fps recording: about 100 ms in, about 1 s held, about 100 ms out.
- [ ] 3.2 Add runtime tests with a page that keeps Esc:
  - Esc on a page that ignores it closes the Peek.
  - With the page's own modal open, Esc closes the modal and keeps the Peek, and a second Esc closes the Peek.
  - With text in a focused field, Esc keeps the Peek.
  - After two seconds, Esc reaches the page again.

  Verify with a `quality.yml` run on the branch, and check a native `<dialog>` by hand, noting whether Clair shows Confirm or closes at once.

## 4. Settings

- [ ] 4.1 Add the Links page between General and Advanced in `SettingsWindow.swift`, with the toggle "Open a Peek window when clicking on links with Shift held" for `ClairPeekOnShiftClick` (on by default), and answer `opensPeekOnShiftClick` from it live (D10). Verify with unit tests in `SettingsTests` (page order, the toggle's default and stored value), passing in CI, and with a runtime test that turns it off and sees Shift+click open a new window, in a `quality.yml` run on the branch.

## 5. Session

- [ ] 5.1 Add a runtime test that quits with a Peek open, relaunches with session restore on, and finds the parent tab alone. If Chromium restores the Peek, switch D9 to its fallback (tag with `AddTabExtraData` and drop on restore, a hook in session restore), update the design, and build the engine again. Verify with a `quality.yml` run on the branch.

## 6. Release notes and integration

- [ ] 6.1 Add a Changie fragment (`changie new`, kind New) for Peek on Shift+click and the Links page in Settings. Verify that it's in the PR.
- [ ] 6.2 Run `openspec validate --all --strict` and the merge gate, and verify that CI passes.
- [ ] 6.3 Run `quality.yml` on the branch and verify that it passes before merging.
- [ ] 6.4 By hand, side by side with Arc: Shift+click, switching tabs and back, expanding, Esc on a page that keeps it, and the Links toggle.

## Workflow follow-up

- After the implementation PR merges, one docs-only PR ticks the quality task, syncs the delta specs and archives the change.
