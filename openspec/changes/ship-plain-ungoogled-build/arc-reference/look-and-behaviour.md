# Arc: look and behaviour

Observed on 2026-10-27 in Arc 1.170.0 (macOS, 1920×1080 pt display, light appearance, default Space theme). Keyboard-driven states were scripted with AppleScript and System Events, and mouse-driven states (menus, hovers, drags) were performed by hand. Sizes come from the accessibility tree and images from `screencapture`. All sizes are in points. The profile was close to new: one Space, the "Arc Basics" folder, and a Google favorite.

This complements `menus-and-shortcuts.md` (menus and keys) and `feature-strings.md` (UI strings). Those say *what* exists; this file records what it looks like and what it does when used. Screenshots are in `screenshots/`. How the app is built is recorded from Dia, Arc's successor, in `dia-architecture.md`.

## Method limits

- Arc rejects synthetic mouse clicks, and its SwiftUI rows ignore `AXPress` and `AXShowMenu`. Context menus, hovers, folders, drag-and-drop and the hidden-sidebar reveal were therefore performed by hand and recorded at about 2 frames per second.
- Keyboard input, menu-bar items, AppKit buttons (the Settings toolbar) and Arc's AppleScript dictionary (`select` a tab, `make new tab`) worked for the scripted parts.
- Animations were seen only as single frames, so timings and curves are not recorded.

## Window anatomy

![Window](screenshots/window.jpg)

```
+-------------------------------------------------------------------+
| (o)(o)(o) [sb]  <-  ->  (R) |                                     |  y=7..39  toolbar row (in sidebar)
| [ news.ycombinator.com    ] |                                     |  URL field, ~24 pt text row
| [         (G)             ] |                                     |  favorites grid, tile 212x47
|  (icon) Space 1        ...  |         web content card            |  Space header, 26 pt icon
|  [] Arc Basics              |         (rounded, shadowed,         |  pinned section
|  -------------------------  |          10 pt inset top/right/     |  divider
|  +  New Tab                 |          bottom)                    |  "New Tab" row
|  [Y] Hacker News   <active> |                                     |  Today (unpinned) tabs,
|  [O] GitHub - ungoogled-... |                                     |  newest first
|  [W] Web browser            |                                     |
|                             |                                     |
| [lib]   ( space dots )  [+] |                                     |  bottom bar, 32 pt buttons
+-------------------------------------------------------------------+
  <---------- 228 ---------->  <-------------- 722 --------------->
```

Measurements (window at x=960, y=30, 960×976):

| Element | Frame | Notes |
|---|---|---|
| Sidebar | width 228 | Stored per window (`StorableWindows.json`: `sidebarWidth: 228`, `sidebarMode: "anchored"`) |
| Traffic lights | 16×16 at x+12/35/58, y+16 | Sit inside the sidebar; no title bar |
| Sidebar toggle, back, forward, reload | 32×32 buttons at x+77, +122, +156, +190; y+7 | Same row as traffic lights. Back and forward dim when unavailable |
| URL field | text at x+20..216, y+55, height ~32 | Shows **host only** (`news.ycombinator.com`). Placeholder "Search or Enter URL…" with a magnifier when the tab is empty |
| Favorites | section y+82, tile 212×47 inset 8 | One favorite fills the full row width. Tile is a rounded, tinted rectangle with the favicon centred |
| Space header | icon 26×26 at x+13, y+150; title at x+41 | "More" button at the right edge |
| Sidebar rows | 40 tall on a 41 pitch, full 228 width | Favicon 18×18 at x+17; title from x+43 |
| Pinned/Today divider | 17 tall row with a hairline | Between pinned items and the "New Tab" row |
| Bottom bar | y+935..976 | Library/archive button 32×32 at x+8; Space switcher strip 144×50 in the middle; "+" (new Space) 32×32 at x+188 |
| Web content | x+228, y+10, 722×956 | 10 pt margin on top, right and bottom; none on the sidebar side. Rounded corners with a soft shadow |

Visual style:

