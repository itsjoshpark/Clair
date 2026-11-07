# Tasks

Tasks marked **(owner)** need the owner: judging the window against Arc by eye, or having the self-hosted Mac online for an engine build.

Wherever a verification below needs a running app, it means a `quality.yml` run dispatched on the branch (`gh workflow run quality.yml --ref <branch>`) against the engine published for the branch's key, unless it says "by hand", which means a check through D15's local loop. Engine builds go through `engine.yml` as `CLAUDE.md` describes; check that the runner is online first. Chromium's source can be read, never written, in the runner's workspace (design, Context).

Runtime tests cover the fundamentals only (D14). A less-used feature is checked by hand once, and fixed when it's later found broken.

Suggested order: 1, 2, 3 (one engine build with the whole contract), then 4, 5 and 6 in `ClairUI` against that engine, then 7 and 8.

## 1. Local edit-to-run loop

- [x] 1.1 Add `scripts/run-local.sh` (D15): download and cache `chromium-engine-<key>` for the checkout, checking its SHA-256; build `ClairUI`; package ad hoc with `package.sh --no-dmg`; launch with a throwaway `--user-data-dir` and `--use-mock-keychain`, passing through any extra arguments. Add `scripts/run-local.test.sh`. Verify that the test covers a cache hit, a changed key, a key with no published engine (fails and prints the `engine.yml` command), and a profile directory outside `~/Library/Application Support/Clair`, and that `shellcheck -S warning` passes.
- [x] 1.2 Document the loop in `docs/building.md`. Update `CLAUDE.md` as D15 says: remove the "Local work is limited to…" sentence, keep the rule against fetching or building Chromium, allow running the runtime suite locally with a note that it deletes the current user's Clair data, and ask before adding external packages to the development machine. Verify by running the documented command on `main` and seeing Clair open a window with a throwaway profile, with no new "Clair Safe Storage" keychain item and `~/Library/Application Support/Clair` unchanged.

## 2. The window contract

- [ ] 2.1 Extend `native/ClairHost.h` with D3's protocols: `ClairBrowser`, `ClairTab`, `ClairWindow`, `ClairAutocomplete` and the entry point's `+windowForBrowser:`, with value types for suggestions, downloads, extension actions, infobars, find results, anchors, indicators and the docked DevTools layout. Document every member in the header as the existing ones are. Verify that `ClairUI` and `ClairUITests` build, and that `ClairHostObjCxxTests.mm` compiles the header as Objective-C++.
- [ ] 2.2 Add `FakeBrowser` and fake value objects to `native/ClairUITests/` implementing the new protocols, with helpers to add, change, move and close tabs and to post suggestions. Verify with a unit test that a `FakeBrowser` change reaches a `ClairWindow` test double through the same calls Chromium will make.
- [ ] 2.3 Add `+windowForBrowser:` to `ClairUI`'s entry point (D2), returning a window for every browser. Verify with a unit test that it returns a configured window for a `FakeBrowser` of each profile kind.

## 3. Engine: overlay and hooks

- [ ] 3.1 Add `overlay/chrome/browser/clair/window/` with:
  - `ClairBrowserWindow` and its helpers (D1), and `ClairNativeWindow` (D4).
  - The Objective-C bridges for `ClairBrowser` and `ClairTab`, with coalesced change notifications (D3).
  - Find, status, infobars and the modal dialog host (D8), the exclusive-access context (D6), and the docked DevTools host (D5).
  - The extensions container and download observer (D7), and the autocomplete session without bookmarks (D11).
  - New-tab placement (D12), and D10's menu changes (Bookmarks menu hidden, Save Page As on Shift+Cmd+S).
  - The password and autofill overrides (D17), and the unavailable `BrowserWindow` methods, each logging once (D9).
  - In `clair::StartNativeLayer`, the alert and quit when `ClairUI` is present but fails to load, and a `CHECK` on a nil window (D2).

  Add `patches/clair/native-window-hook.patch` with D13's hunks, each with its reason in the patch header, after checking each hook site in the runner's source tree, and add the overlay's sources to `BUILD.gn`. Credit Crest and Mori in `CREDITS.md` and in the headers of files adapted from them. Verify with `./build.sh fetch prepare`, through the patch check, that the patch applies without fuzz.
