# Design

**Draft.** These decisions were made while planning the three changes together. Revise them against `add-spaces` and `share-tabs-across-windows` as built, then write `tasks.md`.

## Context

See proposal.md, "Why", and the `add-spaces` change's `arc-reference.md`, "Profile sheets", "Settings › Profiles" and "Space header menu". What shapes the approach:

- **One Chromium `Browser` has one profile, one window and one tab strip.** Each has one `ClairBrowserWindow`, one `ClairNativeWindow` (the `NSWindow`) and one `ClairWindow` in `ClairUI`. Chromium finds a browser from its `NSWindow` (`chrome::FindBrowserWithWindow`), and `AppController`'s `windowDidBecomeMain:` switches the last-used profile and the History menu from it.
- **A tab can't change profile.**
- **The earlier changes leave this in place:** the Space store in Local State, `ClairSpaceTabs` per profile, the shown-Space invariant, tabs moving between browsers of a profile, the still, and a closing window handing its tabs on.
- **Chromium's profile primitives cover profile management** (verified in 156.0.8078.73):
  - `ProfileManager::CreateMultiProfileAsync(name, icon_index, is_hidden, callback)` creates a profile.
  - `profiles::UpdateProfileName(profile, name)` renames a loaded profile.
  - `ProfileManager::GetDeleteProfileHelper().MaybeScheduleProfileForDeletion(path, callback, source)` deletes one.
  - `ProfileAttributesStorage` lists profiles and notifies observers.
  - `ProfileManager::LoadProfileByPath` loads one to read its prefs.
- **Chromium's own profile UI gets in the way.** `ProfilePicker::GetStartupMode()` shows the picker at launch once two profiles exist, unless Local State's `kBrowserProfilePickerAvailabilityOnStartup` is disabled. `ProfileMenuController` sets its main menu item's `hidden` on every rebuild, so hiding the Profiles menu doesn't last.
- **A window can cover a full-screen window instantly.** A prototype attached a second window over a full-screen one as its child, with `.fullScreenAuxiliary`: it was key and on screen in the same run-loop turn, with no transition. When the full-screen window left full screen, macOS animated the cover shrinking with it but left it at screen size afterwards. Making the second window enter full screen itself took a 0.6 s transition between macOS Spaces.

## Goals / Non-Goals

**Goals:**
- Use Chromium's profiles and prefs as they are; keep patches to hooks.
- Leave every Chromium assumption about windows intact.

**Non-Goals:**
- Hosting two profiles' browsers in one `NSWindow`.
- Clair's own records about profiles.

## Decisions

### D1. A profile is a Chromium profile, and Clair stores nothing about it

A profile's ID is its directory's base name (`Default`, `Profile 1`), as Arc uses. Its name and existence come from `ProfileAttributesStorage` alone. The overlay's `ClairProfiles` (`clair_profiles.{h,mm}`) wraps the calls in Context, observes the storage, and gives `ClairUI` snapshots through `ClairHost`.

- **Why:** one source of truth, and Chromium's own pages keep working.
- **Alternative:** Clair's own profile records. Rejected: two lists to keep in step.

At start-up the overlay sets `kBrowserProfilePickerAvailabilityOnStartup` to disabled in Local State.

### D2. A Space stores its profile

A Space in `clair.spaces` gains `"profile"`, the profile's directory name, read as the default profile when absent. A new Local State pref, `clair.windows`, maps a window group's UUID to the Space it shows (D3). The store gains two rules:

- A Space whose profile no longer exists moves to the default profile, at load and when `ProfileAttributesStorage` reports a removal. Clair's own UI can't cause this (D7); Chromium's profile pages can.
- `clair.windows` entries for groups that no longer exist are dropped once session restore has finished.

### D3. A window is a group of browsers, one per profile, and switching profile swaps them in place

`ClairWindowGroup` (`window/clair_window_group.{h,mm}`) is what the user sees as one window: at most one `Browser` per profile, of which one is shown and the rest are ordered out. Each member keeps its own `ClairBrowserWindow`, `ClairNativeWindow` and `ClairWindow`, exactly as today.

- **Same profile:** the shown member changes which Space it shows, as in `add-spaces`.
- **Another profile:** the group finds or creates its member for that profile, gives it the shown member's frame and sidebar state, shows it and makes it key, then orders the old one out, all in one run-loop turn with window animations off.
- **Frame and sidebar:** a group has one frame, one sidebar width and one sidebar visibility; a member takes them when it is shown.
- **A hidden member stays hidden.** `ClairBrowserWindow::Show()` and `Activate()` on a hidden member switch the group to that member's Space, since Chromium is asking to see it (a link from another app, "Switch to Tab").
- **A `Browser` Chromium creates on its own** (Cmd+N, session restore, `chrome.windows.create`) starts a group of its own, unless its tabs carry a group's tag (D6).
- **Incognito and guest windows** are groups of one, with no Spaces, and take no part in groups, shared tabs or Spaces.

- **Why:** this is the roadmap's decision, and it leaves every Chromium assumption about windows intact. `windowDidBecomeMain:` switches the last-used profile and History menu because the shown member really is the main window.
- **Alternative:** several browsers in one `NSWindow`. Rejected: it breaks finding a browser from its window, command dispatch and window ownership throughout the overlay.
- **Alternative:** one `Browser` per Space. Rejected: every switch would swap windows, and an empty Space can't exist as a browser.

### D4. In full screen, the incoming member covers the full-screen window