- The sidebar and window background are one continuous Space-theme gradient (default: lavender-blue, lighter towards the bottom). The window has no visible chrome except the content card.
- The active tab is a white, slightly translucent rounded pill with a soft shadow, inset ~8 pt from the sidebar edges. Other rows have no background.
- Tab titles truncate with an ellipsis at the sidebar edge.
- New Today tabs go to the **top** of the list, directly under "New Tab".
- Link hover shows a URL pill at the bottom-left of the content card (Chromium's status bubble, restyled as a rounded capsule).
- When the window is not key, the active tab's pill fades to a faint tint without a shadow.

![Window not focused](screenshots/window-inactive.jpg)

## Hover states

![Tab hover](screenshots/tab-hover-tooltip.jpg)

- **Today tab:** a light translucent pill appears behind the row, and a close **×** appears at the right. After a moment a tooltip shows the full page title and "Double-click to rename".
- **Pinned tab** (inside a folder): the same pill, but the button at the right is **−** instead of ×. Closing a pinned tab keeps it pinned.
- **Divider:** hovering the sidebar shows a small grey **Clear** button at the right end of the pinned/Today divider (Clear Today). It reads "↓ Clear" with an arrow while Today has tabs.
- **Space header:** a collapse chevron (˅) appears to the left of the Space name (collapses the pinned section).
- **URL field:** shows two icon buttons at its right end: copy link, and site controls. With the sidebar revealed over a hidden layout (see below), the second icon is share.

## Context menus

Menus use the standard macOS menu style (translucent, rounded, separators).

| Target | Items |
|---|---|
| Today tab | Copy Link (⇧⌘C) · Share › · — · Change Icon… · Rename… · Mute (disabled when silent) · Customize Page… · — · Add Split View · Duplicate · Move to › · — · Archive Tab · Archive Tabs Below |
| Favorite | Copy Link · Share › · — · Change Icon… · Rename… · Mute · Customize Page… · Edit Pinned Page › · — · Open in Split View · Duplicate · Move to › · — · Remove Favorite |
| Folder | Share Folder… · — · New Nested Folder… · Turn "Arc Basics" into Space · Copy All Links · — · Change Icon… · Rename… · — · Duplicate · Move to › · — · Delete |
| Space header | Change Space Icon… · Rename Space… · Edit Theme Color… · Set Profile › · — · New Folder · Live Folders › · — · Share Space… · — · Manage Spaces… · — · Delete Space |
| URL field | Copy URL · Share › · Capture… · Capture Full Page · — · Show as Toolbar · Enable Shared Quotes |

- Right-clicking a folder also opens a **search popover** next to the menu ("Search Arc Basics…", listing the folder's items), so you can find an item inside the folder.

![Tab menu](screenshots/menu-tab.jpg)
![Folder menu](screenshots/menu-folder.jpg)
![Favorite menu](screenshots/menu-favorite.jpg)
![Space header menu](screenshots/menu-space-header.jpg)
![URL field menu](screenshots/menu-url-field.jpg)

## Folders

![Folder expanded](screenshots/folder-expanded-hover.jpg)

- A click toggles the folder. When it is open, the folder icon is drawn open, and its children are indented one level (~16 pt) under it.
- Expanded state is stored per window (`expandedItems` in `StorableWindows.json`).

## Drag and drop

- **Lifting a row:** a floating copy of the row (white pill with a shadow) follows the cursor, and the original stays in place until the drop.

![Row lifted](screenshots/drag-row-lifted.jpg)

- **Into a folder:** while hovering over an open folder, the folder's contents area is highlighted with an accent-tinted band. On drop the tab becomes the folder's first child (now pinned) and stays selected.

![Into folder](screenshots/drag-into-folder.jpg)
![Dropped in folder](screenshots/drag-into-folder-dropped.jpg)

- **Into favorites:** over the favorites area the dragged row shrinks towards a tile, and the existing tiles shrink to make room. After the drop, two favorites share the row as two half-width tiles.

![To favorites](screenshots/drag-to-favorites.jpg)
![Two favorites](screenshots/favorites-two.jpg)

- **Onto the page to make a split:** see Split view.

## Favorites

![Favorite selected](screenshots/favorite-selected.jpg)

- Favorites are per profile (`topApps` container keyed by profile in `StorableSidebar.json`) and appear above the Space header, so they stay put when the Space changes.
- A selected favorite turns its tile white with a thin multicolour glow; no list row is highlighted.
- Navigating from a favorite with Cmd+L to another site **opened a new Today tab** rather than navigating the favorite.
- Links to other sites from a favorite open in Peek (see below). While the Peek is open, the favorite's tile shows a small badge with the Peek site's favicon at its top-right corner.

## Command bar

![New tab command bar](screenshots/command-bar-new-tab.jpg)

- **Cmd+T** opens a floating panel about 760 wide, horizontally centred on the window (not on the content card), with its top about a third of the way down. It overlaps the sidebar. The page behind is not dimmed; the panel just casts a large soft shadow.
- While it is open, the sidebar's "New Tab" row is highlighted as a placeholder for the tab about to be created.
- The input row has a magnifier, the placeholder "Search or Enter URL…", and an (i) button at the right. A hairline separates it from up to five results.
- Results have a favicon, a title, and an optional "— domain" suffix in grey. Open tabs show "Switch to Tab →" at the right. The selected row is filled with the Space's accent colour and has white text. The first row is pre-selected.
- With an empty query, the results are open tabs, then top sites, then Arc's own items ("Contact the Team"; not for Clair).
- **Site search:** typing a known site's keyword (here `wiki`) swaps the leading icon for that site's favicon and shows "Search Wikipedia [Tab]" at the right. Tab switches into searching that site.

![Site search](screenshots/command-bar-site-search.jpg)

- **Cmd+L** opens the same panel prefilled with the current tab's **full URL**, all selected. The first result is the current tab.

![Cmd+L](screenshots/command-bar-cmd-l.jpg)

- Choosing "Switch to Tab" while adding a split pane moves that existing tab into the split (see Split view).
- Esc closes the panel and nothing is created.

## Hiding the sidebar (Cmd+S)

![Sidebar hidden](screenshots/sidebar-hidden.jpg)

- The content card expands to fill the window with only a ~5 pt margin. The traffic lights and the sidebar toolbar are hidden. The window still shows a thin theme-coloured frame.
- Cmd+S again restores it.
- **Hover reveal:** resting the pointer on the window's left edge slides the sidebar in as a **floating overlay**: a rounded, shadowed, lighter translucent panel, inset a few points from the window edges and full height. The page is not resized underneath. Moving away slides it back out.

![Sidebar hover reveal](screenshots/sidebar-hover-reveal.jpg)

## Split view

![Adding a split](screenshots/split-view-add.jpg)

- **Ctrl+Shift+=** adds an empty pane to the right of the current one and opens the command bar to fill it. The panes are equal width (356 + 10 gap + 356).
- Each pane gets its own 32 pt header above its content:
  - inactive pane: back, forward, a link icon with the truncated host ("…binator.com"), and close (×)
  - focused pane: back, forward, reload, link icon and host, then the site-controls button, a split-layout button, and close
- With a split open, the sidebar's top row keeps only the sidebar toggle; back, forward and reload move to the pane headers. The URL field follows the focused pane.
- The focused pane has a 2 pt accent-coloured border.
- A drag handle sits in the gap between the panes.

![Two panes](screenshots/split-view-two-panes.jpg)

- In the sidebar, the split appears as **one row containing a chip per pane** (favicon + truncated title), highlighted as one active item.
- **Ctrl+Shift+- (Close this Split Pane) closed the focused pane's tab entirely.** The tab was not returned to the sidebar as a separate tab.
- **Drag to split:** dragging a sidebar tab over the page turns it into a portrait card (favicon and title, about 115×210). The page makes room live: the half under the pointer becomes a translucent, theme-tinted drop zone with an accent border, and the current page slides to the other half. Moving across swaps which side is the drop zone. Dropping creates the split.

![Drag to split](screenshots/drag-to-split.jpg)
![Split after drop](screenshots/split-dropped.jpg)

- Splitting a favorite with a Today tab showed up as a Today split row with chips for both pages, while the favorite tile stayed in place.
- **Sidebar hidden during a split:** the focused pane's header gains the sidebar toggle, back, forward and reload at its left. The inactive pane's header keeps only back/forward, host and ×.

![Split with sidebar hidden](screenshots/split-sidebar-hidden.jpg)

## Peek

![Peek loading](screenshots/peek-loading.jpg)
![Peek](screenshots/peek.jpg)

- Triggered by following a link to another site from a favorite (Return on a focused link). Settings say it also opens on Shift+click and for pinned tabs (see Settings › Links).
- The parent page recedes. It is scaled down slightly and washed out to a pale, low-contrast version behind the Peek.
- The Peek is a large rounded card, 586×952 here, centred over the content area and nearly full height. A short grabber bar shows at its top edge while it loads.
- Three round 34×33 buttons sit in a column at the Peek's top-right, outside the card: **Close (×)**, **Expand** (diagonal arrows; opens it as a full tab), and **Open in Split View**.
- While the Peek is open, the sidebar URL field shows the Peek's host, and reload turns into stop while it loads.
- **Esc closes the Peek** and returns to the parent page unchanged.

## Find in page (Cmd+F)

![Find](screenshots/find-in-page.jpg)

- A floating rounded field ("Find in page…" with a magnifier and ×) at the top-right corner of the content card. It is not Chromium's find bar.
- Esc closes it and leaves focus on the matched link (standard Chromium behaviour).

## Spaces

![New Space form](screenshots/new-space-form.jpg)

- **Spaces › New Space…** replaces the whole sidebar with an inline form:
  - an illustration, "Create a Space", and "Separate your tabs for life, work, projects, and more."
  - a name field with an icon-picker button on its left
  - a Profile row with a dropdown (default "Default") and an (i)
  - "Choose a Theme"
  - a "Create Space" button at the bottom, accent-filled and disabled until a name is typed, and "Cancel" below it
- The bottom bar shows the existing Space icon plus a dot for the Space being created.
- Return in the name field did **not** create the Space. Ctrl+1 (switch to Space 1) abandoned the form without creating anything.
- Data model: each Space has a `profile`, a `customInfo.iconType` (emoji/icon), and two containers: `pinned` and `unpinned` (Today). Space order is stored separately (`orderedSpaceIDs`).
- Not observed: switching between two Spaces (animation, swipe) and the bottom switcher with several Spaces.

## Windows

- A second window (Shift+Return on a link opens one, at 1280×800) shows the **same Space**, and its tabs appear in that Space's sidebar.
- Closing that window (Shift+Cmd+W) **kept its tab** in the Space's sidebar. Tabs belong to the Space, not the window.
- **Incognito window** (Shift+Cmd+N): the sidebar is forced dark, with an "Incognito Tabs" header in place of favorites and the Space header. The command bar opens automatically, and the bottom bar stays.

![Incognito](screenshots/incognito-window.jpg)

## Settings window

A 684×650 window with an icon toolbar of eight panes: account, General, Profiles, Max, Links, Shortcuts, Icon, Advanced. Each pane groups its rows in rounded cards with toggles on the right, in macOS System Settings style.

| Pane | Contents | Clair relevance |
|---|---|---|
| General | Automatically update; Warn before quitting; Previews settings; pointer to Profile settings; Ad blocker (Block Ads, Block Trackers, Block Cookie Banners, Ad Block Settings…) | Updates are decided (no update settings). Ad blocking is out of scope |
| Profiles | Explainer ("Profiles help keep your data separate across Spaces…"); profile list with Space counts and +/−/edit; per profile: Search engine, Search settings, Include search suggestions, **Archive tabs after (12 hours default)**, New documents, Download location; links to Privacy and Security, Passwords, Credit Cards, Notifications, Clear Browsing Data | Profile list and the search engine matter for the MVP. Archive is not in Clair. Passwords and cards are removed |
| Links | Little Arc toggles (Opt+Cmd+N anywhere, Opt+Cmd-click, links from other apps, archive Little Arcs after 6 h); **Peek: "Open a Peek window when clicking on links with Shift held" and "…on links to other sites" (only favorites and pinned tabs)**, both on by default; "Choose where links open inside Arc" (Air Traffic Control rules) | Peek behaviour is defined here. Little Arc and Air Traffic Control are out of scope |
| Shortcuts | "Learn the Essential Shortcuts"; a searchable list of every action with an editable shortcut field; "Custom Shortcuts" lets the user choose whether Arc or the website gets the key; Reset All Shortcuts | Editable shortcuts are not in Clair's MVP |
| Icon | Alternative app icons (original, candy, hologram, neon, flutedGlass, schoolbook, colorful) | Not in scope |
| Advanced | App build (Stable); sound effects; haptic feedback when reordering tabs; restore windows from the previous session; allow window dragging from the top of webpages; show full URL when the toolbar is on; Shared Quotes; PiP when leaving a video tab; allow websites to get theme data; Boosts; More Settings… (Chromium settings); Reset Translated-site Prompts; Export Data | Haptics on reorder, window dragging from the page top, and session restore are candidates |

![Settings: Links](screenshots/settings-links.jpg)

## Storage model (key structure only)

`~/Library/Application Support/Arc/StorableSidebar.json` holds one flat item graph per container:

- `items[]`: `id`, `parentID`, `childrenIds`, `title`, `createdAt`, `isUnread`, and `data`, which is one of:
  - `tab` (`savedURL`, `savedTitle`, `savedMuteStatus`, `timeLastActiveAt`, `activeTabBeforeCreationID`)
  - `list` (a folder)
  - `itemContainer` (`spaceItems` for a Space's pinned/unpinned roots, `topApps` for a profile's favorites)
- `spaces[]`: `id`, `profile`, `containerIDs`, `newContainerIDs` (pinned/unpinned), `customInfo.iconType`.
- `topAppsContainerIDs[]`: one favorites container per profile.

`StorableWindows.json` holds per-window `focusedSpaceID`, `sidebarWidth`, `sidebarMode`, `expandedItems` (open folders), `splitViewState` (`windowContentIDs`, `focusedContentID`) and `spacesWithCollapsedPinnedSections`. `StorableLinkRouting.json` holds the Air Traffic Control rules.

A pinned tab's `savedURL` is what "Back to Pinned URL" returns to. Tabs, folders and favorites share one tree model, and the containers decide where each item shows.

## Not yet observed

Left out on purpose for this pass:

- Space switching (two-finger swipe, Ctrl+N) and the switcher with several Spaces
- the theme editor
- the update-ready banner at the bottom of the sidebar

Not reached:

- reordering within Today, nested folders, dragging out of a folder
- downloads UI, site controls / permission popovers, extension icons in the sidebar
- dark appearance of a normal window
- animation timings and curves
