# Proposal

## Why

Arc users separate work, personal and project browsing with Spaces. They are on the MVP list in `ship-plain-ungoogled-build`'s roadmap, and today Clair has one unnamed tab list per window. Arc stops working on 2026-12-22.

This is the first of three changes that bring Arc's Spaces and Profiles: `share-tabs-across-windows` then gives every window one tab list per Space, and `add-profiles` gives each Space a profile. Spaces come first because they are useful on their own, and the other two build on what this change puts in place.

## What Changes

- **Spaces.** A Space is a named set of tabs with an optional emoji icon. The sidebar shows the current Space's name above its tabs, and a switcher in the footer moves between Spaces with Arc's sideways slide.
- **Creating and editing.** Spaces are created from the footer's plus menu or the Spaces menu, in an inline form in the sidebar. A Space is renamed, given an icon or deleted from its own menu, and reordered by dragging in the switcher. The icon comes from macOS's emoji picker.
- **Manage Spaces.** A dialog lists every Space, to add, rename, reorder and delete Spaces and change their icons in one place.
- **Tabs belong to a Space.** A new tab joins the Space its window shows. A tab's menu moves it to another Space, keeping its page.
- **Arc's choice of the next tab.** Closing the active tab returns to the tab the user came from, or else to the row above, or else the row below.
- **A Spaces menu** in the menu bar: New Space…, Rename Space, Manage Spaces…, Next Space (Opt+Cmd+Right), Previous Space (Opt+Cmd+Left) and Space 1–9 (Ctrl+1…9). Next and Previous Tab move to Opt+Cmd+Down and Opt+Cmd+Up, as decided in `clair-menus.md`.
- **Tabs come back at launch.** Clair reopens the tabs that were open when it quit, as Arc does; today that needs a Chromium setting changed. They come back in one window, each in its Space and its place. Reopening the windows themselves is a separate matter and isn't part of this.
- **BREAKING (`ClairHost.h`):** the host gains Spaces, their tab lists and an observer; `ClairTab` gains its Space and the window that holds it; `ClairBrowser` gains the shown Space; and tab lists come from the host, per Space, in place of each window's own.

**Out of scope:**
- One tab list shared by every window, the dimmed still, and keeping a closed window's tabs: `share-tabs-across-windows`. Until then, a window lists only its own tabs of the Space.
- Profiles, Set Profile and the Profiles page in Settings: `add-profiles`. Until then, every Space uses the one profile.
- The two-finger swipe between Spaces. The footer switcher, menu and shortcuts animate.
- Glyph icons for Spaces, such as a grid of SF Symbols like Arc's "Icon" tab. Glyphs are a possible later addition.
- Arc's Library, including its Space manager. Manage Spaces… opens Clair's own, simpler dialog.
- Space themes, dragging a tab onto another Space, and undoing Delete Space.
- Reopening every window at launch, as Arc's "restore windows from the previous session" setting does.
- Closing old tabs automatically, as Arc's "Archive tabs after" does. With tabs now restored at every launch, that is a likely later change.
- Pinned tabs, favorites and folders.

## Capabilities

### New Capabilities

- `spaces`: what a Space is, how Spaces are created, switched, edited, reordered and deleted, how tabs belong to a Space, and how Spaces come back after a relaunch.

### Modified Capabilities

- `sidebar`:
  - "Tab list" lists the window's tabs of the Space it shows.
  - "Sidebar footer" gains the Space switcher, and its plus menu gains New Space….
- `browser-window`: adds restoring tabs at launch by default, into one window, and "Window size and placement restored" restores that one window.
- `chromium-engine`:
  - "Browser behavior as in ungoogled-chromium outside Clair's interface" excepts Spaces and the "On startup" default.
  - "What Clair's Chromium hooks may do" allows hooks that register Clair's preferences, tag Clair's tabs in saved sessions, free shortcuts Clair reassigns and restore the previous session's tabs into one window by default.

## Impact

- **Depends on `add-clair-dialogs`** for the Delete Space confirmation and Manage Spaces.
- **`native/ClairHost.h`** changes, so the engine key changes and the engine is rebuilt once.
- **Overlay** (`overlay/chrome/browser/clair/`): new files for the Space store, the tab lists and session tags; changes to the bridge, the browser window and the native window's command handling.
- **Patches:** one hook added to `native-window-hook.patch`'s `browser_prefs.cc`, a session-tag patch beside `peek-session.patch`, and a shortcut patch beside `copy-url-shortcut.patch`.
- **`ClairUI`:** new Space views, the Spaces menu and Manage Spaces; changes to the sidebar and the window model and controller.
- **Tests:** `FakeHost` and `FakeBrowser` follow the contract; new unit and runtime tests. The runtime suite's existing sidebar tests must keep passing with one Space.
