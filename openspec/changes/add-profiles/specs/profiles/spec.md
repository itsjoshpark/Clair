# Spec Delta

## Purpose

Profiles keep a user's browsing data separate between Spaces, as in Arc. This covers what a profile isolates, how a Space uses a profile and changes it, switching between profiles in one window, the Profiles page in Settings and its actions, and the absence of Chromium's own profile menu and picker.

## ADDED Requirements

### Requirement: Profiles separate browsing data
Each profile SHALL be a Chromium profile with its own cookies, logins, history, extensions, site permissions, downloads and settings. Spaces that use the same profile SHALL share all of these, and Spaces that use different profiles SHALL share none.

#### Scenario: Different profiles
- **WHEN** the user signs in to a site in a Space using the default profile and opens the same site in a Space using the "Work" profile
- **THEN** the site isn't signed in there

#### Scenario: Same profile
- **WHEN** the user signs in to a site in one Space and opens the same site in another Space using the same profile
- **THEN** the site is signed in there

#### Scenario: Extensions follow the profile
- **WHEN** an extension is installed and pinned in the default profile, and the user switches to a Space using "Work"
- **THEN** the sidebar and the Extensions menu show the extensions of "Work", without that one

### Requirement: Each Space uses one profile
Each Space SHALL use exactly one profile, and several Spaces MAY use the same one. A Space's tabs SHALL use its profile. A Space created without a choice of profile SHALL use the profile of the Space the window shows. The Space's profile SHALL persist across launches.

#### Scenario: First launch
- **WHEN** Clair launches for the first time
- **THEN** its one Space uses the default profile

#### Scenario: Two Spaces on one profile
- **WHEN** "Home" and "Research" use the default profile, and the user signs in to a site in "Home"
- **THEN** the site is signed in in "Research" too

### Requirement: Switching to a Space of another profile
Switching Spaces SHALL work the same whether or not the two Spaces use the same profile: in the same window, at the same frame, sidebar width and sidebar visibility, with the same slide.

#### Scenario: Another profile
- **WHEN** a window shows "Home" in the default profile and the user switches to "Work", which uses another profile
- **THEN** the same window, at the same frame and sidebar width, shows "Work", and its pages use that profile's cookies and logins

#### Scenario: Extensions and history follow
- **WHEN** the window then shows "Work"
- **THEN** the sidebar's pinned extensions, the Extensions menu and the History menu are those of the "Work" profile

### Requirement: Tabs across windows in every profile
The rules of `spaces` for tabs across windows SHALL hold for a Space of any profile, whichever profile's Space each window showed before: every window lists the same tabs for the Space, a tab shows in one window at a time with a still in the window it left, and a closed window's tabs stay listed while another window is open.

#### Scenario: Taking a tab of another profile
- **WHEN** window A shows the tab "Docs" in "Work", which uses another profile than "Home", and the user switches window B from "Home" to "Work" and selects "Docs"
- **THEN** B shows the live page, without reloading it, and A shows a faded still of it

#### Scenario: Closing a window that opened tabs of two profiles
- **WHEN** two windows are open, and the user closes the one in which tabs of "Home" and of "Work" were opened
- **THEN** those tabs stay listed in "Home" and "Work" in the other window, and selecting one shows its page without reloading it

### Requirement: Profiles after a relaunch
After a relaunch, each Space SHALL use the profile it used, and its restored tabs SHALL load in it. A window SHALL come back as one window, whichever profiles its tabs used: Clair SHALL never open one window per profile.

#### Scenario: One window
- **WHEN** the user quits with one window that opened tabs in "Home" and in "Work", which uses another profile, and relaunches
- **THEN** one window opens, and "Home" and "Work" list their tabs, each loaded in its Space's profile

#### Scenario: A restored window on another profile
- **WHEN** "When opening Clair, restore windows from previous session" is on, and the user quits with one window showing the tab "Docs" in "Work" and relaunches
- **THEN** one window opens, showing "Docs" in "Work"

### Requirement: Switching in full screen
Switching Spaces while the window is in macOS full screen SHALL keep the window in full screen, without a transition between macOS Spaces, whichever profiles the two Spaces use. Leaving full screen afterwards SHALL return the window to the frame it had before entering.

#### Scenario: Another profile in full screen
- **WHEN** a full-screen window shows "Home" and the user switches to "Work", which uses another profile
- **THEN** the window shows "Work" in full screen at once

#### Scenario: Leaving full screen after a switch
- **WHEN** the user then leaves full screen
- **THEN** the window returns to its earlier frame, still showing "Work"

### Requirement: Choosing a profile for a new Space
The New Space form SHALL have a profile popup listing every profile, with the profile of the Space shown before selected, and "New Profile…". The Manage Spaces dialog SHALL show the same popup for the selected Space.

