# Design

## Context

See proposal.md, "Why", and `arc-reference.md` for what Arc does. What shapes the approach:

- **One Chromium `Browser` has one window and one tab strip.** Today the sidebar lists the strip, in strip order, and `ClairBrowser.tabs` and `-[ClairWindow tabsDidChange:]` carry it.
- **A tab strip can't be changed while it notifies its observers.** Whatever must happen before a tab closes has to be done before the close starts.
- **Chromium picks the next active tab from the strip** when the active tab closes: its opener, or a neighbour.
- **Sessions carry string tags per tab.** `SessionService::AddTabExtraData` writes them, `CreateRestoredTab` in `browser_tabrestore.cc` receives them for session restore and Reopen Closed Tab, and the session file's rebuild drops them unless a hook writes them again. `peek-session.patch` already hooks these places.
- **The next two changes build on this one.** `share-tabs-across-windows` lets a tab move between windows of a profile, which `TabStripModel::DetachTabAtForInsertion` and `InsertDetachedTabAt` support while keeping the tab's handle (Clair's `ClairTabID`). `add-profiles` gives a Space a profile. So the tab lists and the contract take their final shape here.
- **There are no existing users,** so nothing migrates.

## Goals / Non-Goals

**Goals:**
- One owner for each piece of state: the Space list, each Space's tab order, and each window's shown Space.
- A contract and overlay structure the next two changes extend without reworking.
- Keep patches to hooks.

**Non-Goals:**
- Any tab moving between windows.
- More than one profile.

## Decisions

### D1. The overlay owns the Space store, in Local State

`ClairSpaceStore` (`clair_space_store.{h,mm}`) keeps Spaces in Chromium's Local State, registered through a new `clair::RegisterLocalStatePrefs` called from `RegisterLocalState` in `browser_prefs.cc`:

```
clair.spaces      { "version": 1,
                    "order": ["<uuid>", …],
                    "spaces": { "<uuid>": { "name": "Work",
                                            "icon": "💼" } } }   // one emoji, or absent
clair.last_space  "<space uuid>"      // the Space last shown in a key window
```

The store enforces that there is always one Space: with none stored it creates "Home", and it refuses to delete the last. `add-profiles` adds a `profile` field, read as the default profile when absent.

- **Why Local State:** it follows `--user-data-dir`, so test copies are isolated; it is where Chromium keeps its profile list, which Spaces will refer to; and Space operations have Chromium side effects (closing tabs, opening one) the overlay performs anyway.
- **Alternative:** a JSON file or `UserDefaults` owned by `ClairUI`. Rejected: `UserDefaults` isn't per data folder, and a second store would later have to agree with the profile list.

### D2. Each profile has one tab list per Space, and Clair owns its order

`ClairSpaceTabs` (`clair_space_tabs.{h,mm}`), one per regular profile, observes the tab strip of every native browser of that profile and keeps, for each Space, an ordered list of tab handles across all of them. It tags each tab with its Space as `WebContents` user data.

- **Which Space a tab joins:** its restored tag (D6) if that Space exists; a Peek joins its parent's; otherwise the Space its browser shows.
- **Where it goes in the order:**
  - A restored tab goes by its saved rank.
  - A tab inserted at strip index 0, where `clair::NewTabIndex` puts new tabs, goes to the top.
  - Any other tab goes directly after the nearest tab before it in the strip that belongs to the same Space, which keeps an expanded Peek below its parent.
- **Strip order no longer means anything to the user,** except that a Peek directly follows its parent in the strip, as today.
- **Reordering** changes the Space's list and touches no strip.
- **In this change a window lists only the rows it holds.** `ClairUI` filters a Space's list by `browserID`. `share-tabs-across-windows` removes the filter.

- **Why per profile and across windows now:** it is the shape the next change needs, and here it costs only the filter.
- **Alternative:** Chromium tab groups as Spaces. Rejected: they can't be empty, extensions can edit them, and pinned tabs and folders will want them.

### D3. A browser shows one Space, and its active tab belongs to it

