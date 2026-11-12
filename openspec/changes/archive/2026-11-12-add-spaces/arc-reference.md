# Arc reference: Spaces and Profiles

Observed on 2026-11-11 in Arc on macOS, in a 960×976 pt window on a 1920×1080 display, with the probe in `tests/probe/` (accessibility frames, screenshots and one 60 fps recording). It ran in a virtual machine, so timings are approximate. Frames are in screen points; the window's origin was (0, 30). It adds to `arc-reference/look-and-behaviour.md` in the archived `ship-plain-ungoogled-build` change.

## Storage

- A Space stores its profile as Chromium's profile directory name: `{"default": true}` or `{"custom": {"directoryBasename": "Profile 1"}}`.
- A profile's name lives only in Chromium's `Local State` (`profile.info_cache`).
- A Space's icon is `customInfo.iconType`, such as `{"icon": "planet"}`; a Space without one stores nothing.
- Favorites are stored per profile.

## Sidebar

| Element | Observed |
|---|---|
| Space header | Icon 26×26 at x 13, name from x 41 (from x 13 without an icon), 18 pt high, at y 234. A "More" button appears at the trailing edge on hover. |
| Footer switcher | One 36×34 item per Space, centred in a 144×50 strip between the leading button and the plus. An item is the Space's icon, or a dot when it has none; the current Space's is darker. The switcher is absent with one Space. |
| Plus menu | A 222×308 popover above the plus, items 194×40: New Space, New Folder, New Easel, New Boost, New Split, New Tab ⌘T. The plus becomes a × while it is open. |

## Switching Spaces

- Clicking a footer item slides everything between the URL field and the footer sideways, like pages. The top row, URL field, footer and page card stay put.
- A Space to the left comes in from the left.
- About 300 ms in all: roughly 80% of the distance in the first 100 ms, then it settles.
- Favorites slide too when the two Spaces use different profiles.

## New Space

- The sidebar pages sideways to an inline form; the page card empties.
- Illustration, "Create a Space", "Separate your tabs for life, work, projects, and more."
- Name field (placeholder "Space name…", focused) with an icon button at its leading end, at y 275.
- "Profile" row, 200×36 at (14, 309), with a popup showing the profile's name and an (i).
- "Choose a Theme" row, 200×36 at (14, 353).
- "Create Space", 200×36 at (14, 874), accent-filled and disabled until a name is typed; "Cancel" below it.
- The footer shows the existing Spaces plus a dot for the new one, and hides its two buttons.
- The profile popup is a native menu: each profile with a checkmark on the chosen one, a separator, "New Profile…".
- After Create Space the window shows the new, empty Space.

## Icon picker

- A popover from the icon, with a segmented control: Emoji and Icon.
- Emoji: a search field, a 7-column grid and a category bar.
- Icon: a fixed 8×7 grid of 56 glyphs, including star, bookmark, heart, flag, bolt, bell, lightbulb, folder, calendar, envelope, book, people, terminal, tools, moon, sun, planet, leaf, cloud, paw, basket, gift, bed, fork and knife, dumbbell, plane, music note, palette, video, code, map, flame, skull, thumbs up and tram.
- From the Space header's menu, the header shows a dashed square where the icon goes while the picker is open.

## Space header menu

Change Space Icon… · Rename Space… · Edit Theme Color… · Set Profile › · — · New Folder · Live Folders › · — · Share Space… · Export "…" into Folder › · — · Manage Spaces… · — · Delete Space

- **Rename Space…** turns the name into an inline field with its text selected; "Done" replaces the More button.
- **Set Profile ›** lists the profiles with a checkmark on the Space's, a separator, then "New Profile…".
  - On a Space with no tabs it applies at once.
  - On a Space with tabs it asks first: "Switch to your **Work** Profile?", "Each Profile has different browser data, so your **Temp** Space might look a little different! For example, you might get logged out of some websites, see different Favorites up top, or need to re-install an extension. This action cannot be undone.", Cancel (Esc) and "Switch it up" (Return). The tabs then reload in the new profile, in the same order.
- **Delete Space**
  - On a Space with no tabs it deletes at once, moves the window to the neighbouring Space and shows the toast "Space deleted! Use ⌘Z to undo."
  - On a Space with tabs it asks first: "Delete your "Temp" Space?", "This will archive all the tabs and folders inside it.", Cancel (Esc) and Delete (Return).

## Profile sheets

Each is a sheet centred on its window, with Cancel (Esc) and a default button (Return).

| Sheet | Text |
|---|---|
| New profile (450×426) | "Create a new Profile", "Profiles make your Spaces truly separate — with their own history, saved passwords, extensions, and other browsing data. No more flipping between work and personal accounts!", "What do you want to call this Profile?", a field (placeholder "Personal"), "Profiles are **not synced** between computers.", "Create Profile" (disabled until a name is typed) |
| Rename (496×255) | "Rename your Profile", "This won't affect the names of any of the Spaces associated with this Profile.", a field holding the name, selected, "Save" |
| Delete | "Delete this Profile", "Deleting **Work** will permanently remove any cookies, history, preferences, and logins that belong to this Profile. To continue, please type the name of this Profile:", a field (placeholder: the name), "Delete" (disabled until the name is typed) |

## Settings › Profiles

The window is 701×650 on this pane.

- Help text across the top: "Profiles help keep your data separate across Spaces — like history, logins, cookies, and extensions. You can use any Profile across one or more Spaces." and a "Learn more." link.
- Left card, 205 wide: the header "Your Profiles", then one 40 pt row per profile with its name and, at the trailing end, "1 Space" or "2 Spaces" (nothing for a profile with none). Below the list: Add (+), Remove (−) and Rename buttons.
- Remove is enabled only for a profile with no Spaces.
- Right, for the selected profile: a card with Search engine (popup), Manage search ("Search Settings…") and Include search engine suggestions (switch); a card with Archive tabs after, New documents and Download location (popup showing the folder); then "Your Data and Settings" and a card of rows, each with a coloured icon and a trailing arrow: Privacy and Security, Passwords, Credit Cards, Notifications, Clear Browsing Data.

## Tabs across windows

- Every window lists the same tabs for a Space.
- A new window shows the same Space with no tab selected.
- Selecting, in window B, the tab window A shows moves the live page to B. A keeps the row selected and shows a dimmed still of the page, taken at that moment; its URL field empties and its back, forward and reload buttons disable.
- Focusing A, by a click anywhere in it, moves the live page back to A and leaves the still in B.
- Closing a tab that another window is dimmed on leaves that window with no tab selected.

## Which tab becomes active after a close

In order:

1. The tab the user selected the closed tab from, if it still exists.
2. Otherwise the row above.
3. Otherwise the row below.

It remembers one step: after a close lands on a tab, the next close uses the row above. A tab that another window is showing isn't skipped; it is taken, and that window dims.
