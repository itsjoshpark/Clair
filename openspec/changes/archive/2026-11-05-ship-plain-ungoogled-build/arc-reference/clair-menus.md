# Clair menus and shortcuts (decided)

Clair's macOS menu bar for the MVP, worked out by reviewing Arc 1.170.0's menus (see `menus-and-shortcuts.md`). Change 1 ships Chromium's stock menus. This file is the input for the MVP features change.

Standard macOS items (Edit/Find/Spelling/Substitutions, Window > Move & Resize, and the AutoFill submenu that macOS adds) are left out and keep their system behaviour.

## Menu bar

| Menu | Items (shortcut) |
|---|---|
| Clair | About Clair (shows the Clair and Chromium versions) · Settings… (Cmd+,) · Set as Default Browser · Check for Updates… (reads "Update Available…" with a "1 update" badge while a downloaded update is waiting, as in Arc) |
| File | New Tab… (Cmd+T, opens the command bar) · New Window (Cmd+N) · New Incognito Window (Shift+Cmd+N) · Restore Last Closed Tab (Shift+Cmd+T) · Open Command Bar (Cmd+L) · New Profile · Close Tab (Cmd+W) · Close Window (Shift+Cmd+W) · Print (Cmd+P) |
| Edit | standard items + Copy URL (Shift+Cmd+C) |
| View | Hide Sidebar (Cmd+S) · Collapse Pinned Tabs · Stop Loading (Cmd+.) · Refresh (Cmd+R) · Force Refresh (Shift+Cmd+R) · Add Split View (Ctrl+Shift+=) · Close Split Pane (Ctrl+Shift+-) · Separate Page from Split View · Expand Current Split · Actual Size / Zoom In / Zoom Out (Cmd+0 / Cmd++ / Cmd+-) · Developer > (View Source Opt+Cmd+U, Developer Tools Opt+Cmd+I, Inspect Elements Opt+Cmd+C, JavaScript Console Opt+Cmd+J, Allow JavaScript from Apple Events) · Enter Full Screen (Ctrl+Cmd+F) |
| Spaces | New Space… · Rename Space · Change Profile · Next Space (Opt+Cmd+Right) · Previous Space (Opt+Cmd+Left) · Space 1–9 (Ctrl+1…9) · Manage Spaces… |
| Tabs | New Tab… (Cmd+T) · Pin/Unpin Tab (Cmd+D) · New Folder… · Next Tab (Opt+Cmd+Down) · Previous Tab (Opt+Cmd+Up) · Reveal Tab in Sidebar · Clear Today (Shift+Cmd+K) · Back to Pinned URL · Close and Keep Pinned |
| History | Back (Cmd+[) · Forward (Cmd+]) · Show History (Cmd+Y) |
| Extensions | Add Extension… · Manage Extensions… |
| Window | standard items + Downloads (Shift+Cmd+J) |
| Help | Keyboard Shortcuts |

Deferred until after the MVP: File > Blank Window, File > Share…, Window > Stay On Top.

## Removed relative to Arc

- **Not in the MVP scope:**
  - Little Arc, Easels, Capture (all variants), Library, Media, Boosts
  - Edit Theme (no themes)
  - Cast (ungoogled disables Google's casting service)
- **No Arc account:** Share Arc, Privacy Policy, Sign Out.
- **Removed by choice:**
  - Import from Another Browser (menu item only; Chromium's Settings importer stays unless decided otherwise)
  - Save Page As
  - Copy URL as Markdown / as Quote
  - Appearance (websites follow the system appearance)
  - Reset all tabs in this Space
  - Contact the Team, Help Center, Restore Data, Export Notes, Troubleshooting
- **No archive concept:**
  - the Archive menu becomes **History**
  - View Archive and Clear Archive are removed
  - closing a Today tab, or Clear Today, simply closes the tabs; history is the only record
- **Show Toolbar (Shift+Cmd+D) removed:** the URL is shown only in the sidebar, and there is no setting to change that.

## Added relative to Arc

- File > Close Tab (Cmd+W): Arc handles the shortcut but hides it from the menu.
- Tabs > Back to Pinned URL and Close and Keep Pinned: Arc has these only in context menus.

## Shortcut conflicts: Arc's behaviour wins

| Shortcut | Chrome default | Clair (follows Arc) |
|---|---|---|
| Cmd+S | Save page | Hide sidebar (Save Page As is removed) |
| Cmd+D | Bookmark page | Pin/unpin tab |
| Cmd+L | Focus the address bar | Open the command bar on the current URL |
| Opt+Cmd+Left/Right | Previous/next tab | Previous/next Space |
| Opt+Cmd+Up/Down | none | Previous/next tab |
| Cmd+1…9 | Tab N | Sidebar item N; favorites do **not** count toward N (Arc makes this optional, Clair doesn't) |
| Shift+Cmd+C | Inspect element | Copy URL (Inspect Elements moves to Opt+Cmd+C) |

Chromium's default shortcuts for these keys must be reassigned or removed. Otherwise Chromium would handle the key before Clair's command does.

## Consequence: the toolbar moves into the sidebar

Because the URL appears only in the sidebar, Chromium's top toolbar is removed, and everything it holds has to live in the sidebar:

- back / forward / reload
- the URL display (Cmd+L edits it through the command bar)
- the site-info and permission chips (camera, microphone, location, etc.)
- extension action icons and their popups
- the download indicator

Chromium attaches permission prompts, extension popups and the download bubble to toolbar buttons. They need new anchor points in the sidebar, plus a fallback anchor when the sidebar is hidden (Cmd+S) or the window is in full screen. Helium's `ui/layout/minimal-location-bar.patch` and `ui/layout/zen-mode*.patch` are references. This belongs in the UX spike.
