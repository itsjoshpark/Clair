# Proposal

## Why

Arc users keep their work and personal logins apart with Profiles, and give each Space one. They are on the MVP list in `ship-plain-ungoogled-build`'s roadmap ("Spaces many-to-one with profiles"). Today Clair's only profile UI is Chromium's Profiles menu, which opens Chromium-style profile windows that don't fit Clair, and after `add-spaces` every Space still shares one profile. Arc stops working on 2026-12-22.

This is the last of the changes proposed together in #130. `add-clair-dialogs`, `add-spaces` (#138) and `share-tabs-across-windows` (#140, #142) have landed, and this change builds on them as built.

## What Changes

- **Each Space uses a profile.** A profile is a Chromium profile: its own cookies, history, logins, extensions, permissions and downloads. Several Spaces can use one profile.
- **Switching profile in the same window.** Switching to a Space of another profile looks like any other switch: same window, same frame, same slide, including in full screen.
- **Choosing and changing a Space's profile.** The New Space form and Manage Spaces gain a profile popup with "New Profile…", and the Space header's menu gains Set Profile and the Spaces menu Change Profile, as in Arc. Changing the profile of a Space with tabs asks first, then reloads its tabs in the new profile.
- **Move to Space across profiles** opens the tab's URL in the other profile.
- **Move to Space follows the active tab.** Moving the active tab switches the window to its new Space; moving any other tab leaves the window alone and shows the notice "Tab was moved to …". Today the window always stays.
- **Settings opens on General** each time, no longer on the page last shown.
- **No Profiles menu.** Chromium's Profiles menu leaves the menu bar, and Chromium's profile picker never shows at launch.
- **A Profiles page in Settings,** between General and Links, laid out as Arc's: the help text, then "Your Profiles" on the left with Add, Remove and Rename at the bottom, and the selected profile's settings on the right: Download location (a folder, or asking every time), then Search Engine, Privacy and Security, Notifications and Clear Browsing Data, which each open Chromium's page for that profile.
- **Removing a profile follows Arc:** only a profile that no Space uses can be removed, after typing its name.
- **An empty Space stays, as in Arc.** Closing a Space's last tab leaves the window on that Space with a new tab page, where today it shows a tab of another Space. A window never leaves its Space, or its profile, because a tab closed.
- **Restoring windows becomes a setting, as in Arc:** the toggle "When opening Clair, restore windows from previous session" on Settings › Advanced, off by default. Off, Clair opens one window on the Space last shown; on, each window comes back on its Space and tab. Tabs come back in their Spaces either way. Today every window comes back.
- **"Warn before quitting" moves to Settings › Advanced,** as a toggle, and Chromium's menu item for it goes.
- **BREAKING (`ClairHost.h`):** the host gains profiles, their observer and their calls, a Space gains its profile, and the host gains the warn-before-quitting setting.

**Out of scope:**
- Arc's per-profile search suggestions, "Archive tabs after" and "New documents" settings.
- Favorites per profile, which don't exist yet.
- Syncing profiles.

## Capabilities

### New Capabilities

- `profiles`: what a profile isolates, how a Space uses one and changes it, switching between profiles in one window, the Profiles page in Settings and its actions, and the absence of Chromium's own profile UI.

### Modified Capabilities

- `spaces`: the header's menu, the New Space form and Manage Spaces gain the profile; "Moving a tab to another Space" keeps the page only within a profile, follows the active tab and shows a notice for any other; "Tab chosen after a close" keeps the window on an emptied Space; "Spaces restored after a relaunch" no longer depends on which windows come back.
- `browser-window`: adds "Windows restored at launch", and "Window size and placement restored" follows it.
- `settings-window`: "Settings pages" is replaced by "Pages of the Settings window", which adds Profiles between General and Links and drops the remembered page, and the Advanced page gains the restore-windows and "Warn before quitting" toggles.
- `chromium-engine`: "Browser behavior as in ungoogled-chromium outside Clair's interface" excepts profile management.

## Impact

- **Builds on `add-spaces`, `share-tabs-across-windows` and `add-clair-dialogs`,** all merged. `design.md` is revised against them as built and includes a prototype of the full-screen switch.
- **`native/ClairHost.h`** changes, so the engine key changes and the engine is rebuilt once.
- **Overlay:** new files for profiles and window groups; changes to the Space store, the tab lists, the browser window, session tags and the menu set-up.
- **`ClairUI`:** the Profiles page and profile dialogs; the profile popup in the form and Manage Spaces; Set Profile and Change Profile in the menus; the two Advanced toggles.
- **Chromium behaviour:** a window holds one hidden browser window per extra profile, which extensions see as a window through `chrome.windows`.
