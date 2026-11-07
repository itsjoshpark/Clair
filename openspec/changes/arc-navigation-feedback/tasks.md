# Tasks

Wherever a verification below needs a running app, it means a `quality.yml` run dispatched on the branch (`gh workflow run quality.yml --ref <branch>`) against the engine published for the branch's key, unless it says "by hand", which means a check through `scripts/run-local.sh`. Engine builds go through `engine.yml` as `CLAUDE.md` describes, with the owner's go-ahead; check that the runner is online first. Chromium's source can be read, never written, in the runner's workspace.

Runtime tests cover the fundamentals only: the reload/stop fix and choosing a history entry. The rest is checked by hand against Arc.

Suggested order: 1, 2 (one engine build), then 3 and 4 in `ClairUI`, which can start against `FakeBrowser` during the build, then 5.

## 1. Measure Arc

- [ ] 1.1 With the XCUITest probe (CLAUDE.md, "Comparing with Arc and driving the UI"), drive Arc and record in design.md's Measurements section: the back and forward history menu (right-click, and whether press-and-hold opens it and after how long; its position against the button; its entries, cap, icons and labels, any separators, "Show Full History" or chapter stops; what Cmd-, Option- and middle-choosing do; what the `isAlternate` items are); the reload/stop button's behavior when a load ends under the pointer; and the loading indicator from a 60 fps `screencapture -v` recording of a slow page load with the sidebar shown and hidden (position, height, colour, blur, whether it follows progress or loops, fade-in delay and durations, what a stop or a failed load does, whether background tabs or same-document navigations show it). Verify that every item has a result, and update D2–D4 where Arc differs from what they assume.

## 2. Contract and engine

- [ ] 2.1 Add to `native/ClairHost.h`: `ClairTab.loadProgress`, the `isLoading` comment stating it's Chromium's loading-UI state (D1), and `ClairHistoryDirection`, `ClairHistoryItem`, `ClairHistoryMenu`, `ClairHistoryMenuDelegate` and `-[ClairBrowser startHistoryMenuWithDirection:delegate:]` (D3). Implement them in `FakeBrowser`, with entries and late favicons it can script. Verify that `ClairUI`'s build and unit tests pass in CI.
- [ ] 2.2 In the overlay: report `IsLoading() && ShouldShowLoadingUI()` as `isLoading` (D1); observe each tab's `LoadProgressChanged` and add `loadProgress` to the snapshot (D4); add `ClairHistoryMenuSession` over `BackForwardMenuModel`, listing history entries only, pushing icon changes, and opening entries through `ActivatedAt` with the disposition's flags (D3), in `clair_browser_bridge.mm` so the hook patch's source list stays as it is. Verify that `patches/` is unchanged, that the patch check applies and `engine.yml` builds the engine for the branch's key.

## 3. Reload and stop

- [ ] 3.1 Add `ReloadStopMode` (D2) and use it for the full row's reload button and the compact row's menu item; the tab row's spinner keeps reading `isLoading`. Add unit tests for the hover hold, its 1.35 s timeout, the double-click case and a tab switch. Verify that they pass in CI.
- [ ] 3.2 Add a runtime test: a page whose iframe reloads every 500 ms after the page has loaded, and a page that calls `history.pushState` on a timer; the reload button's accessibility label stays "Reload" for five seconds on each, and loading a slow page shows "Stop" until it ends. Verify that it passes in `quality.yml` on the branch, and that it fails against `main`'s engine (on a throwaway run) so it catches the bug.

## 4. History menu and loading indicator

- [ ] 4.1 Add `HistoryMenuBuilder` and the right-click and press-and-hold handling on the back and forward buttons in both top rows (D3), with the hold duration from task 1.1. Add unit tests against `FakeBrowser`: items in order with titles and icons, a late favicon updating an open menu's item, choosing an entry, Cmd-choosing (new background tab), and no menu when the tab can't go that way. Verify that they pass in CI.
- [ ] 4.2 Add a runtime test: visit three pages in one tab, open the back menu, choose the first page; the tab shows it and forward is enabled. Verify that it passes in `quality.yml` on the branch.
- [ ] 4.3 Add `LoadingIndicatorModel` and `LoadingIndicatorView` (D4), with the look and timings measured in task 1.1. Add unit tests for the model: fade in on a visible load, progress never going backwards within a load, fade out on finish and on stop, and a tab switch jumping to the new tab's state. Verify that they pass in CI.

## 5. Verification and release notes

- [ ] 5.1 **(owner)** Check by hand against Arc, side by side: the history menu's look, position and contents in both top rows, press-and-hold, Cmd-choosing, favicons arriving in an open menu; the loading indicator on a slow page, a fast page, a stopped load, a failed load, a tab switch mid-load, with the sidebar shown, hidden and revealed, in page full screen, in an incognito window and in Light and Dark Mode; and reload/stop on a page with busy iframes (a news site with ads). Verify each item and note the results in the PR.
- [ ] 5.2 Run `quality.yml` on the branch with the new engine. Verify that the whole runtime suite passes, including the tests from 3.2 and 4.2.
- [ ] 5.3 Add a Changie fragment for the history menu and the loading indicator, mentioning the reload/stop fix. Verify that `changie batch --dry-run` renders it.

## Workflow follow-up

- Archive this change after `replace-browser-window`, since its deltas add to the `sidebar` and `browser-window` capabilities that change introduces.
