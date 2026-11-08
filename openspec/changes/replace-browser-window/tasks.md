# Tasks

Tasks marked **(owner)** need the owner: judging the window against Arc by eye, or having the self-hosted Mac online for an engine build.

Wherever a verification below needs a running app, it means a `quality.yml` run dispatched on the branch (`gh workflow run quality.yml --ref <branch>`) against the engine published for the branch's key, unless it says "by hand", which means a check through D15's local loop. Engine builds go through `engine.yml` as `CLAUDE.md` describes; check that the runner is online first. Chromium's source can be read, never written, in the runner's workspace (design, Context).

Runtime tests cover the fundamentals only (D14). A less-used feature is checked by hand once, and fixed when it's later found broken.

Suggested order: 1, 2, 3 (one engine build with the whole contract), then 4, 5 and 6 in `ClairUI` against that engine, then 7 and 8.

## 1. Local edit-to-run loop

- [x] 1.1 Add `scripts/run-local.sh` (D15): download and cache `chromium-engine-<key>` for the checkout, checking its SHA-256; build `ClairUI`; package ad hoc with `package.sh --no-dmg`; launch with a throwaway `--user-data-dir` and `--use-mock-keychain`, passing through any extra arguments. Add `scripts/run-local.test.sh`. Verify that the test covers a cache hit, a changed key, a key with no published engine (fails and prints the `engine.yml` command), and a profile directory outside `~/Library/Application Support/Clair`, and that `shellcheck -S warning` passes.
- [x] 1.2 Document the loop in `docs/building.md`. Update `CLAUDE.md` as D15 says: remove the "Local work is limited to…" sentence, keep the rule against fetching or building Chromium, allow running the runtime suite locally with a note that it deletes the current user's Clair data, and ask before adding external packages to the development machine. Verify by running the documented command on `main` and seeing Clair open a window with a throwaway profile, with no new "Clair Safe Storage" keychain item and `~/Library/Application Support/Clair` unchanged.

## 2. The window contract

- [x] 2.1 Extend `native/ClairHost.h` with D3's protocols: `ClairBrowser`, `ClairTab`, `ClairWindow`, `ClairAutocomplete` and the entry point's `+windowForBrowser:`, with value types for suggestions, downloads, extension actions, infobars, find results, anchors, indicators and the docked DevTools layout. Document every member in the header as the existing ones are. Verify that `ClairUI` and `ClairUITests` build, and that `ClairHostObjCxxTests.mm` compiles the header as Objective-C++.
- [x] 2.2 Add `FakeBrowser` and fake value objects to `native/ClairUITests/` implementing the new protocols, with helpers to add, change, move and close tabs and to post suggestions. Verify with a unit test that a `FakeBrowser` change reaches a `ClairWindow` test double through the same calls Chromium will make.
- [x] 2.3 Add `+windowForBrowser:` to `ClairUI`'s entry point (D2), returning a window for every browser. Verify with a unit test that it returns a configured window for a `FakeBrowser` of each profile kind.

## 3. Engine: overlay and hooks

- [x] 3.1 Add `overlay/chrome/browser/clair/window/` with:
  - `ClairBrowserWindow` and its helpers (D1), and `ClairNativeWindow` (D4).
  - The Objective-C bridges for `ClairBrowser` and `ClairTab`, with coalesced change notifications (D3).
  - Find, status, infobars and the modal dialog host (D8), the exclusive-access context (D6), and the docked DevTools host (D5).
  - The extensions container and download observer (D7), and the autocomplete session without bookmarks (D11).
  - New-tab placement (D12), and D10's menu changes (Bookmarks menu hidden, Save Page As on Shift+Cmd+S).
  - The password and autofill overrides (D17), and the unavailable `BrowserWindow` methods, each logging once (D9).
  - In `clair::StartNativeLayer`, the alert and quit when `ClairUI` is present but fails to load, and a `CHECK` on a nil window (D2).

  Add `patches/clair/native-window-hook.patch` with D13's hunks, each with its reason in the patch header, after checking each hook site in the runner's source tree, and add the overlay's sources to `BUILD.gn`. Credit Crest and Mori in `CREDITS.md` and in the headers of files adapted from them. Verify with `./build.sh fetch prepare`, through the patch check, that the patch applies without fuzz.
