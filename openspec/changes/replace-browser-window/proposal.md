# Proposal

## Why

Clair still shows Chromium's own browser window: a tab strip, a top toolbar and an omnibox. Every MVP feature (the vertical sidebar, pinned tabs and favorites, Spaces, split view, Peek) is drawn by `ClairUI` in a native window, so that window has to exist before any of them can be built. This change is roadmap step 2 of `ship-plain-ungoogled-build`, the UX spike, and it ships: once it merges, released builds open only the native window. Arc stops working on 2026-12-22, so the window needs to be in use well before the MVP to find what breaks.

## What Changes

- **BREAKING (user-facing):** a normal browser window, incognito included, is a native AppKit/SwiftUI window drawn by `ClairUI` in Arc's layout, instead of Chromium's window. Chromium's tab strip, toolbar, omnibox and bookmarks bar are gone.
  - The whole window is one vibrancy material. The page sits in a rounded, shadowed card inset from the window edges, and the traffic lights sit in the sidebar.
  - The **sidebar** holds what Chromium's toolbar held: back, forward and reload/stop; a URL field that shows the host; site controls with the permission and capture indicators; extension actions; and a downloads indicator. Below them is a "New Tab" row and a flat, reorderable tab list. Every new tab, including one opened from a link, goes to the top of the list, as in Arc.
  - **Cmd+S** and a sidebar button hide the sidebar with a spring animation, and resting the pointer on the window's left edge reveals it as a floating overlay. The sidebar is resizable.
  - **Cmd+T** and **Cmd+L** open a floating command bar built on Chromium's `AutocompleteController`. It is the only place to type a URL or a search: Cmd+T opens the choice in a new tab, and Cmd+L opens on the current URL and navigates the current tab.
  - Native replacements for Chromium UI that lived in its window: find in page (Cmd+F), the link-hover status pill, infobars, toasts, the crashed-page view, and a downloads popover.
  - **DevTools docks in the card** beside the page by default, on the side DevTools' own dock setting names. Undocked, it opens in Chromium's DevTools window.
  - Chromium's own bubbles that remain, such as permission prompts, page info and extension popups, attach to their controls in the sidebar, or to the page's top-leading corner when the sidebar is hidden or the window is in full screen.
  - Chromium features the native window doesn't host are unavailable rather than broken: their menu items are hidden, and invoking them through a shortcut or API does nothing harmful. Examples are side panels, tab search, Chrome Labs, the EyeDropper, tab groups UI and the app and profile menus.
- **BREAKING (user-facing): no bookmarks in the interface.** Arc has none. The Bookmarks menu, the bookmarks bar, the bookmark star and their shortcuts go, and the command bar doesn't suggest bookmarks. Bookmark data stays in the profile, and `chrome://bookmarks` still opens when typed.
- **BREAKING (user-facing): passwords and autofill are turned off.** Users are expected to use a dedicated password manager. Clair doesn't offer to save passwords and doesn't fill passwords, addresses or payment methods, and the "Autofill and passwords" settings section is hidden. Passwords saved earlier stay at `chrome://password-manager`, so they can be exported.
- Pop-up, app, Picture-in-Picture and undocked DevTools windows keep Chromium's own windows.
- **Packaged Clair never shows Chromium's browser window.** There is no setting to bring it back. If `ClairUI` fails to load, Clair says so and quits. Only a bare engine without `ClairUI`, which CI's smoke test runs and which never ships, opens Chromium's window.
- Menus stay Chromium's apart from what the window needs: "Hide Sidebar" (Cmd+S) in the View menu, "Save Page As…" moved to Shift+Cmd+S as in Arc, Cmd+T and Cmd+L opening the command bar, and the hidden items above. The full menu bar of `arc-reference/clair-menus.md` belongs to the MVP.
- `ClairHost.h` grows from the updater contract into the window contract: Chromium hands each browser window's tabs, page views, DevTools, navigation state, autocomplete and downloads to `ClairUI`, and `ClairUI` hands back the window, anchors and commands.
- New engine hooks, kept to one call each into new overlay files, in the style of Crest's `native-host.patch`: the browser window factory, new-tab placement, docked DevTools, toasts, the crashed page, bubble anchors, download UI, and the password and autofill defaults.
- The quality checks' runtime suite gains tests for the native window's fundamentals, and the spike's measurements are recorded: how native it feels against Arc, the edit-to-run time for a `ClairUI` change, and which Chromium features needed native replacements.
- A local edit-to-run loop: a script that packages the current `ClairUI` against the published engine for the checkout and launches it with a throwaway profile. It never fetches or builds Chromium. `CLAUDE.md` drops its "local work is limited to…" rule, which dates from development in a resource-constrained VM.

**Out of scope:** Spaces and the two-finger swipe between them, favorites, pinned tabs and folders, split view, Peek, Arc's full menu bar and shortcuts, the sidebar update banners, native replacements for the remaining Chromium bubbles, and themes (all MVP or later).

## Capabilities

### New Capabilities
- `browser-window`: the native browser window, covering which windows are native, the window's layout and appearance, hosting the page and docked DevTools, full screen, native find, status, infobars, toasts and the crashed page, how Chromium's remaining bubbles, dialogs and windows are placed, the removed bookmarks UI, and what is unavailable.
- `sidebar`: the window's sidebar, covering the toolbar controls it carries (navigation, URL field, site controls and indicators, extension actions, downloads), the tab list and where new tabs go, and hiding, revealing and resizing the sidebar. The MVP's favorites, pinned tabs, folders and Spaces will extend it.
- `command-bar`: the floating command bar for opening URLs, searching and switching tabs, built on Chromium's autocomplete.

### Modified Capabilities
- `native-layer`: the native layer now provides the browser window as well as the updater, and the `ClairHost.h` contract covers windows, tabs, page views, DevTools, autocomplete and downloads. A packaged app whose framework fails to load quits instead of falling back.
- `chromium-engine`: "No browser behavior changes beyond identity and updates", "Changes to Chromium limited to hooks and identity" and "ungoogled-chromium privacy defaults preserved" change, since Clair now replaces Chromium's window through hooks and turns off passwords and autofill. An extension's action shows in the sidebar instead of a toolbar.
- `build-pipeline`: the runtime suite's required coverage adds the native window.

## Impact

- **Engine:** a new engine for the changed `ClairHost.h`, the new overlay files under `overlay/chrome/browser/clair/` and the new hook patch in `patches/clair/`. The engine-key PR follows the usual flow: build the engine first, then push docs.
- **Native layer:** most of the work. New window, sidebar, command bar, find, downloads and toast code in `native/ClairUI/`, and unit tests of their logic against a fake host in `native/ClairUITests/`.
- **Tests:** `tests/runtime/` gains tests for the window's fundamentals (XCUITest for the window, DevTools Protocol for page state), and existing tests that drive Chromium's tab strip or omnibox move to the sidebar and the command bar. Less-used features are checked by hand and fixed when found broken.
- **Users:** every window looks and behaves differently after the update. Bookmarks, saved passwords and autofill disappear from the UI, along with the unavailable features above. Session restore, profiles, history, extensions and the remaining settings keep working. A Changie fragment describes the new window and what's gone.
- **Docs:** `CLAUDE.md` loses the local-work limit and allows running the runtime suite locally, which deletes the current user's Clair data.
- **Licensing:** code adapted from Crest stays MPL-2.0, and from Mori (through Crest) MIT, credited in `CREDITS.md` as change 1's D8 requires.
