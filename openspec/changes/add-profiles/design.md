# Design

Revised on 2026-11-13 against `add-spaces` (#138) and `share-tabs-across-windows` (#140, #142) as built. "`add-spaces` D*n*" and "`share-tabs` D*n*" below are decisions in those changes' archived `design.md`.

## Context

See proposal.md, "Why", and `openspec/changes/archive/2026-11-12-add-spaces/arc-reference.md`, "Profile sheets", "Settings › Profiles" and "Space header menu". What shapes the approach:

- **One Chromium `Browser` has one profile, one window and one tab strip.** This is a limit of Chromium, not what the user sees: the user sees one window that shows Spaces of any profile, which D3 builds from one `Browser` per profile. Each `Browser` has one `ClairBrowserWindow`, one `ClairNativeWindow` (the `NSWindow`) and one `ClairWindow` in `ClairUI`. Chromium finds a browser from its `NSWindow` (`chrome::FindBrowserWithWindow`), and `AppController`'s `windowDidBecomeMain:` switches the last-used profile and the History menu from it.
- **A tab can't change profile in Chromium:** its `WebContents` belongs to one profile for life. The user can still move a tab, or a whole Space, to another profile: Clair reopens it there at its URL (D9), so the page reloads and its state is lost.
- **The earlier changes leave this in place:**
  - the Space store in Local State, and `ClairSpaceTabs` per profile with one ordered tab list per Space across that profile's browsers;
  - the shown-Space invariant (`add-spaces` D3) and the came-from rule (`add-spaces` D4);
  - the take, which moves a tab between browsers of one profile, and the still over a placeholder tab (`share-tabs` D1, D2);
  - the user's close of a window handing its tabs to another window, while every other close goes through Chromium's close flow (`share-tabs` D4, #142);
  - a close of a Space's last tab showing a tab of another Space (`share-tabs` D3), which D13 replaces;
  - session restore at every launch, reopening the windows Chromium saved, each with the tabs it held (`add-spaces` D11), which D6 changes.
- **Arc at relaunch** (observed on 2026-11-13 with the probe, two windows on different Spaces, each with a tab selected):
  - With its restore-windows setting off, the default (`arc_quitAlwaysKeepsWindows`), Arc opens one window, on the Space the last active window showed, with no tab selected and the command bar open. Every tab is still listed in its Space.
  - With it on, both windows come back, each on its Space with its tab selected.
- **Arc keeps an empty Space.** Closing a Space's only tab leaves the window on that Space with no tab selected (observed the same day).
- **Chromium's profile primitives cover profile management** (verified in 156.0.8078.73, and still present in 156.0.8078.79):
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

For the window the user sees, nothing changes from `share-tabs-across-windows`: its rules already work per profile, since `ClairSpaceTabs` is per profile and a take moves a tab between two browsers of one profile. What is new is the hidden member, which that change never had. Its rules:

- **A hidden member shows no tab.** "A tab no window shows" (`share-tabs` D3) includes a hidden member's active tab, so taking it starts no still there. A take goes to the group's member for the tab's profile, created if the group has none.
- **Switching a group to another profile ends a still** its outgoing member showed: the tab stays with the window that took it, and the member keeps its placeholder as its active tab, without a still. When the group shows that member again, showing the Space picks a tab as usual (`share-tabs` D3) and the placeholder closes.
- **A hidden member needs no tab of its own.** When its last tab is taken or closes, it closes; a placeholder doesn't count. The group makes a new member when it next shows a Space of that profile.
- **The user's close** (`share-tabs` D4, #142) hands each member's tabs to the most recently active other group's member for that profile, created hidden if it has none, and then closes the emptied members. Any other close of a member, such as an extension's `chrome.windows.remove`, is Chromium's close flow for that member alone.
- **Closing the last regular group** closes its members through Chromium's close flow, hidden ones first; a cancelled prompt stops the rest and shows that member's Space.

### D6. Sessions carry the group as a third tag, and a setting says whether windows come back

Each tab's session extra data gains `clair_window`, its group's UUID, beside `clair_space` and `clair_order`. Chromium's session restore still reopens every browser it saved, in every profile. What the overlay makes of them follows "When opening Clair, restore windows from previous session", the user default `ClairRestoreWindows` (off when unset), read once at launch:

- **On:** a restored browser joins the group named by its first tagged tab, when that tab is inserted, which is before session restore shows the window. The group shows the member whose profile matches its Space in `clair.windows`, on the tab Chromium restored as that member's selected one; the others stay hidden.
- **Off, as Arc by default:** every restored browser joins one group, at the frame of the window that was last active. A second browser of a profile hands its tabs to the first, as a closing window does (`share-tabs` D4), and closes. The group shows `clair.last_space` on a new tab page with the command bar open, as a new window does. No member shows before session restore has finished.

Today every window comes back (`add-spaces` D11), so "off" as the default is a change of behaviour for existing sessions, to Arc's.

**New tab pages aren't restored.** Where `peek-session.patch` already calls `DropPeeks` on the windows session restore is about to restore, the overlay also drops every tab whose current entry is the new tab page, and a window left without tabs. So the new tab page a launch opens is the only one, and those left by Cmd+N or an emptied Space (D13) don't pile up across launches. With the setting on, a group whose restored member has no selected tab of its Space left opens a new tab page there.

- **Why drop them at restore, and not reuse a blank one:** it is one filter beside an existing one, where reuse needs to know whether a page was ever navigated and whether a window shows it, in every place a new tab page is opened.
- **Why a tab tag for the group:** it needs no hook where Chromium creates the restored browser, and no second rebuild hook.
- **Why merge after Chromium's restore, and not restore fewer windows:** the tabs of every window must come back in their Spaces either way, and Chromium restores tabs only with their windows.
- **Why a user default:** the setting is the app's, not a profile's, and `ClairUI`'s other toggles are user defaults.

### D7. Profiles and Spaces stay consistent without a cascade

Remove is enabled only for a profile no Space uses, as in Arc, so removing a profile never closes a tab or a window, and the last profile can't be removed because the remaining Space uses it. A profile may have no Spaces. Its four link rows in Settings are then disabled, since there is no Space to open the page in.

`openURL:inProfile:` uses the most recently active regular group, or a new one: it shows the Space of that profile shown most recently in this run, or else the profile's first Space, and opens the tab there.

### D8. Chromium's last-used profile always has a Space

Cmd+N with no window open, and links from other apps, open in Chromium's last-used profile. `windowDidBecomeMain:` already sets it to the shown member's profile. When a profile loses its last Space while it is the last-used one, the overlay sets the last-used profile to that of `clair.last_space` with `profiles::SetLastUsedProfile`. If a browser still opens in a profile with no Space, its group switches to `clair.last_space` and that browser closes.

A new window shows the Space of the group that was active when it opened, or `clair.last_space` with none.

### D9. Changing a Space's profile reopens its tabs

`setProfile:forSpace:` updates the store, then, for each tab of the Space in list order, opens its URL in the target profile's member of the group that holds it, tagged with the Space at the same place in the list, and closes the original. `ClairUI` asks for confirmation first when the Space has tabs.

- **No leave-page prompt.** The originals close without running `beforeunload`, since the user has confirmed, and Arc's confirmation says it can't be undone.
- **Peeks close** with their parents.
- **The active tab.** In each group showing the Space, the tab reopened from the active one becomes active, in the group's member for the new profile, which the group swaps to (D3).
- **Stills.** A window showing a still of one of the tabs gets a new tab page, as for any still whose tab closes (`share-tabs` D2). A take waiting for its page's copy is dropped first.

Moving one tab to a Space of another profile is this step for one tab; to a Space of the same profile it stays `add-spaces`' retag.

**The window follows the active tab.** This replaces `add-spaces` D7's choice of a next tab. When `moveTab:toSpace:` moves the tab that is active in the window it was called for, that window shows the destination Space with the tab, or the tab reopened from it, active; across profiles that is the group's swap (D3). When it moves any other tab, the window stays, and `ClairUI`, which knows which case it is, shows "Tab was moved to <name>" in its `NoticePopup`, as Copy URL does. Another window that was showing the moved tab picks its next tab as if the tab had closed there.

### D10. Menus

`InstallNativeWindowMenus` removes the item tagged `IDC_PROFILE_MAIN_MENU` from the main menu. `ProfileMenuController` keeps its reference and goes on updating an item nobody sees. It also removes Chromium's "Warn Before Quitting" item from the application menu, found by its action, `toggleConfirmToQuit:`, since it has no tag, and the separator left beside it; the Advanced toggle replaces it (D12). The Space header's menu gains Set Profile › and `SpacesMenu` gains Change Profile ›, Arc's names for the one submenu, acting on the window's Space.

### D11. The contract (`native/ClairHost.h`)

- **New snapshot:** `ClairProfile` (`profileID`, `name`). `ClairSpace` gains `profileID`.
- **`ClairHost` gains:**
  - `profiles`, and the observer learns that profiles changed;
  - `createProfileNamed:completion:`, `renameProfile:to:`, `deleteProfile:`;
  - `setProfile:forSpace:`, and `createSpaceNamed:icon:` takes a profile;
  - `downloadSettingsForProfile:completion:` (the folder and whether it asks every time), `setDownloadDirectory:forProfile:` and `setAsksWhereToSave:forProfile:`, which load the profile if needed and use its `download.default_directory`, `savefile.default_directory` and `download.prompt_for_download` prefs;
  - `openURL:inProfile:`;
  - `warnsBeforeQuitting`, read and write, over Local State's `browser.confirm_to_quit`, which Chromium registers as on.

### D12. `ClairUI`

- **The slide across profiles:** `shownSpaceDidChange:from:` reaches the window that is now shown, which draws the earlier Space's header and rows from `SpacesModel` and slides to the new one. So a cross-profile swap animates in the incoming window.
- **Dialogs:** `ProfileDialogs` holds the new, rename and delete dialogs as `ClairDialog`s, used from Settings and from "New Profile…" in the form, the Set Profile and Change Profile menus and Manage Spaces, where they swap the card's content.
- **Settings:** `SettingsPage` gains `profiles` after `general`; `ProfilesSettingsView` is the page, 684 pt wide, where the other pages stay 520. The window opens on General each time: `SettingsPage.stored(in:)` and the `ClairSettingsPage` user default go. The Advanced page gains two toggles: "Warn before quitting", bound to the host's `warnsBeforeQuitting`, and "When opening Clair, restore windows from previous session", bound to `ClairRestoreWindows` (D6).
- **A dialog follows a swap.** A `ClairDialog` is attached to one member's window. When the group swaps under an open Manage Spaces dialog, as when the shown Space's profile changes there, the incoming window presents the dialog again with the same selection, in the same run-loop turn.

### D13. An emptied Space keeps its window

This replaces `share-tabs` D3's "The Space's last tab". When a close Clair starts would leave the shown Space with no row, the overlay first opens a new tab page in the Space, with the command bar, and then closes the tab. A window therefore never changes Space, or profile, because a tab closed. `ShowTabOfAnotherSpace` goes.

- **Closing that new tab page** while it is the Space's only row closes the window, as the user's close does (D5), and the page closes with it instead of being handed on. Arc closes a window with no tab selected. Otherwise Cmd+W would only ever replace it.
- **A close Clair doesn't start** (`window.close()`, an extension) on a member's only tab still closes that browser, as accepted in `share-tabs`. A shown member that closes this way closes its group, as the user's close does.

- **Why:** Arc keeps the empty Space, and with profiles the old rule would swap the window to another profile on a close.

## Risks / Trade-offs

- **[A launch shows a new tab page where Arc shows no tab]** → Accepted: Clair's windows always show a tab. New tab pages aren't restored, so they don't pile up (D6).
- **[Restored windows flash before they merge]** with restoring windows off. → No member shows until session restore has finished (D6).
- **[Hidden members during session restore]** Chromium may show a restored window before its first tagged tab arrives. → Test it early; the fallback hides non-shown members when session restore finishes.
- **[The cover in full screen]** Unproven with Chromium's windows, a page's own full screen, and the menu bar's reveal. → Prove it on a test build before the rest; D4 names the fallback.
- **[Extensions see hidden members]** `chrome.windows` lists one window per profile of a group. → Accepted.
- **[A profile with no Spaces can't open its settings pages]** → Its link rows are disabled with a note (D7).