#### Scenario: Creating a Space on another profile
- **WHEN** the user opens the form, types "Work", chooses the profile "Work" and clicks "Create Space"
- **THEN** a Space "Work" using that profile is last in the switcher, and the window shows it with a new tab page

#### Scenario: New profile from the form
- **WHEN** the user chooses "New Profile…" in the form's profile popup and creates the profile "Client"
- **THEN** the form's popup shows "Client" selected

### Requirement: Changing a Space's profile
The Space header's menu SHALL offer Set Profile and the Spaces menu Change Profile, as Arc names them, each listing every profile, with a checkmark on the Space's, and "New Profile…", as the Manage Spaces dialog's profile popup does. Choosing another profile SHALL apply at once for a Space with no tabs. For a Space with tabs, a dialog SHALL first ask, saying that the tabs will reload and may be signed out; on confirmation each tab SHALL reopen at its URL in the new profile, in the same order.

#### Scenario: Empty Space
- **WHEN** the user sets the profile of a Space with no tabs to "Work"
- **THEN** the Space uses "Work" at once, with no prompt

#### Scenario: Space with tabs
- **WHEN** the user sets the profile of a Space with three tabs to "Work" and confirms
- **THEN** the Space lists the same three URLs in the same order, loaded in the "Work" profile

#### Scenario: Cancelled
- **WHEN** the user cancels the confirmation
- **THEN** the Space keeps its profile and its tabs are untouched

### Requirement: Windows follow a Space whose profile changes
When a Space's tabs reopen in a new profile, no page SHALL ask before leaving, since the user has confirmed, and a tab's Peek SHALL close. A window showing one of the Space's tabs SHALL show the tab reopened in its place, and a window showing a still of one SHALL show a new tab page, as when a still's tab closes. The Manage Spaces dialog SHALL stay open when the profile changed is that of the Space its window shows.

#### Scenario: A page that asks before leaving
- **WHEN** one of the Space's tabs has a page that asks whether to leave, and the user sets the Space's profile to "Work" and confirms
- **THEN** the tab reopens in "Work" without the page asking

#### Scenario: The shown Space, from Manage Spaces
- **WHEN** a window shows "Home" on the tab "Docs", and the user sets the profile of "Home" to "Work" in Manage Spaces and confirms
- **THEN** the dialog stays open, showing "Work" in the popup, and the window shows "Docs" loaded in "Work"

### Requirement: Moving a tab to a Space of another profile
"Move to Space" SHALL list Spaces of every profile. A tab moved to a Space of another profile SHALL be opened there at its URL, at the top of that Space's list, and removed from this one, since a page can't change profile. Its page SHALL NOT ask before leaving, and its Peek SHALL close. The window SHALL stay on the Space it shows, as for any move.

#### Scenario: Another profile
- **WHEN** the user moves a tab from "Home" to "Work", which uses another profile
- **THEN** "Work" lists a tab at the same URL, loaded in its profile, and "Home" no longer lists the tab

#### Scenario: Moving the active tab
- **WHEN** the user moves the active tab of "Home" to "Work", which uses another profile
- **THEN** the window stays on "Home" and shows the tab it would show had the moved tab been closed

#### Scenario: Same profile
- **WHEN** the user moves a tab to a Space using the same profile
- **THEN** the tab keeps its page as it is

### Requirement: No Chromium profile menu or picker
The menu bar SHALL have no Profiles menu. Clair SHALL NOT show Chromium's profile picker at launch, however many profiles exist. A window SHALL open on a Space, never on a profile chosen in Chromium's own profile UI.

#### Scenario: Menu bar
- **WHEN** the user reads the menu bar with two profiles present
- **THEN** it has a Spaces menu and no Profiles menu

#### Scenario: Launch with two profiles
- **WHEN** Clair launches with two profiles present
- **THEN** a browser window opens, and no profile picker shows

### Requirement: Profiles page
The Settings window's Profiles page SHALL show, at the top, the text "Profiles help keep your data separate across Spaces — like history, logins, cookies, and extensions. You can use any Profile across one or more Spaces." Below it SHALL be two columns: the list of profiles on the left, and the settings of the profile selected in it on the right.

#### Scenario: Opening the page
- **WHEN** the user opens the Profiles page
- **THEN** it shows the help text above the profile list on the left and the selected profile's settings on the right

### Requirement: Profile list
The list SHALL be headed "Your Profiles" and show each profile's name and how many Spaces use it, with Add, Remove and Rename buttons at its bottom edge. One profile SHALL always be selected: the first when the page opens, and a neighbour when the selected one is removed. The list SHALL follow changes made elsewhere at once.

#### Scenario: Two profiles
- **WHEN** the default profile has two Spaces and "Work" has one, and the user opens the Profiles page
- **THEN** the list shows the default profile with "2 Spaces" and "Work" with "1 Space", with the first selected and its settings on the right

