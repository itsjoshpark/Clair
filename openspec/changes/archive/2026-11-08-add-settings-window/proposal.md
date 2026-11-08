# Proposal

## Why

Settings… (Cmd+,) still opens Chromium's `chrome://settings` in a tab, so Clair has nowhere native for its own preferences. "Allow window dragging from the top of webpages", added by `drag-window-from-page-top`, can only be turned off with `defaults write` today, and the coming MVP features (Peek, Spaces and profiles) each bring toggles of their own. Arc's Settings window is a native window with a toolbar of pages, and people moving from Arc expect the same before Arc stops working on 2026-12-22.

## What Changes

- **Settings… opens Clair's own Settings window** instead of a `chrome://settings` tab. `ClairUI` takes over Chromium's existing app-menu item (`IDC_OPTIONS`), as it does for About Clair, and titles it "Settings…", as Arc does. Cmd+, stays its shortcut. There is one Settings item, and one Settings window, which comes to the front when chosen again.
- **The window has Arc's shape:** a toolbar of pages, each with its rows in System Settings-style grouped cards, and the selected page's name as the window's title. It reopens on the page last shown. The first version has two pages:
  - **General:** a Default Browser row that says whether Clair is the default web browser and offers "Make Default", which asks macOS to change it.
  - **Advanced:** the "Allow window dragging from the top of webpages" toggle for the existing preference, and a "More Settings…" button that opens `chrome://settings` in a browser tab, as Arc's Advanced page does.
- `chrome://settings` itself is unchanged and stays reachable through "More Settings…" and by URL.

**Out of scope:**
- Chromium's own preferences (search engine, download location, startup and session restore, warn before quitting). They are per profile and belong with the Spaces and profiles work, which settles which profile a native setting applies to.
- Pages for features that don't exist yet: Links (Peek), Profiles, Shortcuts. Each feature adds its page or rows when it lands.
- Update settings, which `software-updates` rules out.
- Arc's account, Max and Icon pages.

## Capabilities

### New Capabilities

- `settings-window`: Clair's native Settings window: how Settings… opens it, its pages and their rows, and the hand-off to `chrome://settings` for Chromium's own settings.

### Modified Capabilities

None. The window-dragging preference in `browser-window` keeps its behavior; this change only gives it a control.

## Impact

- **Native layer only:** a Settings window controller, its pages and the menu takeover in `native/ClairUI/`, started from `NativeLayer` next to About. No `ClairHost.h` change and no patch, so the engine key is unchanged and no engine build is needed.
- **Tests:** a few unit tests in `native/ClairUITests/` (menu takeover, a single reused window, More Settings… opening `chrome://settings`), and the existing runtime test of the Clair menu extended to check that there is exactly one Settings… item and that it opens the native window, not a `chrome://settings` tab. The rest is checked by hand.
- **Users:** a user-facing change, so a Changie fragment.