- [ ] 3.2 Add the smallest `ClairUI` window that exercises the contract: the styled `NSWindow`, the card holding the active page, and an unstyled tab list. Verify by hand that a page renders in the card, that switching tabs swaps the page, and that closing the window runs a page's `beforeunload` prompt.
- [ ] 3.3 **(owner)** Build the engine for the branch with `engine.yml`. Verify that the run publishes `chromium-engine-<key>`, that its headless smoke test passes in Chromium's own window (the bare engine has no `ClairUI`), and that the PR's engine check passes.
- [ ] 3.4 Check every row of D9's table by hand on the packaged app. For each row that crashes or misbehaves, add a hook as D13 describes, rebuild, and re-check. Update D9's table and D13's hook list to match. Verify that no row is left unchecked and that the final engine passes the smoke test.

## 4. The window

- [ ] 4.1 Build the window's layout and appearance (D4): no title bar, traffic lights in the sidebar, one vibrancy material, the inset card with rounded corners and shadow, the inactive look, and the incognito appearance. Add runtime tests for "Normal browser windows are native" (launch, restore, incognito, a `window.open` pop-up in Chromium's window) and "Window layout" (control and card positions from the accessibility tree). Verify that both pass in `quality.yml` on the branch.
- [ ] 4.2 Host the page (D5): live resize, visibility on tab switch, focus on activation, and the window's bounds and state for session restore. Add runtime tests for "Page shown in the card" (`visibilityState` on switching, viewport size after resize) and "Window size and placement restored" (two windows of different sizes across a relaunch). Verify that they pass, and that the existing relaunch and idle-install tests still pass.
- [ ] 4.3 Add docked DevTools (D5): DevTools in the card on its dock side, per-tab DevTools across tab switches, and undocking to Chromium's window and back. Add a runtime test that Opt+Cmd+I opens DevTools inside the card with the page's viewport narrowed, and that undocking restores the page's width. Verify that it passes, and check the bottom and left dock sides and tab switching by hand.
- [ ] 4.4 Add full screen (D6), with the native capsule in place of the exclusive-access bubble. Add a runtime test for page full screen filling the screen and ending with Esc. Verify that it passes, and check window full screen keeping the sidebar state by hand.
- [ ] 4.5 Add the native find field (D8), the status capsule and infobars (D8), and the crashed-page view (D5). Verify by hand: "1 of 3", Cmd+G and Esc on a find page; a link hover; the extension-debugging infobar and its cancel button; and `chrome://crash` followed by Reload.
- [ ] 4.6 Add toasts (D8), including zoom changes. Add a runtime test that Copy Image from the page's context menu shows Chromium's toast in the card. Verify that it passes.
- [ ] 4.7 Check tab-modal dialogs and file pickers in the native window (D9). Verify by hand that a JavaScript alert shows over the card and that an `<input type=file>` opens a panel.
- [ ] 4.8 Finish D10's menu changes and the unavailable features (D9). Verify by hand: no Bookmarks menu; Cmd+D, Shift+Cmd+B and Shift+Cmd+A do nothing; `new EyeDropper().open()` rejects with Clair still running; and `chrome://bookmarks` opens from the command bar.
- [ ] 4.9 Turn passwords and autofill off (D17). Verify by hand on a profile that has saved passwords and an address: submitting a local sign-in form offers no save prompt, an address field shows no suggestions, `chrome://settings` has no "Autofill and passwords" section, and `chrome://password-manager` still lists the saved passwords.

## 5. The sidebar

