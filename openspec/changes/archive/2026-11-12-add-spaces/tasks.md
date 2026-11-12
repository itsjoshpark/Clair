# Tasks

`add-clair-dialogs` must be merged first. Groups 1 and 2 change the engine key, so build the engine first and push docs afterwards, as `CLAUDE.md` describes. "CI" is the merge gate in `ci.yml`. "By hand" means the owner launches a test build of the branch; behaviour compared with Arc is checked there with `tests/probe/`. `quality.yml` runs on the branch before merging (`gh workflow run quality.yml --ref <branch>`). D-numbers are `design.md`'s decisions; `arc-reference.md` has Arc's measurements and wording.

Suggested order: 1, then 2 with one engine build at 2.9. Group 3 can start in `ClairUI` against `FakeHost` and `FakeBrowser` as soon as 1 is done, while the engine builds. Group 4 is last.

Read `design.md` in full before starting. Verify every Chromium call it names against the engine workspace's source before using it, and update the design if one differs.

## 1. Contract and fakes

- [x] 1.1 Change `native/ClairHost.h` as D9 lists: add `ClairSpace` and `ClairSpacesObserver`; add `spaces`, `tabsInSpace:`, `addObserver:` and the Space calls to `ClairHost`; add `spaceID` and `browserID` to `ClairTab`; add `browserID`, `shownSpaceID` and `showSpace:` to `ClairBrowser` and remove `tabs`; replace `tabsDidChange:` and `tabDidChange:` on `ClairWindow` with `shownSpaceDidChange:from:`. Document each as the header documents the rest. Verify that the header compiles in `ClairHostObjCxxTests.mm` in CI.
- [x] 1.2 Update `FakeHost` and `FakeBrowser` to the new contract: ordered Spaces, a tab list per Space with each tab's `browserID`, the shown Space following the active tab (D3), and the came-from rule of D4, so `ClairUI` logic can be tested without an engine. Verify with new cases in `FakeBrowserTests` in CI: a new tab joins the shown Space; closing follows came-from, above, below; closing a Space's last tab shows another Space.
- [x] 1.3 Add `SpacesModel` (D10) fed by the host's observer, and make `BrowserWindowModel` and `BrowserWindowController` read rows from it for the shown Space, filtered to the window's `browserID`. Keep every existing sidebar behaviour with one Space. Verify that the existing `ClairUI` unit tests pass in CI, adapted to the fakes, with no test deleted.

## 2. Engine

- [x] 2.1 Add `clair::RegisterLocalStatePrefs` to `clair_window_hooks`, registering `clair.spaces` and `clair.last_space`, and call it from `RegisterLocalState` in `browser_prefs.cc` through `patches/clair/native-window-hook.patch` (D1). Verify that `./build.sh fetch prepare` applies the patch in CI's patch check.
- [x] 2.2 Add `overlay/chrome/browser/clair/clair_space_store.{h,mm}` (D1): load, validate and save `clair.spaces`; create "Home" when empty; create, rename, set icon, reorder and delete (refused for the only Space); notify observers. Wire its calls and snapshots into `ClairChromiumHost` in `clair_native_layer.mm`, and add the files to `BUILD.gn` through the patch. Verify by the engine build in 2.9 and the runtime tests in 3.11.
- [x] 2.3 Add `overlay/chrome/browser/clair/clair_space_tabs.{h,mm}` (D2): one per regular profile, observing every native browser's tab strip of that profile; the Space tag as `WebContents` user data; the ordered list per Space with the three placement rules; reordering within the list; and the coalesced pushes of D9. Move the tab snapshot code from `clair_browser_bridge.mm` here, and fill `spaceID` and `browserID`. Verify by the engine build and the runtime tests in 3.11.
- [x] 2.4 Give each `ClairBrowserWindow` a shown Space with `showSpace:`, and keep D3's invariant: the shown Space follows the active tab; showing a Space activates the tab last active in it here, or opens a new tab page with the command bar; a new browser shows the active browser's Space or `clair.last_space`. New tabs join the shown Space; a Peek joins its parent's. Verify with the runtime tests in 3.11.
- [x] 2.5 Implement the came-from slot and choose the next tab before a close Clair starts (D4), in `closeTab:` and `IDC_CLOSE_TAB`; and implement `moveTab:toSpace:`, `moveSpace:toIndex:` and `deleteSpace:` (D7). Verify with the runtime tests in 3.11, which replay `arc-reference.md`'s close sequences.
- [x] 2.6 Run the tab commands D5 lists over the window's rows of the shown Space in `ExecuteCommand` in `clair_native_window.mm`, keeping the existing handling of Peeks, and make `closeTabsBelowTab:` and `moveTab:toIndex:` use the Space's list. Add `patches/clair/space-shortcuts.patch` (D8) with a header explaining it as `copy-url-shortcut.patch`'s does, and add it to `patches/series`. Verify that the patch check applies it, and with the runtime tests in 3.11: Cmd+number, Next and Previous Tab wrapping within the Space, and Close Tabs Below.
- [x] 2.7 Add `overlay/chrome/browser/clair/window/clair_space_session.{h,mm}` and `patches/clair/space-session.patch` (D6): write `clair_space` and `clair_order` when they change and in the session file's rebuild, add them for Reopen Closed Tab and Window, and read them in `CreateRestoredTab`. Add the patch to `patches/series` after `peek-session.patch`. Verify that the patch check applies it, and with the runtime tests in 3.11 that relaunch and that restore a closed tab.
- [x] 2.8 Restore tabs at launch by default (D11): set the default of `session.restore_on_startup` in `clair::RegisterProfilePrefOverrides`. Remove `--restore-last-session` from the runtime tests that relaunch, so they prove the default. Don't change which windows Chromium reopens or which tabs each holds; that is left to `share-tabs-across-windows`. Verify with the runtime tests in 3.11: a fresh data folder restores its tabs after a relaunch with no setting changed; and "Open the New Tab page" in `chrome://settings/onStartup` still opens one new tab page.
- [x] 2.9 Build the engine with `gh workflow run engine.yml -f ref=<branch>`. Verify that `chromium-engine-<key>` is published and CI's engine check passes.
- [x] 2.10 Update `docs/native-window.md` with the Space store, the per-profile tab lists and the shown-Space invariant, and where each lives. Verify that every file and decision it names exists.