While a group is in macOS full screen, one member, the **owner**, holds the full-screen `NSWindow`. Switching to another profile attaches the incoming member's window over the owner as a child window with `.fullScreenAuxiliary`, at the owner's frame, and makes it key; the owner is not ordered out. Switching back to the owner's profile detaches the cover.

- `IsFullscreen()` answers for the group, and a request to enter or leave full screen (the green button, a page's full-screen request) goes to the owner.
- When the owner leaves full screen, the overlay sets the cover to the owner's restored frame, detaches it, and orders the owner out: a normal swap.
- The cover has square corners and hidden window controls, so the owner doesn't show at the corners.

- **Why:** the prototype showed it is instant, where a second full-screen window costs a 0.6 s transition.
- **Fallback, if it fails with real Chromium windows**: the group leaves full screen, then swaps.

### D5. Tabs across windows, per profile

`share-tabs-across-windows`' rules apply within each profile, with a group's member standing for the window:

- A tab is taken from, and a still shown by, the group's member for the tab's profile.
- A closing window hands each member's tabs to the most recently active other group's member for that profile, created hidden if it has none. Closing the last regular group closes its members through Chromium's close flow, hidden ones first; a cancelled prompt stops the rest and shows that member's Space.
- A hidden member left with no tabs closes.

### D6. Sessions carry the group as a third tag

Each tab's session extra data gains `clair_window`, its group's UUID, beside `clair_space` and `clair_order`. A restored browser joins the group named by its first tagged tab, when that tab is inserted, which is before session restore shows the window. The group shows the member whose profile matches its Space in `clair.windows`; the others stay hidden.

- **Why a tab tag for the group:** it needs no hook where Chromium creates the restored browser, and no second rebuild hook.

### D7. Profiles and Spaces stay consistent without a cascade

Remove is enabled only for a profile no Space uses, as in Arc, so removing a profile never closes a tab or a window, and the last profile can't be removed because the remaining Space uses it. A profile may have no Spaces. Its four link rows in Settings are then disabled, since there is no Space to open the page in.

`openURL:inProfile:` uses the most recently active regular group, or a new one: it shows the Space of that profile shown most recently in this run, or else the profile's first Space, and opens the tab there.

### D8. Chromium's last-used profile always has a Space

Cmd+N with no window open, and links from other apps, open in Chromium's last-used profile. `windowDidBecomeMain:` already sets it to the shown member's profile. When a profile loses its last Space while it is the last-used one, the overlay sets the last-used profile to that of `clair.last_space` with `profiles::SetLastUsedProfile`. If a browser still opens in a profile with no Space, its group switches to `clair.last_space` and that browser closes.

A new window shows the Space of the group that was active when it opened, or `clair.last_space` with none.

### D9. Changing a Space's profile reopens its tabs

`setProfile:forSpace:` updates the store, then, for each tab of the Space in list order, opens its URL in the target profile's member of the group that holds it, tagged with the Space at the same place in the list, and closes the original. Peeks close. `ClairUI` asks for confirmation first when the Space has tabs.

Moving one tab to a Space of another profile is this step for one tab; to a Space of the same profile it stays `add-spaces`' retag.

### D10. Menus

`InstallNativeWindowMenus` removes the item tagged `IDC_PROFILE_MAIN_MENU` from the main menu. `ProfileMenuController` keeps its reference and goes on updating an item nobody sees. `SpacesMenu` gains Change Profile ›, and the Space header's menu gains Set Profile ›.

### D11. The contract (`native/ClairHost.h`)

- **New snapshot:** `ClairProfile` (`profileID`, `name`). `ClairSpace` gains `profileID`.
- **`ClairHost` gains:**
  - `profiles`, and the observer learns that profiles changed;
  - `createProfileNamed:completion:`, `renameProfile:to:`, `deleteProfile:`;
  - `setProfile:forSpace:`, and `createSpaceNamed:icon:` takes a profile;
  - `downloadSettingsForProfile:completion:` (the folder and whether it asks every time), `setDownloadDirectory:forProfile:` and `setAsksWhereToSave:forProfile:`, which load the profile if needed and use its `download.default_directory`, `savefile.default_directory` and `download.prompt_for_download` prefs;
  - `openURL:inProfile:`.

### D12. `ClairUI`

- **The slide across profiles:** `shownSpaceDidChange:from:` reaches the window that is now shown, which draws the earlier Space's header and rows from `SpacesModel` and slides to the new one. So a cross-profile swap animates in the incoming window.
- **Dialogs:** `ProfileDialogs` holds the new, rename and delete dialogs as `ClairDialog`s, used from Settings and from "New Profile…" in the form, the Set Profile menus and Manage Spaces, where they swap the card's content.
- **Settings:** `SettingsPage` gains `profiles` after `general`; `ProfilesSettingsView` is the page, 684 pt wide, where the other pages stay 520.

## Risks / Trade-offs

- **[Hidden members during session restore]** Chromium may show a restored window before its first tagged tab arrives. → Test it early; the fallback hides non-shown members when session restore finishes.
- **[The cover in full screen]** Unproven with Chromium's windows, a page's own full screen, and the menu bar's reveal. → Prove it on a test build before the rest; D4 names the fallback.
- **[Extensions see hidden members]** `chrome.windows` lists one window per profile of a group. → Accepted.
- **[A profile with no Spaces can't open its settings pages]** → Its link rows are disabled with a note (D7).