- [x] 3.2 Add the smallest `ClairUI` window that exercises the contract: the styled `NSWindow`, the card holding the active page, and an unstyled tab list. Verify by hand that a page renders in the card, that switching tabs swaps the page, and that closing the window runs a page's `beforeunload` prompt.
- [x] 3.3 **(owner)** Build the engine for the branch with `engine.yml`. Verify that the run publishes `chromium-engine-<key>`, that its headless smoke test passes in Chromium's own window (the bare engine has no `ClairUI`), and that the PR's engine check passes.
- [x] 3.4 Check every row of D9's table by hand on the packaged app. For each row that crashes or misbehaves, add a hook as D13 describes, rebuild, and re-check. Update D9's table and D13's hook list to match. Verify that no row is left unchecked and that the final engine passes the smoke test.

## 4. The window

- [x] 4.1 Build the window's layout and appearance (D4): no title bar, traffic lights in the sidebar, one vibrancy material, the inset card with rounded corners and shadow, the inactive look, and the incognito appearance. Add runtime tests for "Normal browser windows are native" (launch, restore, incognito, a `window.open` pop-up in Chromium's window) and "Window layout" (control and card positions from the accessibility tree). Verify that both pass in `quality.yml` on the branch.
- [x] 4.2 Host the page (D5): live resize, visibility on tab switch, focus on activation, and the window's bounds and state for session restore. Add runtime tests for "Page shown in the card" (`visibilityState` on switching, viewport size after resize) and "Window size and placement restored" (two windows of different sizes across a relaunch). Verify that they pass, and that the existing relaunch and idle-install tests still pass.
- [x] 4.3 Add docked DevTools (D5): DevTools in the card on its dock side, per-tab DevTools across tab switches, and undocking to Chromium's window and back. Add a runtime test that Opt+Cmd+I opens DevTools inside the card with the page's viewport narrowed, and that undocking restores the page's width. Verify that it passes, and check the bottom and left dock sides and tab switching by hand.
- [x] 4.4 Add full screen (D6), with the native capsule in place of the exclusive-access bubble. Add a runtime test for page full screen filling the screen and ending with Esc. Verify that it passes, and check window full screen keeping the sidebar state by hand.
- [x] 4.5 Add the native find field (D8), the status capsule and infobars (D8), and the crashed-page view (D5). Verify by hand: "1 of 3", Cmd+G and Esc on a find page; a link hover; the extension-debugging infobar and its cancel button; and `chrome://crash` followed by Reload.
- [x] 4.6 Add toasts (D8), including zoom changes. Add a runtime test that Copy Image from the page's context menu shows Chromium's toast in the card. Verify that it passes.
- [x] 4.7 Check tab-modal dialogs and file pickers in the native window (D9). Verify by hand that a JavaScript alert shows over the card and that an `<input type=file>` opens a panel.
- [x] 4.8 Finish D10's menu changes and the unavailable features (D9). Verify by hand: no Bookmarks menu; Cmd+D, Shift+Cmd+B and Shift+Cmd+A do nothing; `new EyeDropper().open()` rejects with Clair still running; and `chrome://bookmarks` opens from the command bar.
- [x] 4.9 Turn passwords and autofill off (D17). Verify by hand on a profile that has saved passwords and an address: submitting a local sign-in form offers no save prompt, an address field shows no suggestions, `chrome://settings` has no "Autofill and passwords" section, and `chrome://password-manager` still lists the saved passwords.

## 5. The sidebar

