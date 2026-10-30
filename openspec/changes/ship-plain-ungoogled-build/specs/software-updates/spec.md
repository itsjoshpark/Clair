# Spec Delta

## Purpose

Defines how an installed copy of Clair finds, verifies, downloads and installs newer Clair releases. Users stay on current engine security fixes without reinstalling by hand.

## ADDED Requirements

### Requirement: Update feed location
Clair SHALL check for updates against the appcast at `https://github.com/itsjoshpark/Clair/raw/main/.sparkle/appcast.xml`, and against no other update source.

#### Scenario: Update check request
- **WHEN** Clair checks for updates
- **THEN** it fetches the appcast from `https://github.com/itsjoshpark/Clair/raw/main/.sparkle/appcast.xml` and makes no request to Google's or Chromium's update services

### Requirement: Automatic background updates
Clair SHALL check for updates automatically at least once every 24 hours while running, without asking permission first. When an update is found, Clair SHALL download it in the background without showing any window. Clair SHALL provide no settings UI for update behavior.

#### Scenario: Fresh install checks automatically
- **WHEN** a newly installed Clair has been running for 24 hours
- **THEN** it has checked the appcast at least once without the user asking it to

#### Scenario: Update found in the background
- **WHEN** an automatic check finds a newer compatible release
- **THEN** Clair downloads it without showing a dialog or interrupting browsing

### Requirement: Downloaded update installs on quit
A downloaded update SHALL be installed the next time the user quits Clair. The user's next launch then runs the new version, with no other action needed.

#### Scenario: Quit with an update ready
- **WHEN** an update has finished downloading and the user quits Clair
- **THEN** the update is installed, and the next launch of Clair runs the new version

### Requirement: Downloaded update installs while the user is idle
While a downloaded update is waiting, Clair SHALL install it and relaunch on its own once the Mac has received no keyboard, mouse or trackpad input for 30 minutes. It SHALL NOT do so while a download is in progress, an incognito window is open, or a tab is playing audio or using the camera, microphone or screen; it SHALL try again at the next idle period. If Clair was not the active app, the relaunched Clair SHALL stay in the background.

#### Scenario: User away with an update ready
- **WHEN** an update is waiting and the Mac has had no input for 30 minutes
- **THEN** Clair installs the update, relaunches with its windows and tabs restored, and runs the new version

#### Scenario: Something would be interrupted
- **WHEN** an update is waiting and the Mac has had no input for 30 minutes, but a download is in progress, an incognito window is open, or a tab is playing audio or using the camera, microphone or screen
- **THEN** Clair does not install the update, and installs it at a later idle period once none of these holds

#### Scenario: Clair in the background
- **WHEN** Clair installs an update while idle and another app was active
- **THEN** the relaunched Clair does not become the active app

### Requirement: Update ready indicator in the application menu
The Clair application menu SHALL contain one update item. While a downloaded update is waiting to be installed, that item SHALL read "Update Available…" and carry a "1 update" badge, in place of "Check for Updates…". Choosing it SHALL show an alert with the new version and "Restart and Update" and "Later". Clair SHALL add no other update item to the menu. Status SHALL NOT appear on the About settings page.

#### Scenario: Update ready
- **WHEN** an update has finished downloading
- **THEN** the Clair menu's update item reads "Update Available…" with a "1 update" badge, and the menu has no "Check for Updates…" item

#### Scenario: Choosing Update Available
- **WHEN** the user chooses "Update Available…"
- **THEN** an alert shows the new version with "Restart and Update" and "Later", and "Restart and Update" installs the update and relaunches Clair

#### Scenario: No update waiting
- **WHEN** no downloaded update is waiting
- **THEN** the Clair menu's update item reads "Check for Updates…" with no badge

### Requirement: Manual update check
While no downloaded update is waiting, the Clair application menu's update item SHALL read "Check for Updates…". It SHALL check the appcast immediately and report the result in a small alert. When a newer release is available, the alert SHALL show its version and offer "Restart and Update" and "Later".

#### Scenario: Already up to date
- **WHEN** a user chooses "Check for Updates…" while running the newest compatible release in the appcast
- **THEN** an alert says Clair is up to date and shows the running version

#### Scenario: Update available after a manual check
- **WHEN** a user chooses "Check for Updates…" and the appcast lists a newer compatible release
- **THEN** Clair downloads it, and an alert shows the new version with "Restart and Update" and "Later"

#### Scenario: Choosing Later
- **WHEN** the user chooses "Later" in that alert
- **THEN** the update stays downloaded, the Clair menu's update item reads "Update Available…", and the update installs on quit or while the user is idle

#### Scenario: Check fails
- **WHEN** a user chooses "Check for Updates…" and the appcast cannot be reached
- **THEN** an alert says the check failed, and nothing changes

### Requirement: Update signature verification
Clair SHALL install an update only if its EdDSA signature verifies against the Sparkle public key embedded in the running app. The new app SHALL also carry a valid Developer ID signature from the same Apple team as the running app. An update failing either check MUST be rejected and left uninstalled.

#### Scenario: Tampered update is rejected
- **WHEN** a downloaded update's file does not match its EdDSA signature in the appcast
- **THEN** Clair refuses to install it, the Clair menu doesn't show "Update Available…" for it, and Clair keeps running the current version unchanged

#### Scenario: Valid update is installed
- **WHEN** a downloaded update's EdDSA signature verifies and its app is signed by the same Developer ID team
- **THEN** Clair installs it

### Requirement: Only newer, compatible releases are offered
Clair SHALL offer only releases whose build number is higher than the running build, and whose minimum macOS version is no higher than the running macOS version.

#### Scenario: Older or equal build is not offered
- **WHEN** the newest appcast item's build number is equal to or lower than the running build
- **THEN** Clair downloads nothing, and a manual check reports that Clair is up to date

#### Scenario: Release needs a newer macOS
- **WHEN** the newest appcast item declares a minimum macOS version higher than the running macOS
- **THEN** Clair does not offer that release

### Requirement: Delta updates with full-update fallback
When the appcast provides a delta for the running build, Clair SHALL download the delta instead of the full release. If no delta matches, or applying it fails, Clair SHALL use the full release.

#### Scenario: Delta available
- **WHEN** the newest release includes a delta for the running build number
- **THEN** Clair downloads only the delta and installs the new release from it

#### Scenario: Delta fails to apply
- **WHEN** applying a downloaded delta fails, for example because the installed app was modified
- **THEN** Clair downloads the full release and installs that instead

### Requirement: Relaunch preserves the browsing session
When Clair relaunches to install an update, through "Restart and Update" or while the user is idle, it SHALL restore the windows and tabs that were open before the relaunch, whatever the user's startup setting. After "Restart and Update", it SHALL warn first if quitting would lose an active download or incognito windows. An idle install never needs that warning, because it doesn't run in those cases.

#### Scenario: Restart and update
- **WHEN** a user chooses "Restart and Update" while three windows with open tabs exist
- **THEN** Clair quits, installs the update, and relaunches with the same three windows and their tabs restored

#### Scenario: Active download on relaunch
- **WHEN** a user chooses "Restart and Update" while a download is in progress
- **THEN** Clair warns that relaunching will cancel the download, and lets the user postpone the update
