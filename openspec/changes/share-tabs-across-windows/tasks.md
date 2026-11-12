# Tasks

Groups 1 and 2 change the engine key, so build the engine first and push docs afterwards, as `CLAUDE.md` describes. "CI" is the merge gate in `ci.yml`. "By hand" means the owner launches a test build of the branch; behaviour compared with Arc is checked there with `tests/probe/`. `quality.yml` runs on the branch before merging (`gh workflow run quality.yml --ref <branch>`). D-numbers are `design.md`'s decisions; "`add-spaces` D*n*" is a decision in `openspec/changes/archive/2026-11-12-add-spaces/design.md`, and its `arc-reference.md` has Arc's behaviour.

Suggested order: 1, then 2 with one engine build at 2.7. Group 3 can start in `ClairUI` against `FakeHost` and `FakeBrowser` as soon as 1 is done, while the engine builds. Group 4 is last.

Read `design.md` in full before starting. Verify every Chromium call it names against the engine workspace's source before using it, and update the design if one differs.

## 1. Contract and fakes

- [ ] 1.1 Change `native/ClairHost.h` as D5 lists: add `stillTabID` and `stillImage` to `ClairBrowser` and `stillDidChange` to `ClairWindow`, and revise the comments on `-[ClairHost tabsInSpace:]` and `ClairBrowser.shownSpaceID` that say a window lists the tabs with its own `browserID`. Document each as the header documents the rest. Verify that the header compiles in `ClairHostObjCxxTests.mm` in CI.
- [ ] 1.2 Update `FakeHost` and `FakeBrowser` to the shared list: selecting a tab another browser holds takes it (D1) and leaves that browser a still when it was showing the tab (D2); the still ends as D2 lists; showing a Space, the came-from rule and the tab commands look across browsers (D3); closing a browser hands its tabs to another (D4). Verify with new cases in `FakeBrowserTests` in CI: take and take back; the still's tab closing; showing a Space whose tabs are held elsewhere, and one whose only tab is showing elsewhere; the row above held elsewhere, showing and not; closing a window with another open.
- [ ] 1.3 Make `BrowserWindowController` copy its shown Space's whole list from `SpacesModel` into `BrowserWindowModel`, keeping the `browserID` filter for an incognito or guest window, and drop the mapping of a dragged row around other windows' tabs (D1). Verify with `ClairUI` unit tests in CI: two windows on one Space list the same rows; a row dragged in one is moved in the other; an incognito window lists only its own tabs; and the existing tests pass with none deleted.

## 2. Engine

- [ ] 2.1 Implement take (D1) in `clair_browser_window.mm` and `clair_space_tabs.mm`: `-[ClairBrowser activateTab:]` on a tab another browser holds closes its Peek, detaches it with `DetachTabAtForInsertion` and inserts it here, active, with `InsertDetachedTabAt`, never while a strip notifies its observers. Keep the tab's Space, its place in the Space's list and its session tags, and push its new `browserID`. Verify with the runtime tests in 3.4: a tab opened in one window and selected in another shows its page's counter unchanged.
- [ ] 2.2 Implement the still and its placeholder (D2): copy the page with `CopyFromSurface` under a 250 ms timeout before the tab leaves; insert and activate a placeholder marked in its `WebContents` user data, which `ClairSpaceTabs` puts in no Space and which leaves the browser's shown Space alone; record `stillTabID` and `stillImage` and call `stillDidChange`. End the still in each of D2's three ways, the window becoming key included. Verify with the runtime tests in 3.4: taking, taking back, selecting another row, switching Space, and closing the still's tab.
- [ ] 2.3 Make showing a Space and the came-from rule look across browsers (D3) in `clair_browser_window.mm`: `showSpace:` prefers the tab last active here unless another browser shows it, then the Space's most recently active tab no browser shows; the next tab after a close is chosen among all the Space's rows and taken when held elsewhere; the Space's last tab takes a tab of another Space that no browser shows, or lets the browser close. Keep the wait for a page that asks before leaving (`add-spaces` D4). Verify with the runtime tests in 3.4, which replay `arc-reference.md`'s close sequences across two windows.
- [ ] 2.4 Run `ClairBrowserWindow::ExecuteTabCommand`, `closeTabsBelowTab:`, `closeTab:` and `moveTab:toIndex:` over the Space's whole list (D3), taking a selected tab held elsewhere and closing a tab in whichever browser holds it. Verify with the runtime tests in 3.4: Cmd+number and Next Tab reach a tab from another window; Close Tabs Below closes rows another window holds; closing another window's active row leaves that window on its own next tab.
- [ ] 2.5 Hand a closing window's tabs to the most recently active other regular window of the profile (D4) before the browser closes, leaving out a placeholder and closing each moved tab's Peek, and keep Chromium's close flow for the last regular window and for incognito and guest windows. Verify with the runtime tests in 3.4: the other window lists the tabs and shows one without a reload; no leave-page prompt shows; closing the last window closes its tabs, and Reopen Closed Window brings them back.
- [ ] 2.6 Check session restore (D2): a placeholder gets no session tags, and after a relaunch no window shows a still and no tab is listed twice. Verify with the runtime test in 3.4 that quits while a window shows a still.
- [ ] 2.7 Build the engine with `gh workflow run engine.yml -f ref=<branch>`. Verify that `chromium-engine-<key>` is published and CI's engine check passes.
- [ ] 2.8 Update `docs/native-window.md` with take, the placeholder and its two exceptions, and where a closing window's tabs go. Verify that every file and decision it names exists.

