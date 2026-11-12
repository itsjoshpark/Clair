# Design

## Context

See proposal.md, "Why", and `arc-reference.md` for what Arc does. What shapes the approach:

- **One Chromium `Browser` has one profile, one window and one tab strip, and closes when its strip empties.** Today each `Browser` has one `ClairBrowserWindow`, one `ClairNativeWindow` (the `NSWindow`) and one `ClairWindow` in `ClairUI`. Chromium finds a browser from its `NSWindow` (`chrome::FindBrowserWithWindow`), and `AppController`'s `windowDidBecomeMain:` switches the last-used profile and the History menu from it.
- **A tab can move between browsers of one profile, never between profiles.** `TabStripModel::DetachTabAtForInsertion` returns the `tabs::TabModel` and `InsertDetachedTabAt` takes it, so the tab and its handle (Clair's `ClairTabID`) survive the move. `chrome::MoveTabsToExistingWindow` does this too, but appends at the end and calls `Show()` on the target, so the overlay uses the two strip calls directly.
- **A tab strip can't be changed while it notifies its observers.** Whatever must happen before a tab closes has to be done before the close starts.
- **Sessions carry string tags per tab.** `SessionService::AddTabExtraData` writes them, `CreateRestoredTab` in `browser_tabrestore.cc` receives them for session restore and Reopen Closed Tab, and the session file's rebuild drops them unless a hook writes them again. `peek-session.patch` already hooks these places.
- **Chromium's profile primitives cover profile management** (verified in 156.0.8078.73):
  - `ProfileManager::CreateMultiProfileAsync(name, icon_index, is_hidden, callback)` creates a profile.
  - `profiles::UpdateProfileName(profile, name)` renames a loaded profile.
  - `ProfileManager::GetDeleteProfileHelper().MaybeScheduleProfileForDeletion(path, callback, source)` deletes one.
  - `ProfileAttributesStorage` lists profiles and notifies observers.
  - `ProfileManager::LoadProfileByPath` loads one to read its prefs.
- **Chromium's own profile UI gets in the way.** `ProfilePicker::GetStartupMode()` shows the picker at launch once two profiles exist, unless Local State's `kBrowserProfilePickerAvailabilityOnStartup` is disabled. `ProfileMenuController` sets its main menu item's `hidden` on every rebuild, so hiding the Profiles menu doesn't last.
- **`RenderWidgetHostView::CopyFromSurface` copies a page once,** asynchronously, and may fail for an occluded page.
- **A window can cover a full-screen window instantly.** A prototype attached a second window over a full-screen one as its child, with `.fullScreenAuxiliary`: it was key and on screen in the same run-loop turn, with no transition. When the full-screen window left full screen, macOS animated the cover shrinking with it but left it at screen size afterwards. Making the second window enter full screen itself took a 0.6 s transition between macOS Spaces.
- **There are no existing users,** so nothing migrates.

## Goals / Non-Goals

**Goals:**
- Use Chromium's profiles, prefs and sessions as they are; keep patches to hooks.
- Keep every Chromium feature working per tab by leaving each tab in a real `Browser` of its profile.
- Give the implementer one owner for each piece of state.

**Non-Goals:**
- Hosting two profiles' browsers in one `NSWindow`.
- A tab that lives in no window.
- An interactive swipe that follows the fingers.
- Clair's own icon picker. macOS's emoji picker is the only one; a grid of SF Symbols may follow.

## Decisions

### D1. A profile is a Chromium profile, and Clair stores nothing about it

A profile's ID is its directory's base name (`Default`, `Profile 1`), as Arc uses. Its name and existence come from `ProfileAttributesStorage` alone. The overlay's `ClairProfiles` (`clair_profiles.{h,mm}`) wraps the calls in Context, observes the storage, and gives `ClairUI` snapshots through `ClairHost`.

- **Why:** one source of truth, and Chromium's own pages keep working.
- **Alternative:** Clair's own profile records. Rejected: two lists to keep in step.

At start-up the overlay sets `kBrowserProfilePickerAvailabilityOnStartup` to disabled in Local State.

### D2. The overlay owns the Space store, in Local State

`ClairSpaceStore` (`clair_space_store.{h,mm}`) keeps Spaces in Chromium's Local State, registered through a new `clair::RegisterLocalStatePrefs` called from `RegisterLocalState` in `browser_prefs.cc`:

```
clair.spaces      { "version": 1,
                    "order": ["<uuid>", …],
                    "spaces": { "<uuid>": { "name": "Work",
                                            "icon": "💼",              // one emoji, or absent
                                            "profile": "Profile 1" } } }
clair.windows     { "<group uuid>": "<space uuid>" }    // the Space each window shows
clair.last_space  "<space uuid>"                        // the Space last shown in a key window
```

Rules the store enforces, in one place:

- There is always one Space. With none stored it creates "Home" on the default profile.
- A Space whose profile no longer exists moves to the default profile, at load and when `ProfileAttributesStorage` reports a removal. Clair's own UI can't cause this (D15); Chromium's profile pages can.
- `clair.windows` entries for groups that no longer exist are dropped once session restore has finished.

- **Why Local State:** it is where Chromium keeps `profile.info_cache`, which Spaces refer to; it follows `--user-data-dir`, so test copies are isolated; and nearly every Space operation has a Chromium side effect the overlay must perform anyway.
- **Alternative:** a JSON file or `UserDefaults` owned by `ClairUI`. Rejected: a second store that can disagree with the profile list, and `UserDefaults` isn't per data folder.

### D3. A window is a group of browsers, one per profile, and switching profile swaps them in place

`ClairWindowGroup` (`window/clair_window_group.{h,mm}`) is what the user sees as one window: at most one `Browser` per profile, of which one is shown and the rest are ordered out. Each member keeps its own `ClairBrowserWindow`, `ClairNativeWindow` and `ClairWindow`, exactly as today.

- **Same profile:** the shown member changes which Space it shows (D6).
- **Another profile:** the group finds or creates its member for that profile, gives it the shown member's frame and sidebar state, shows it and makes it key, then orders the old one out, all in one run-loop turn with window animations off.
- **Frame and sidebar:** a group has one frame, one sidebar width and one sidebar visibility; a member takes them when it is shown.
- **A hidden member stays hidden.** `ClairBrowserWindow::Show()` and `Activate()` on a hidden member switch the group to that member's Space, since Chromium is asking to see it (a link from another app, "Switch to Tab").
- **A `Browser` Chromium creates on its own** (Cmd+N, session restore, `chrome.windows.create`) starts a group of its own, unless its tabs carry a group's tag (D11).
- **Incognito and guest windows** are groups of one, with no Spaces, and take no part in D5 to D10.

- **Why:** this is the roadmap's decision, and it leaves every Chromium assumption about windows intact. `windowDidBecomeMain:` switches the last-used profile and History menu because the shown member really is the main window.
- **Alternative:** several browsers in one `NSWindow`. Rejected: it breaks finding a browser from its window, command dispatch and window ownership throughout the overlay.
- **Alternative:** one `Browser` per Space. Rejected: every switch would swap windows, and an empty Space can't exist as a browser.

### D4. In full screen, the incoming member covers the full-screen window

While a group is in macOS full screen, one member, the **owner**, holds the full-screen `NSWindow`. Switching to another profile attaches the incoming member's window over the owner as a child window with `.fullScreenAuxiliary`, at the owner's frame, and makes it key; the owner is not ordered out. Switching back to the owner's profile detaches the cover.

- `IsFullscreen()` answers for the group, and a request to enter or leave full screen (the green button, a page's full-screen request) goes to the owner.
- When the owner leaves full screen, the overlay sets the cover to the owner's restored frame, detaches it, and orders the owner out: a normal swap.
- The cover has square corners and hidden window controls, so the owner doesn't show at the corners.

- **Why:** the prototype showed it is instant, where a second full-screen window costs a 0.6 s transition.
- **Fallback, if it fails with real Chromium windows** (task 5.5): the group leaves full screen, then swaps.

### D5. Each profile has one tab list per Space, and Clair owns its order

`ClairSpaceTabs` (`clair_space_tabs.{h,mm}`), one per regular profile, observes the tab strip of every native browser of that profile and keeps, for each Space, an ordered list of tab handles. It tags each tab with its Space as `WebContents` user data.

- **Which Space a tab joins:** its restored tag (D11) if that Space exists and uses this profile; a Peek joins its parent's; otherwise the Space its browser shows.
- **Where it goes in the order:**
  - A restored tab goes by its saved rank.
  - A tab inserted at strip index 0, where `clair::NewTabIndex` puts new tabs, goes to the top.
  - Any other tab goes directly after the nearest tab before it in the strip that belongs to the same Space, which keeps an expanded Peek below its parent.
- **Strip order no longer means anything to the user,** except that a Peek directly follows its parent in the strip, as today.
- **Reordering** changes the Space's list and touches no strip.

- **Why per profile:** tabs can move only between browsers of one profile, so that is the natural owner.
- **Alternative:** Chromium tab groups as Spaces. Rejected: they can't be empty, extensions can edit them, and pinned tabs and folders will want them.

### D6. A browser shows one Space, and its active tab belongs to it

Each member has a shown Space, set by `-[ClairBrowser showSpace:]` and stored per group in `clair.windows`. The invariant: **the active tab of a shown member belongs to its shown Space.** `ClairSpaceTabs` keeps it:

- If another tab becomes active for any reason (Chromium's choice after a page closed itself, an extension, "Switch to Tab"), the member's shown Space becomes that tab's Space.
- Showing a Space activates the tab last active in it in this member; failing that, the Space's most recently active tab that no shown member is showing, taken from its holder (D7); failing that, a new tab page (D8).

### D7. Selecting a tab held elsewhere moves it here

`-[ClairBrowser activateTab:]` on a tab another browser holds runs **take**:

1. If the holder is a shown member showing the tab, start its still and placeholder (D8).
2. Detach the tab from the holder's strip and insert it into this strip, active. Its Peek, if any, closes first.

A hidden member left with no tabs closes, as Chromium does for any empty browser.

### D8. A window that gives its tab away keeps a still over a hidden placeholder tab

When a shown member's active tab is taken:

1. The overlay asks for the page's copy with `CopyFromSurface`, with a 250 ms timeout, before the tab leaves.
2. It inserts a **placeholder**: a new tab page tab, marked as a placeholder in its `WebContents` user data, and activates it. A placeholder is in no Space list and has no row.
3. The member records the taken tab's ID. `ClairUI` shows the still dimmed over the card, highlights the taken tab's row, empties the URL field and disables back, forward and reload. If the copy fails, it dims the card's background alone.

The still ends when:

- **the window becomes key:** it takes the tab back (D7), and the placeholder closes;
- **the user selects another row or switches Space:** the placeholder closes once the other tab is active;
- **the taken tab closes:** the placeholder becomes an ordinary tab of the shown Space, at the top of its list, and the command bar opens.

The same "new tab page with the command bar" serves a new window and a Space with no tab to show, as an ordinary tab from the start.

A placeholder needs no session work: restored, it is an ordinary new tab page in the Space its window shows.

- **Why a placeholder:** Chromium needs an active tab, and activating any real tab would run its page as visible behind the still.

### D9. The next tab is chosen before a close starts

Each member remembers one **came-from** tab: set when the user selects a tab while another is active, cleared when a close changes the active tab. For a close Clair starts on the active tab (Cmd+W, the row's close button, middle-click, `-[ClairBrowser closeTab:]`), the overlay first activates, in order, the came-from tab if it is in the same Space, the row above, or the row below, taking it if needed (D7), and then closes the tab.

- When the Space has no other tab, and for a close Clair doesn't start (`window.close()`, an extension), Chromium's own choice stands, and D6 moves the window to that tab's Space. A window whose only tab closes this way closes.
- Closing a tab that isn't active here just closes it, in whichever browser holds it.

### D10. Closing a window hands its tabs to another window

When the user closes a window and another regular group is open, each member's tabs (not placeholders) move to the most recently active other group's member for that profile, created hidden if it has none, and the emptied members close. No tab closes, so no leave-page prompt shows. Closing the last regular group closes its members through Chromium's close flow, hidden ones first; a cancelled prompt stops the rest and shows that member's Space.

### D11. Sessions carry three tags per tab

`clair_space` (the Space's UUID), `clair_window` (the group's UUID) and `clair_order` (the tab's index in its Space's list) ride in each tab's session extra data, written by `ClairSpaceTabs` through `SessionService::AddTabExtraData` when they change. `patches/clair/space-session.patch` adds three calls into `window/clair_space_session.{h,mm}`:

- `session_service_base.cc`, in the rebuild: write the tags again.
- `browser_live_tab_context.cc`: add them for Reopen Closed Tab and Window.
- `browser_tabrestore.cc`, in `CreateRestoredTab`: read them onto the new `WebContents`, before it joins a strip.

A restored browser joins the group named by its first tagged tab, when that tab is inserted, which is before session restore shows the window. The group shows the member whose profile matches its Space in `clair.windows`; the others stay hidden.

- **Why tab tags for the group:** they need no hook where Chromium creates the restored browser, and no second rebuild hook.

### D12. Menus and shortcuts

- `InstallNativeWindowMenus` removes the item tagged `IDC_PROFILE_MAIN_MENU` from the main menu. `ProfileMenuController` keeps its reference and goes on updating an item nobody sees.
- `ClairUI`'s `SpacesMenu` adds a Spaces menu after View, as `ExtensionsMenu` adds its menu: New Space…, Rename Space, Change Profile ›, Next Space, Previous Space, and one item per Space. Its actions go up the responder chain to the key window's root view.
- `patches/clair/space-shortcuts.patch` removes Opt+Cmd+Left and Right from Chromium's own table in `global_keyboard_shortcuts_mac.mm` and puts Next and Previous Tab on Opt+Cmd+Down and Up, as `copy-url-shortcut.patch` did for Shift+Cmd+C.
- `ExecuteCommand` in `clair_native_window.mm` runs `IDC_SELECT_NEXT_TAB`, `IDC_SELECT_PREVIOUS_TAB`, `IDC_SELECT_TAB_0`…`7`, `IDC_SELECT_LAST_TAB`, `IDC_WINDOW_CLOSE_TABS_TO_RIGHT` and `IDC_WINDOW_CLOSE_OTHER_TABS` over the shown Space's rows, where it already steps over Peeks.

### D13. The contract (`native/ClairHost.h`)

- **New snapshots:** `ClairProfile` (`profileID`, `name`) and `ClairSpace` (`spaceID`, `name`, `icon`, `profileID`).
- **`ClairHost` gains:**
  - `profiles`, `spaces` (in order) and `tabsInSpace:` (in order);
  - `addObserver:` for a `ClairSpacesObserver`: profiles changed, Spaces changed, a Space's tabs changed (added, closed, moved), one tab changed;
  - `createProfileNamed:completion:`, `renameProfile:to:`, `deleteProfile:`;
  - `createSpaceNamed:icon:profile:` (returning its ID), `renameSpace:to:`, `setIcon:forSpace:`, `setProfile:forSpace:`, `moveSpace:toIndex:`, `deleteSpace:`, and `moveTab:toSpace:`;
  - `downloadSettingsForProfile:completion:` (the folder and whether it asks every time), `setDownloadDirectory:forProfile:` and `setAsksWhereToSave:forProfile:`, which load the profile if needed and use its `download.default_directory`, `savefile.default_directory` and `download.prompt_for_download` prefs;
  - `openURL:inProfile:`.
- **`ClairTab` gains** `spaceID` and `browserID`, the browser that holds it.
- **`ClairBrowser` gains** `browserID`, `shownSpaceID`, `showSpace:`, and `stillTabID` with `stillImage` (D8). `tabs` goes: rows come from the host. `moveTab:toIndex:` takes an index in the Space's list.
- **`ClairWindow`:** `tabsDidChange:` and `tabDidChange:` go, replaced by the host's observer. It gains `shownSpaceDidChange:from:` (the Space shown before, or nil, which drives the slide) and `stillDidChange`.

Pushes stay coalesced to once per run-loop turn per tab and per Space.

### D14. `ClairUI`

- **`SpacesModel`** (app-wide, `@Observable`) holds what the host's observer sends: profiles, Spaces and each Space's tabs. Every window's `BrowserWindowModel` reads its rows from it for its `shownSpaceID`.
- **Sidebar:** `SpaceHeaderView` above the tab list; `SpaceSwitcher` in `SidebarFooter`; `NewSpaceForm` in place of the header and list.
- **The slide:** the content between the URL field and the footer is a pager. On `shownSpaceDidChange:from:` the window that is now shown draws the earlier Space's header and rows from `SpacesModel` and slides to the new one, so a cross-profile swap animates in the incoming window. Start from an interpolating spring that covers about 80% of the distance in 100 ms and settles by 300 ms, then tune against Arc.
- **Icons:** a Space's icon is one emoji, chosen with macOS's emoji picker. `SpaceIconField` is a one-character text field where the icon shows, in the header and in the form. Change Space Icon… and the form's icon button make it first responder and call `NSApp.orderFrontCharacterPalette`. It keeps the first emoji of whatever is entered, ignores text that isn't an emoji, and clears on Delete; Return, Esc or losing focus ends the edit. The store keeps the string, so a later change can add glyphs, such as a grid of SF Symbols, under a prefix without changing the schema.
- **Dialogs:** `ProfileDialogs` holds the new, rename and delete dialogs, used from Settings and from "New Profile…" in the form, the Set Profile menu and Manage Spaces. `ManageSpacesDialog` is D21's. All are `ClairDialog`s (D20).
- **Settings:** `SettingsPage` gains `profiles` after `general`; `ProfilesSettingsView` is the page, 684 pt wide, where the other pages stay 520.

### D15. Profiles and Spaces stay consistent without a cascade

Remove is enabled only for a profile no Space uses, as in Arc, so removing a profile never closes a tab or a window, and the last profile can't be removed because the remaining Space uses it. A profile may have no Spaces. Its four link rows in Settings are then disabled, since there is no Space to open the page in.

`openURL:inProfile:` uses the most recently active regular group, or a new one: it shows the Space of that profile shown most recently in this run, or else the profile's first Space, and opens the tab there.

### D16. Chromium's last-used profile always has a Space

Cmd+N with no window open, and links from other apps, open in Chromium's last-used profile. `windowDidBecomeMain:` already sets it to the shown member's profile. When a profile loses its last Space while it is the last-used one, the overlay sets the last-used profile to that of `clair.last_space` with `profiles::SetLastUsedProfile`. If a browser still opens in a profile with no Space, its group switches to `clair.last_space` and that browser closes.

A new window shows the Space of the group that was active when it opened, or `clair.last_space` with none.

### D17. Changing a Space's profile reopens its tabs

`setProfile:forSpace:` updates the store, then, for each tab of the Space in list order, opens its URL in the target profile's member of the group that holds it, tagged with the Space at the same place in the list, and closes the original. Peeks close. `ClairUI` asks for confirmation first when the Space has tabs.

### D18. Moving a tab to another Space

`moveTab:toSpace:` has two cases, both in `ClairSpaceTabs`:

- **Same profile:** the tab's Space tag changes and it moves to the top of the target's list. The page isn't touched. The tab stays in the browser that holds it.
- **Another profile:** the tab's URL opens in the target profile, in the member of the same group (created hidden if needed), tagged with the target Space at the top of its list, and the original closes. This is D17's step for one tab.

If the tab is active here, the overlay first activates the next tab as D9 does for a close, so the window stays on its Space.

### D19. Reordering Spaces

`moveSpace:toIndex:` rewrites `clair.spaces`' `order` and notifies observers. `SpaceSwitcher` handles the drag; the Spaces menu rebuilds from the observer.

### D20. `ClairDialog`: Clair's own dialog

`ClairDialog.swift` adds one reusable SwiftUI component and a `.clairDialog(item:)` modifier, used on a browser window's root view and on the Settings window's content. It draws a dimmed layer over the window's content and a rounded, shadowed card centred on it, layered above the page as the command bar is.

- **Parts:** an optional icon, a title, a message, a content slot (a field, or D21's two columns), and a button row built from roles: cancel (Esc), default (Return) and destructive default (red). The buttons show their key in a small capsule, as Arc's do.
- **Blocking its window:** the dimmed layer takes every click, and the dialog holds first responder inside a focus scope, so keys don't reach the page; the browser window gives up the page's focus first, as it does for the command bar, and restores it on closing. It is modal to its window only.
- **One at a time per window, with one level on top:** a confirmation opened from a dialog (Remove in Manage Spaces, "New Profile…" in its profile popup) shows over it and returns to it.
- **Accessibility:** the card is a modal accessibility element titled by its title, with stable identifiers on its buttons for the runtime suite.

- **Why not `NSAlert` or a sheet:** their layout, corners, buttons and key hints can't be styled to match Arc's, and a sheet can't hold D21's two columns well.
- **Why in the window and not a child window:** it moves, resizes and goes full screen with its window for free, and needs no window ordering code.
- **Scope:** every dialog this change adds. `ExtensionPromptSheets` and the update prompts stay as they are; a later change moves them.

### D21. Manage Spaces

`ManageSpacesDialog.swift` is a `ClairDialog` with two columns in its content slot, shown in the window it was opened from:

- **Left:** the Spaces from `SpacesModel` in order, each row with icon, name and tab count; drag to reorder (`moveSpace:toIndex:`); Add and Remove under the list.
- **Right:** the selected Space's name field, its `SpaceIconField` and its profile popup with "New Profile…".
- Add creates a Space named "New Space" on the selected Space's profile and focuses its name. An emptied name reverts when the field loses focus.
- Remove and a profile change on a Space with tabs use the same confirmations as the header's menu.
- Its one button is "Done"; Esc closes it too.

It needs no contract of its own: every action is a host call D13 already lists. With no browser window open, Manage Spaces… is disabled.

## Risks / Trade-offs

- **[Hidden members during session restore]** Chromium may show a restored window before its first tagged tab arrives. → Task 5.6 tests it; the fallback hides non-shown members when session restore finishes.
- **[The cover in full screen]** Unproven with Chromium's windows, a page's own full screen, and the menu bar's reveal. → Task 5.5 proves it early; D4 names the fallback.
- **[A page copy can fail or come late]** → The still is optional: the card dims without it (D8).
- **[Extensions see hidden members]** `chrome.windows` lists one window per profile of a group, and tabs move between windows as the user moves between windows. → Accepted; both are ordinary Chromium events.
- **[Two windows on one tab move it on every focus change]** → Accepted; Arc does the same.
- **[A window can close when a page closes its only tab]** → Accepted (D9); it needs a close Clair didn't start.
- **[Reopen Closed Window brings back an empty window]** when its tabs moved to another window. → Accepted.
- **[A hand-built dialog must get keyboard and VoiceOver behaviour right]** that `NSAlert` gives for free. → D20 lists them, and the `dialogs` spec's scenarios are tested in the runtime suite.
- **[The contract change is large]** Every `ClairUI` test double changes. → Group 1 lands the contract and fakes first, so `ClairUI` work can proceed against `FakeHost` while the engine builds.
- **[Engine build time]** One engine build covers groups 2 to 5; fixes rebuild incrementally.

## Open Questions

- The first Space's name, "Home". It changes one string.
- The slide's exact curve, tuned in task 6.5 against a recording on real hardware.
