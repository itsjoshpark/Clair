# Proposal

## Why

Arc users separate work, personal and project browsing with Spaces, and keep their logins apart with Profiles. Both are on the MVP list in `ship-plain-ungoogled-build`'s roadmap ("Spaces many-to-one with profiles"). Today Clair has one unnamed tab list per window, and its only profile UI is Chromium's Profiles menu, which opens Chromium-style profile windows that don't fit Clair. Arc stops working on 2026-12-22.

## What Changes

- **Spaces.** A Space is a named set of tabs with an optional emoji icon and one profile. The sidebar shows the current Space's name above its tabs, and a switcher in the footer moves between Spaces with Arc's sideways slide. Spaces are created from the footer's plus menu or the Spaces menu, in an inline form in the sidebar, and renamed, given an icon, moved to another profile or deleted from the Space's own menu, and reordered by dragging in the switcher. A tab's menu moves it to another Space.
- **Profiles.** A profile is a Chromium profile: its own cookies, history, logins, extensions, permissions and downloads. Several Spaces can use one profile. Switching to a Space of another profile happens in the same window, with no visible window change.
- **One sidebar for all windows, as in Arc.** Every window lists the tabs of the Space it shows, whichever window they were opened in. Clicking a tab that another window is showing brings it here; the other window keeps a dimmed still of the page until it is focused again. Closing a window keeps its tabs while another window is open.
- **Arc's choice of the next tab.** Closing the active tab returns to the tab the user came from, or else to the row above, or else the row below.
- **Manage Spaces.** A dialog lists every Space, to add, rename, reorder and delete Spaces and to change a Space's icon and profile in one place.
- **Clair's own dialogs.** Dialogs become cards with Clair's own content and styling, attached to their window as Arc's are, with Esc and Return shown on their buttons. They replace macOS's standard alerts, whose look can't be changed much. Every dialog this change adds uses them, and the extension install, remove and permission prompts move over.
- **A Spaces menu** in the menu bar: New Space…, Rename Space, Change Profile, Manage Spaces…, Next Space (Opt+Cmd+Right), Previous Space (Opt+Cmd+Left) and Space 1–9 (Ctrl+1…9). Next and Previous Tab move to Opt+Cmd+Down and Opt+Cmd+Up, as decided in `clair-menus.md`.
- **No Profiles menu.** Chromium's Profiles menu leaves the menu bar, and Chromium's profile picker never shows at launch.
- **A Profiles page in Settings,** between General and Links, laid out as Arc's: the help text, then "Your Profiles" on the left with Add, Remove and Rename at the bottom, and the selected profile's settings on the right: Download location (a folder, or asking every time), then Search Engine, Privacy and Security, Notifications and Clear Browsing Data, which each open Chromium's page for that profile.
- **BREAKING (`ClairHost.h`):** the host gains profiles, Spaces and their observers; `ClairTab` gains its Space and the window that holds it; `ClairBrowser` gains the shown Space and the still of a tab it gave away, and tab lists come from the host, per Space, in place of each window's own.

**Out of scope:**
- The two-finger swipe between Spaces. The footer switcher, menu and shortcuts animate.
- Glyph icons for Spaces, such as a grid of SF Symbols like Arc's "Icon" tab. Icons are emoji, chosen with macOS's own emoji picker; glyphs are a possible later addition.
- Arc's Library, including its Space manager. Manage Spaces… opens Clair's own, simpler dialog.
- Moving the update prompts to the new dialogs. They show without a window and the updater waits on their answer, so they need their own change.
- Space themes, dragging a tab onto another Space, and undoing Delete Space.
- Pinned tabs, favorites and folders, which will be per Space or per profile when they exist.
- Arc's per-profile search suggestions, "Archive tabs after" and "New documents" settings.
- Syncing Spaces or profiles.

## Capabilities

### New Capabilities

- `spaces`: what a Space is, how Spaces are created, switched, edited and deleted, how tabs belong to a Space and are shared between windows, and how Spaces come back after a relaunch.
- `dialogs`: Clair's own dialogs: how they look, attach to and block their window, and handle keys, focus and accessibility.
- `profiles`: what a profile isolates, the Profiles page in Settings and its actions, and the absence of Chromium's own profile UI.

### Modified Capabilities

- `sidebar`:
  - "Tab list" lists the tabs of the Space the window shows, from every window.
  - "Sidebar footer" gains the Space switcher, and its plus menu gains New Space….
- `settings-window`: "Settings pages" adds Profiles between General and Links.
- `extensions`: "Install confirmation as a native sheet" and "Remove confirmation as a native sheet" ask in a Clair dialog, where they named macOS's alert.
- `chromium-engine`:
  - "Browser behavior as in ungoogled-chromium outside Clair's interface" excepts Spaces and profiles.
  - "What Clair's Chromium hooks may do" allows hooks that register Clair's preferences, tag Clair's tabs in saved sessions and free shortcuts Clair reassigns.

## Impact

- **`native/ClairHost.h`** changes, so the engine key changes and the engine is rebuilt once.
- **Overlay** (`overlay/chrome/browser/clair/`): new files for profiles, the Space store, the per-profile tab lists, window groups and session tags; changes to the bridge, the browser window, the native window's command handling and the menu set-up.
- **Patches:** two hooks added to `native-window-hook.patch`'s files, a session-tag patch beside `peek-session.patch`, and a shortcut patch beside `copy-url-shortcut.patch`.
- **`ClairUI`:** new Space views, the Spaces menu and the Profiles page; changes to the sidebar, the window model and controller, and Settings.
- **Tests:** `FakeHost` and `FakeBrowser` follow the contract; new unit tests and runtime tests. The runtime suite's existing sidebar tests must keep passing with one Space.
- **Chromium behaviour:** a window group holds one hidden browser window per extra profile, which extensions see as a window through `chrome.windows`.