- [x] 5.1 Build the top row and URL field (D4, D7): hide-sidebar, back, forward, reload/stop with their states, the host or full-URL display, the placeholder, and the copy button. Add unit tests for the display rules (host, `chrome://`, file URLs, new tab page) and a runtime test for going back and forward. Verify that they pass.
- [x] 5.2 Add site controls and indicators (D7), with Chromium's page info and permission prompt anchored to them and to the fallback corner. Add unit tests for the anchor and its fallback in each sidebar state, and runtime tests for a notifications permission prompt with the sidebar shown (Allow) and hidden (Block). Verify that they pass and that each prompt sits fully on screen.
- [x] 5.3 Add extension actions (D7): pinned buttons with badges, the extensions button and its list, and native popovers hosting popups. Add `tests/runtime/extensions/` with a test extension that has a popup and sets a badge, and a runtime test for opening its popup from a pinned button. Verify that it passes. Check the badge, the list, and installing the test extension as a CRX (the modified `chromium-engine` scenario) by hand.
- [x] 5.4 Add the downloads button and list (D7). Add a download to `server.py` and a runtime test that the button appears with progress and that opening a finished download clears its mark. Verify that it passes, and that the existing download-blocks-idle-install test still passes.
- [x] 5.5 Build the tab list and new-tab placement (D12): rows, the active pill, hover close button, the speaker, scrolling, the "New Tab" row, drag to reorder, middle-click, and the context menu with Copy Link, Duplicate, Mute or Unmute, Close Tab and Close Tabs Below. Add unit tests for ordering, insertion and Close Tabs Below, and runtime tests for selecting, closing, a Cmd-clicked link opening at the top, and reordering followed by Cmd+1. Verify that they pass, and check muting and Close Tabs Below by hand.
- [x] 5.6 Add hiding, hover reveal and resizing (D12), with View > Hide Sidebar on Cmd+S and Save Page As on Shift+Cmd+S. Add runtime tests for Cmd+S twice, Cmd+S opening no save panel while Shift+Cmd+S does, and the hover reveal leaving the page's size unchanged. Verify that they pass, and check by hand that a new window gets the last width.

## 6. The command bar

- [x] 6.1 Build the command bar's panel and keyboard handling (D11): position and sizing, the field and rows, selection, Return, Shift+Return, Cmd+Return and Esc, and the highlighted "New Tab" row. Add unit tests against `FakeBrowser` suggestions for each key and for both modes. Verify that they pass.
- [x] 6.2 Connect it to the autocomplete session: Cmd+T and the "New Tab" row, Cmd+L and the URL field, "Switch to Tab", the empty-query list, keyword mode and incognito. Add runtime tests for typing a URL with Cmd+T (the tab opens at the top), Esc creating no tab, Cmd+L navigating the current tab, and switching to an open tab. Verify that they pass. Check a history match, a search, the empty-query list, a site search keyword (ungoogled-chromium has no `wiki` keyword; its default engines have keywords such as `bing.com`), no bookmark suggestions, and incognito suggestions staying out of regular history by hand.

## 7. Rollout

- [x] 7.1 Verify by hand that a packaged Clair whose `ClairUI` binary is damaged shows the alert and quits without opening a window, and that the bare engine still opens Chromium's window in the engine smoke test.
- [x] 7.2 Add a Changie fragment describing the new window, what moved into the sidebar and the command bar, Save Page As on Shift+Cmd+S, and what's gone: bookmarks UI, password saving and autofill (with how to export saved passwords), and the unavailable features. Add `docs/native-window.md`: the architecture (D1–D3), where each piece lives, and how to add a hook. Add a native-window pass in Light and Dark Mode to `docs/releasing.md`'s checklist. Verify that the pull request includes all three.
- [x] 7.3 Run the full quality checks on the branch, then on `main` after merging. Verify that every runtime test passes in both runs, including every item in the modified `build-pipeline` spec's native window coverage.

## 8. Spike measurements

