# Spec Delta

## Purpose

Profiles keep a user's browsing data separate between Spaces, as in Arc. This covers what a profile isolates, the Profiles page in Settings and its actions, and the absence of Chromium's own profile menu and picker.

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
Add, and "New Profile…" wherever profiles are listed, SHALL ask for the new profile's name in a sheet, as in Arc, with "Create Profile" disabled until a name is typed. Creating SHALL add a profile with that name and no Spaces, and select it where it was asked for.

#### Scenario: Adding from Settings
- **WHEN** the user clicks Add, types "Client" and presses Return
- **THEN** "Client" is in the list, selected, with no Space count

#### Scenario: Cancelling
- **WHEN** the user clicks Add and presses Esc
- **THEN** no profile is created

### Requirement: Renaming a profile
Rename SHALL ask for the selected profile's new name in a sheet that says the names of its Spaces won't change. Saving a non-empty name SHALL rename the profile everywhere it is listed, at once, including while windows show its Spaces.

#### Scenario: Renaming the profile in use
- **WHEN** a window shows a Space using "Work", and the user renames "Work" to "Office"
- **THEN** the Profiles list and every Set Profile menu show "Office", the Space keeps its name, and the window keeps showing its page

#### Scenario: Empty name
- **WHEN** the user clears the name in the sheet
- **THEN** "Save" is disabled

### Requirement: Removing a profile
Remove SHALL be enabled only for a profile that no Space uses. It SHALL ask for confirmation in a sheet that says the profile's cookies, history, preferences and logins will be permanently removed, and SHALL enable "Delete" only once the user has typed the profile's name. Confirming SHALL delete the profile and its data.

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
- **WHEN** the user types "client 2" in the sheet for "Client"
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