#### Scenario: Selecting a profile
- **WHEN** the user clicks "Work" in the list
- **THEN** the right side shows the settings of "Work"

#### Scenario: A change elsewhere
- **WHEN** the Profiles page is open and the user creates a Space using "Work" in a browser window
- **THEN** the row for "Work" shows "2 Spaces"

### Requirement: Adding a profile
Add, and "New Profile…" wherever profiles are listed, SHALL ask for the new profile's name in a dialog, as in Arc, with "Create Profile" disabled until a name is typed. Creating SHALL add a profile with that name and no Spaces, and select it where it was asked for.

#### Scenario: Adding from Settings
- **WHEN** the user clicks Add, types "Client" and presses Return
- **THEN** "Client" is in the list, selected, with no Space count

#### Scenario: Cancelling
- **WHEN** the user clicks Add and presses Esc
- **THEN** no profile is created

### Requirement: Renaming a profile
Rename SHALL ask for the selected profile's new name in a dialog that says the names of its Spaces won't change. Saving a non-empty name SHALL rename the profile everywhere it is listed, at once, including while windows show its Spaces.

#### Scenario: Renaming the profile in use
- **WHEN** a window shows a Space using "Work", and the user renames "Work" to "Office"
- **THEN** the Profiles list and the Set Profile and Change Profile menus show "Office", the Space keeps its name, and the window keeps showing its page

#### Scenario: Empty name
- **WHEN** the user clears the name in the dialog
- **THEN** "Save" is disabled

### Requirement: Removing a profile
Remove SHALL be enabled only for a profile that no Space uses. It SHALL ask for confirmation in a dialog that says the profile's cookies, history, preferences and logins will be permanently removed, and SHALL enable "Delete" only once the user has typed the profile's name. Confirming SHALL delete the profile and its data.

#### Scenario: Profile in use
- **WHEN** the user selects a profile that one Space uses
- **THEN** Remove is disabled

#### Scenario: The last profile
- **WHEN** there is one profile
- **THEN** Remove is disabled, since the remaining Space uses it

#### Scenario: Removing
- **WHEN** the user selects "Client", which no Space uses, clicks Remove, types "Client" and clicks Delete
- **THEN** "Client" leaves the list and every profile menu, and its data folder is deleted

#### Scenario: Wrong name
- **WHEN** the user types "client 2" in the dialog for "Client"
- **THEN** "Delete" stays disabled

### Requirement: Download location
The selected profile's settings SHALL have a "Download location" popup, as in Arc. Closed, it SHALL show the folder the profile's downloads are saved to, or "Ask every time". Its menu SHALL offer that folder, "Other…", which chooses another folder with macOS's folder picker, and, after a divider, "Ask every time", which makes each download ask where to save. Choosing the folder or "Other…" SHALL turn asking off. The choice SHALL apply to that profile only, and to its next download.

#### Scenario: Default
- **WHEN** the user opens the popup for a profile that never changed it
- **THEN** it shows "Downloads" checked, "Other…", a divider and "Ask every time"

#### Scenario: Changing the folder
- **WHEN** the user chooses "Other…" for "Work", picks "Documents", and downloads a file in a Space using "Work"
- **THEN** the popup shows "Documents", the file is saved there, and downloads in other profiles still go to their own folders

#### Scenario: Asking every time
- **WHEN** the user chooses "Ask every time" for "Work" and downloads a file in a Space using "Work"
- **THEN** Clair asks where to save the file, and downloads in other profiles don't ask

#### Scenario: Back to a folder
- **WHEN** "Ask every time" is chosen and the user chooses the folder in the menu
- **THEN** the next download is saved to that folder without asking

### Requirement: Links to a profile's Chromium settings
Below Download location, one group SHALL hold the rows Search Engine, Privacy and Security, Notifications and Clear Browsing Data, in that order. Choosing a row SHALL close the Settings window and open Chromium's page for it (`chrome://settings/search`, `/privacy`, `/content/notifications` and `/clearBrowserData`) in a new tab of a Space using the selected profile. The rows SHALL be disabled, with a note saying why, for a profile that no Space uses.

#### Scenario: Search engine of another profile
- **WHEN** the front window shows a Space using the default profile, and the user selects "Work" and chooses Search Engine
- **THEN** Settings closes, and a window shows a Space using "Work" with a new tab on `chrome://settings/search`

#### Scenario: No browser window open
- **WHEN** no browser window is open and the user chooses Privacy and Security for the default profile
- **THEN** a new window opens on a Space using the default profile, showing `chrome://settings/privacy`

#### Scenario: Profile without a Space
- **WHEN** the user selects a profile that no Space uses
- **THEN** the four rows are disabled, and a note says to use the profile in a Space first