## 3. ClairUI

- [ ] 3.1 Show the still (D2): on `stillDidChange`, `PageCardView` draws `stillImage` dimmed over the card, or dims the card's background when there is no image; the sidebar highlights `stillTabID`'s row; the URL field is empty; back, forward and reload are disabled. Clear all four when the still ends. Verify with unit tests of `BrowserWindowModel`'s still state in CI (the highlighted row, the empty URL field, the disabled controls, with and without an image).
- [ ] 3.2 Make row actions work on a row another window holds: select, close, middle-click, mute, Copy Link, Duplicate, Move to Space and drag. Verify with unit tests against `FakeHost` in CI for each action on a row with another `browserID`.
- [ ] 3.3 Check the flow by hand against Arc with `tests/probe/`, two windows of each side by side: the dimmed still's look, the highlighted row while not key, taking back by a click anywhere in the window, and the list updating in both. Verify by the owner accepting the comparison.
- [ ] 3.4 Add runtime tests to `tests/runtime/`, using the local page with a counter:
  - Two windows on one Space list the same tabs in the same order; a tab opened, closed or moved in one shows in the other; Cmd+N lists the Space's tabs.
  - Selecting, in window B, the tab window A shows keeps the page's counter; A shows the still's state (row highlighted, URL field empty, back, forward and reload disabled). Clicking in A takes it back.
  - Selecting a tab another window holds but doesn't show leaves that window unchanged.
  - Closing the still's tab leaves that window on a new tab page with the command bar; selecting another row or Space ends the still.
  - Switching to a Space whose tabs are held elsewhere shows the more recently active one; with its only tab showing elsewhere, a new tab page.
  - The close sequences of `arc-reference.md` with the row above held by another window, showing and not; closing a Space's last tab.
  - Cmd+number, Next Tab and Close Tabs Below over rows from another window.
  - A tab with a Peek taken by another window shows without it.
  - Closing a window with another open keeps its tabs, without a reload or a leave-page prompt; closing the last closes them, and Reopen Closed Window brings them back.
  - An incognito window still lists only its own tabs.
  - Quit while a window shows a still, and relaunch: that window shows a new tab page, and the tab is listed once.

  Give the still an accessibility identifier so the tests can find it. Verify with a `quality.yml` run on the branch.

## 4. Release notes and integration

- [ ] 4.1 Add a Changie fragment (`changie new`, kind Changed) for tabs shared across windows. Verify that it's in the PR.
- [ ] 4.2 Run `openspec validate --all --strict` and the merge gate, and start `quality.yml` on the branch with the last push. Verify that CI and the quality checks pass.