Each native browser has a shown Space, set by `-[ClairBrowser showSpace:]`. The invariant: **the active tab of a browser belongs to its shown Space.** `ClairSpaceTabs` keeps it:

- If another tab becomes active for any reason (Chromium's choice after a page closed itself, an extension, "Switch to Tab", Restore Last Closed Tab), the browser's shown Space becomes that tab's Space.
- Showing a Space activates the tab last active in it in this browser, or else opens a new tab page with the command bar.

So which Space a window shows needs no storage of its own: after a relaunch it is its active tab's Space. A new browser shows the Space of the browser that was active when it opened, or `clair.last_space`.

### D4. The next tab is chosen before a close starts

Each browser remembers one **came-from** tab: set when the user selects a tab while another is active, cleared when a close changes the active tab. For a close Clair starts on the active tab (Cmd+W, the row's close button, middle-click, `-[ClairBrowser closeTab:]`), the overlay first activates, in order, the came-from tab if it is one of this window's rows of the Space, the row above, or the row below, and then closes the tab.

- When the window has no other row in the Space, and for a close Clair doesn't start (`window.close()`, an extension), Chromium's own choice stands, and D3 moves the window to that tab's Space. A window whose only tab closes, closes, as today.
- Moving the active tab to another Space (D7) uses the same choice.

### D5. Tab commands run over the rows

`ExecuteCommand` in `clair_native_window.mm` runs `IDC_SELECT_NEXT_TAB`, `IDC_SELECT_PREVIOUS_TAB`, `IDC_SELECT_TAB_0`…`7`, `IDC_SELECT_LAST_TAB`, `IDC_WINDOW_CLOSE_TABS_TO_RIGHT` and `IDC_WINDOW_CLOSE_OTHER_TABS` over the window's rows of the shown Space, where it already steps over Peeks. `closeTabsBelowTab:` and `moveTab:toIndex:` use the Space's list.

### D6. Sessions carry two tags per tab

`clair_space` (the Space's UUID) and `clair_order` (the tab's index in its Space's list) ride in each tab's session extra data, written by `ClairSpaceTabs` through `SessionService::AddTabExtraData` when they change. `patches/clair/space-session.patch` adds three calls into `window/clair_space_session.{h,mm}`:

- `session_service_base.cc`, in the rebuild: write the tags again.
- `browser_live_tab_context.cc`: add them for Reopen Closed Tab and Window.
- `browser_tabrestore.cc`, in `CreateRestoredTab`: read them onto the new `WebContents`, before it joins a strip.

### D11. Session restore is the default

`clair::RegisterProfilePrefOverrides`, which already sets Clair's defaults for the password and autofill prefs, also sets the default of `session.restore_on_startup` to Chromium's "continue where you left off" value. It is a default, not a forced value: "On startup" in `chrome://settings` still changes it, and Arc has the same switch in its Advanced settings. It is a profile pref, so it holds for every profile `add-profiles` creates.

- **Why a default override and not the `--restore-last-session` switch:** the switch can't be turned off by the user and doesn't show in settings.

### D7. Moving a tab to another Space, and reordering Spaces

- `moveTab:toSpace:` changes the tab's Space tag and puts it at the top of the target's list. The page isn't touched and the tab stays in its browser. If it is the active tab, the overlay first activates the next tab as D4 does, so the window stays on its Space.
- `moveSpace:toIndex:` rewrites `clair.spaces`' `order` and notifies observers.
- `deleteSpace:` closes the Space's tabs in every browser, after moving each browser that shows it to the Space before it.

### D8. Menus and shortcuts

- `ClairUI`'s `SpacesMenu` adds a Spaces menu after View, as `ExtensionsMenu` adds its menu: New Space…, Rename Space, Manage Spaces…, Next Space, Previous Space, and one item per Space. Its actions go up the responder chain to the key window's root view.
- `patches/clair/space-shortcuts.patch` removes Opt+Cmd+Left and Right from Chromium's own table in `global_keyboard_shortcuts_mac.mm` and puts Next and Previous Tab on Opt+Cmd+Down and Up, as `copy-url-shortcut.patch` did for Shift+Cmd+C.

### D9. The contract (`native/ClairHost.h`)

- **New snapshot:** `ClairSpace` (`spaceID`, `name`, `icon`).
- **`ClairHost` gains:**
  - `spaces` (in order) and `tabsInSpace:` (in order);
  - `addObserver:` for a `ClairSpacesObserver`: Spaces changed, a Space's tabs changed (added, closed, moved), one tab changed;
  - `createSpaceNamed:icon:` (returning its ID), `renameSpace:to:`, `setIcon:forSpace:`, `moveSpace:toIndex:`, `deleteSpace:` and `moveTab:toSpace:`.
- **`ClairTab` gains** `spaceID` and `browserID`, the browser that holds it.
- **`ClairBrowser` gains** `browserID`, `shownSpaceID` and `showSpace:`. `tabs` goes: rows come from the host. `moveTab:toIndex:` takes an index in the Space's list.
- **`ClairWindow`:** `tabsDidChange:` and `tabDidChange:` go, replaced by the host's observer. It gains `shownSpaceDidChange:from:`, with the Space shown before, or nil, which drives the slide.

Pushes stay coalesced to once per run-loop turn per tab and per Space.

### D10. `ClairUI`

- **`SpacesModel`** (app-wide, `@Observable`) holds what the host's observer sends: Spaces and each Space's tabs. Every window's `BrowserWindowModel` reads its rows from it for its `shownSpaceID`, filtered to its own `browserID`.
- **Sidebar:** `SpaceHeaderView` above the tab list; `SpaceSwitcher` in `SidebarFooter`; `NewSpaceForm` in place of the header and list.
- **The slide:** the content between the URL field and the footer is a pager. On `shownSpaceDidChange:from:` the window draws the earlier Space's header and rows from `SpacesModel` and slides to the new one. Start from an interpolating spring that covers about 80% of the distance in 100 ms and settles by 300 ms, then tune against Arc.
- **Icons:** `SpaceIconField` is a one-character text field where the icon shows, in the header, the form and Manage Spaces. Change Space Icon… and the icon buttons make it first responder and call `NSApp.orderFrontCharacterPalette`. It keeps the first emoji of whatever is entered, ignores text that isn't an emoji, and clears on Delete; Return, Esc or losing focus ends the edit. The store keeps the string, so a later change can add glyphs under a prefix without changing the schema.
- **Manage Spaces:** `ManageSpacesDialog` is a `ClairDialog` (`add-clair-dialogs`) with two columns in its content slot. Left: the Spaces in order, each with icon, name and tab count, drag to reorder, Add and Remove under the list. Right: the selected Space's name field and `SpaceIconField`. Add creates a Space named "New Space" and focuses its name; an emptied name reverts when the field loses focus. Remove on a Space with tabs asks by swapping the card's content. Its one button is "Done". It is disabled with no browser window open.
- **Confirmation:** Delete Space on a Space with tabs asks in a `ClairDialog`.

## Risks / Trade-offs

- **[The contract change is large]** Every `ClairUI` test double changes. → Group 1 lands the contract and fakes first, so `ClairUI` work can proceed against `FakeHost` while the engine builds.
- **[A restored tab's rank can collide or leave gaps]** after tabs were closed while Clair wasn't saving. → Ranks only order tabs on restore; ties fall back to strip order, and `ClairSpaceTabs` writes fresh ranks once restored.
- **[Closing a Space's last tab moves the window to another Space]** where Arc shows an empty Space. → Accepted: Clair's windows always show a tab.
- **[A window can close when a page closes its only tab]** → Accepted, as today.
- **[Tabs pile up now that every launch restores them]** → Accepted for now; closing old tabs automatically is a later change.

## Open Questions

- The first Space's name, "Home". It changes one string.
- The slide's exact curve, tuned in task 3.4 against a recording on real hardware.