- [ ] 5.1 Build the top row and URL field (D4, D7): hide-sidebar, back, forward, reload/stop with their states, the host or full-URL display, the placeholder, and the copy button. Add unit tests for the display rules (host, `chrome://`, file URLs, new tab page) and a runtime test for going back and forward. Verify that they pass.
- [ ] 5.2 Add site controls and indicators (D7), with Chromium's page info and permission prompt anchored to them and to the fallback corner. Add unit tests for the anchor and its fallback in each sidebar state, and runtime tests for a notifications permission prompt with the sidebar shown (Allow) and hidden (Block). Verify that they pass and that each prompt sits fully on screen.
- [ ] 5.3 Add extension actions (D7): pinned buttons with badges, the extensions button and its list, and native popovers hosting popups. Add `tests/runtime/extensions/` with a test extension that has a popup and sets a badge, and a runtime test for opening its popup from a pinned button. Verify that it passes. Check the badge, the list, and installing the test extension as a CRX (the modified `chromium-engine` scenario) by hand.
- [ ] 5.4 Add the downloads button and list (D7). Add a download to `server.py` and a runtime test that the button appears with progress and that opening a finished download clears its mark. Verify that it passes, and that the existing download-blocks-idle-install test still passes.
- [ ] 5.5 Build the tab list and new-tab placement (D12): rows, the active pill, hover close button, the speaker, scrolling, the "New Tab" row, drag to reorder, middle-click, and the context menu with Copy Link, Duplicate, Mute or Unmute, Close Tab and Close Tabs Below. Add unit tests for ordering, insertion and Close Tabs Below, and runtime tests for selecting, closing, a Cmd-clicked link opening at the top, and reordering followed by Cmd+1. Verify that they pass, and check muting and Close Tabs Below by hand.
- [ ] 5.6 Add hiding, hover reveal and resizing (D12), with View > Hide Sidebar on Cmd+S and Save Page As on Shift+Cmd+S. Add runtime tests for Cmd+S twice, Cmd+S opening no save panel while Shift+Cmd+S does, and the hover reveal leaving the page's size unchanged. Verify that they pass, and check by hand that a new window gets the last width.

## 6. The command bar

- [ ] 6.1 Build the command bar's panel and keyboard handling (D11): position and sizing, the field and rows, selection, Return, Shift+Return, Cmd+Return and Esc, and the highlighted "New Tab" row. Add unit tests against `FakeBrowser` suggestions for each key and for both modes. Verify that they pass.
- [ ] 6.2 Connect it to the autocomplete session: Cmd+T and the "New Tab" row, Cmd+L and the URL field, "Switch to Tab", the empty-query list, keyword mode and incognito. Add runtime tests for typing a URL with Cmd+T (the tab opens at the top), Esc creating no tab, Cmd+L navigating the current tab, and switching to an open tab. Verify that they pass. Check a history match, a search, the empty-query list, a `wiki` keyword search, no bookmark suggestions, and incognito suggestions staying out of regular history by hand.

## 7. Rollout

- [ ] 7.1 Verify by hand that a packaged Clair whose `ClairUI` binary is damaged shows the alert and quits without opening a window, and that the bare engine still opens Chromium's window in the engine smoke test.
- [ ] 7.2 Add a Changie fragment describing the new window, what moved into the sidebar and the command bar, Save Page As on Shift+Cmd+S, and what's gone: bookmarks UI, password saving and autofill (with how to export saved passwords), and the unavailable features. Add `docs/native-window.md`: the architecture (D1–D3), where each piece lives, and how to add a hook. Add a native-window pass in Light and Dark Mode to `docs/releasing.md`'s checklist. Verify that the pull request includes all three.
- [ ] 7.3 Run the full quality checks on the branch, then on `main` after merging. Verify that every runtime test passes in both runs, including every item in the modified `build-pipeline` spec's native window coverage.

## 8. Spike measurements

- [ ] 8.1 **(owner)** Fill in design.md's Measurements section (D16): compare the window with Arc side by side while Arc still runs, time a one-line `ClairUI` change through D15's loop and through a push and `quality.yml`, and record D9's final table with what moved and why. Verify that every item in D16 has a result, and that each "worse" result has a follow-up issue.

## Workflow follow-up

- Run a `release.yml` dry run and the updated release checklist on its DMG before the first release that ships the native window.
- Archive this change after that release.