- [x] 8.1 **(owner)** Fill in design.md's Measurements section (D16): compare the window with Arc side by side while Arc still runs, time a one-line `ClairUI` change through D15's loop and through a push and `quality.yml`, and record D9's final table with what moved and why. Verify that every item in D16 has a result, and that each "worse" result has a follow-up issue. Closed by the owner on 2026-11-07: the polish passes of groups 9 to 11 compared the window with Arc instead and fixed what was worse (design, Measurements).

## 9. Polish from the owner's pass

Fixes from the owner's side-by-side pass against Arc (D18), all in `ClairUI`. Arc's numbers below were measured with the XCUITest probe on 2026-11-07.

- [x] 9.1 Sidebar motion (D12, D18): reveal the hidden sidebar after 100 ms (Arc: 100–117 ms) on a quicker spring for the floating sidebar (Arc slides in within about 100 ms, with a slight overshoot); keep the card inset 10 pt on every edge with the sidebar hidden (D4; Arc's is 10 pt); and make showing a revealed sidebar dock it in place, with only the card moving, instead of sliding it out and back in. Add unit tests for the hidden layout and for docking from a reveal, and update the runtime layout tests for the new inset. Verify that they pass, and check the reveal and docking against Arc by hand.
- [x] 9.2 Move the window by dragging the sidebar's empty areas, as in Arc (D18): the top row's background, the gaps around the URL field and the space below the last tab, in the docked and the revealed sidebar. Verify by hand that those drag the window, and that clicks on the controls, tab rows and the URL field, and dragging tabs to reorder them, still work.
- [x] 9.3 Tab rows (D12, D18): draw the favicon at 16 pt in its 18 pt frame (Arc's); make the close button 26 pt square, 5 pt from the pill's trailing edge, with a 10 pt glyph and a hover background (Arc's); and open the row's context menu from AppKit so the list draws no selection ring around a right-clicked row. Verify by hand against Arc, and that the context menu's items, middle-click and the runtime tests that close and reorder tabs still work.
- [x] 9.4 Top row and URL field (D18): Arc-style tooltips drawn by the sidebar, since AppKit's never show in Chromium's window, with Arc's delay, wording and shortcut key caps ("Hide sidebar", "Lock sidebar" while revealed, "Go back", "Go forward", "Reload this page", "Stop loading this page", "Copy URL", "Site Control Center"); fade the URL field's buttons in and out and every hover background in the sidebar; a darker hover background on the URL field (Arc's is about 4% darker than its resting field); and no indicator for a blocked permission, which page info still shows. Verify by hand that each tooltip appears and that the fades run in Light and Dark Mode.
- [x] 9.5 Inactive window (D4, D18): dim the top row's and the URL field's glyphs, and lighten the active tab's pill, while the window isn't key. Verify by hand against Arc in Light and Dark Mode.
- [x] 9.6 Incognito (D12): use the `eye.slash` symbol in the "Incognito" header and as the incognito new tab's icon. Verify by hand, and that the incognito runtime test still finds the header.
- [x] 9.7 Command bar (D11, D18): keep the field still while results appear or change; the panel grows downwards only. Verify by hand with Cmd+L and Cmd+T, typing until results appear and deleting back to an empty field.
- [x] 9.8 Link status (D8, D18): show the capsule once the pointer has rested on links for about 0.5 s and hide it about 0.5 s after it leaves them, fading both ways; moving between links while it shows updates it at once. Add unit tests for the timing rules against a fake clock. Verify that they pass, and check by hand.
- [x] 9.9 Run the full quality checks on the branch. Verify that every runtime test passes.

## 10. Second polish pass

More fixes from the owner's pass (D18), all in `ClairUI`. Arc's figures were measured with the probe on 2026-11-07.

- [x] 10.1 New windows (D18): open the command bar when a window first shows a single new tab page, as Arc does, and close it if the page navigates without it. Verify by hand with Cmd+N and Shift+Cmd+N that typing goes straight into the field, and that the runtime tests still pass.
- [x] 10.2 Colours and weights (D18): Arc's flat URL field fill in Light and Dark Mode, Arc's near-black sidebar and a lighter active tab in Dark Mode and incognito, Arc's incognito badge, and medium-weight glyphs in the top row and the URL field. Verify by hand against Arc in a normal and an incognito window.
- [x] 10.3 Tooltips everywhere (D18): draw them in a tooltip window of their own, with the shadow on the capsule only and flat key caps; give every control that had a system tooltip Clair's, with the tab's close button reading "Close tab ⌘W", Copy URL "⇧⌘C", the compact row's menu "More options" with a hover state, and a tab's full title after 3 s on its row; the innermost control under the pointer owns the tooltip. Verify by hand, including in an extension or downloads popover and in full screen.
- [x] 10.4 Copy URL (D18): Edit > Copy URL on Shift+Cmd+C after Copy, running Chromium's command; `copy-url-shortcut.patch` drops Shift+Cmd+C from Chromium's own table, where it inspects an element; and Copy URL in the URL field's context menu. Verify that the patch check applies the patch and `engine.yml` builds the engine for the branch's key, then by hand that the menu item, the shortcut and the context menu copy the URL, and that Opt+Cmd+C still inspects.
- [x] 10.5 The URL field (D18): show its buttons while the pointer is over the key window's sidebar, and the host without a leading `www.`. Add unit tests for the `www.` rule. Verify that they pass, and check the buttons by hand.
- [x] 10.6 Hidden sidebar (D18): reveal from anywhere in the 10 pt leading inset, with a less translucent revealed sidebar. Verify by hand.
- [x] 10.7 Full screen (D18): keep the top row at Arc's y+8 with hide-sidebar 13 pt in. Verify by hand against Arc.
- [x] 10.8 Investigate the sidebar changing colour for about 2 s when the pointer moves over the tabs in full screen. Verify by finding and fixing the cause, or, if it can't be reproduced, record what was tried in D18 and open an issue.
- [x] 10.9 Run the full quality checks on the branch. Verify that every runtime test passes.

## 11. Third polish pass

More fixes from the owner's pass (D18). Arc's figures were measured with the probe on 2026-11-07.

- [ ] 11.1 "Copied Current URL" (D18): Arc's popup in the card's top-trailing corner, with its spring in and out, its timing and a share button, for Edit > Copy URL, Shift+Cmd+C, the URL field's copy button and its context menu; page full screen's notice in the same popup with Esc as a key cap. Verify by hand against Arc, and that the full-screen runtime test still finds the notice.
- [ ] 11.2 Tooltips (D18): key-cap depth, a softer and wider shadow, tighter sides with the keys sitting evenly at the end, a tab's title after 2 s, and no tooltip after a click or a right click until the pointer leaves the control. Verify by hand against Arc, including a tab's context menu.
- [ ] 11.3 Command bar border (D18): Arc's crisp mid-grey hairline. Verify by measuring the edge against Arc's.
- [ ] 11.4 Clearing history (D13, D18): the clear-browsing-data hook. Verify that the patch check applies it and `engine.yml` builds the engine for the branch's key, then by hand that deleting all history from `chrome://settings/clearBrowserData` and from `chrome://history` leaves Clair running.
- [ ] 11.5 The tab's speaker (D18): between the favicon and the title with even 10 pt gaps (a row without it keeps its gap), Arc's outline symbols in medium weight changing with a quicker SF Symbols replace effect, growing and fading in and out with the sound, Arc's size and grey, a hover background, and "Mute this tab" or "Unmute this tab". Add a runtime test of the row's layout from its accessibility frames: the favicon's inset and size, the favicon-to-title gap, and the speaker's gaps while the tab plays sound (D12, D18). Verify that it passes in `quality.yml`, and by hand with a tab playing sound, muted, unmuted and falling silent.
- [ ] 11.6 Run the full quality checks on the branch. Verify that every runtime test passes.

## Workflow follow-up

- Run a `release.yml` dry run and the updated release checklist on its DMG before the first release that ships the native window.
- Archive this change after that release.