## 3. ClairUI

- [x] 3.1 Add `SpaceHeaderView.swift`: the icon and name above the tab list, its context menu (Change Space Icon…, Rename Space…, Manage Spaces…, Delete Space), inline renaming with "Done", and no header in incognito and guest windows. Verify with unit tests of its menu's enabled states (Delete Space with one Space) in CI, and by hand against Arc for the header's size and place.
- [x] 3.2 Add `SpaceSwitcher.swift` to `SidebarFooter`, as in Arc: 36×34 pt items, an icon or a dot, the current one darker, absent with one Space; dragging an item reorders Spaces through `moveSpace:toIndex:`; and add New Space… to the plus menu. Give each item an accessibility identifier. Verify with unit tests of the items for one, two and ten Spaces in CI, and by hand against Arc.
- [x] 3.3 Add `SpaceIconField.swift` (D10): the one-emoji field that opens macOS's emoji picker, used in the header for Change Space Icon… and in the New Space form. Verify with unit tests of a pure helper in CI (the first emoji of mixed text is kept, including one with a skin tone or joined sequence; text with no emoji changes nothing; empty clears), and by hand that the picker opens and its choice lands in the header and the switcher.
- [x] 3.4 Make the sidebar's content between the URL field and the footer a pager, and slide on `shownSpaceDidChange:from:` (D10), with no slide under Reduce Motion. Verify by hand with 60 fps recordings of Clair and Arc side by side on real hardware, and record the tuned curve in `design.md`.
- [x] 3.5 Add `NewSpaceForm.swift`, replacing the header and list as in Arc: the name field with the icon button, "Create Space" disabled until named, Cancel and Esc. Verify with unit tests of the form's state in CI, and by hand against Arc.
- [x] 3.6 Add `SpacesMenu.swift` and install it after View (D8): New Space…, Rename Space, Manage Spaces…, Next Space (Opt+Cmd+Right), Previous Space (Opt+Cmd+Left) and one item per Space with Ctrl+1…9 for the first nine, rebuilt when Spaces change. Verify with unit tests in a new `SpacesMenuTests` (items, shortcuts, the checkmark, wrapping at the ends, the order after a reorder) in CI.
- [x] 3.7 Add the confirmation for Delete Space on a Space with tabs as a `ClairDialog`, worded for Clair (its tabs will close). Verify with unit tests that an empty Space skips it, in CI.
- [x] 3.8 Add "Move to Space ›" to a tab row's context menu in `SidebarView.swift`, listing every other Space and absent with one Space. Verify with unit tests of the menu's items in CI.
- [x] 3.9 Add `ManageSpacesDialog.swift` (D10) and wire "Manage Spaces…" in the Spaces menu and the Space header's menu. Verify with unit tests of its state in CI (the opening selection, Add's defaults, Remove's enabled state, an emptied name reverting).
- [x] 3.10 Check the whole flow by hand against Arc with `tests/probe/`: the form, the header, the switcher with two and five Spaces, and the slide. Verify by the owner accepting the comparison.
- [x] 3.11 Add runtime tests to `tests/runtime/`, using a local page with a counter:
  - First launch has one Space, "Home", and no switcher.
  - Creating a Space from the plus menu and from the Spaces menu; Esc cancels.
  - Switching by switcher, Ctrl+number and Opt+Cmd+arrows, wrapping at the ends; the window's frame is unchanged.
  - Switching to a Space with no tabs opens a new tab page with the command bar; Cmd+N opens on the same Space.
  - A new tab joins the shown Space; Cmd+number and Next Tab stay within it.
  - Rename, icon and Delete Space (with and without tabs).
  - Move to Space keeps the page's counter, and the window stays on its Space.
  - Manage Spaces: rename, add and remove from the dialog, each showing in the sidebar at once.
  - The close sequences of `arc-reference.md`, and closing a Space's last tab.
  - Quit and relaunch, with no setting changed and no launch switch: Spaces, each Space's tabs in order, and the shown Space come back. Restore Last Closed Tab returns a tab to its Space.

  Reordering Spaces by dragging, in the switcher and in Manage Spaces, has no runtime test: XCUITest's drags move neither on hosted runners, and the runner may not post real mouse events. Check both by hand with a real drag (`tests/probe/tools/drag.swift`); the drop slot and the order after a move have unit tests.

  Verify with a `quality.yml` run on the branch.

## 4. Release notes and integration

- [x] 4.1 Add a Changie fragment (`changie new`, kind New) for Spaces. Verify that it's in the PR.
- [x] 4.2 Run `openspec validate --all --strict` and the merge gate, and start `quality.yml` on the branch with the last push. Verify that CI and the quality checks pass.
