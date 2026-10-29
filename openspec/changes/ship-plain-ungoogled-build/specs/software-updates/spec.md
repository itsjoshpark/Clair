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

### Requirement: Update ready indicator in the application menu
While a downloaded update is waiting to be installed, the Clair application menu SHALL contain an "Install Update and Relaunch" item, which installs the update and relaunches immediately. Status SHALL NOT appear on the About settings page.

#### Scenario: Update ready
- **WHEN** an update has finished downloading
- **THEN** the Clair menu shows "Install Update and Relaunch", and choosing it installs the update and relaunches Clair

#### Scenario: No update waiting
- **WHEN** no downloaded update is waiting
- **THEN** the Clair menu has no "Install Update and Relaunch" item

### Requirement: Manual update check
The Clair application menu SHALL contain a "Check for Updates…" item that checks the appcast immediately and reports the result in a small alert. When a newer release is available, the alert SHALL show its version and offer "Install and Relaunch" and "Later".

#### Scenario: Already up to date
- **WHEN** a user chooses "Check for Updates…" while running the newest compatible release in the appcast
- **THEN** an alert says Clair is up to date and shows the running version

#### Scenario: Update available after a manual check
- **WHEN** a user chooses "Check for Updates…" and the appcast lists a newer compatible release
- **THEN** Clair downloads it, and an alert shows the new version with "Install and Relaunch" and "Later"

#### Scenario: Choosing Later
- **WHEN** the user chooses "Later" in that alert
- **THEN** the update stays downloaded, the Clair menu shows "Install Update and Relaunch", and the update installs on quit

#### Scenario: Check fails
- **WHEN** a user chooses "Check for Updates…" and the appcast cannot be reached
- **THEN** an alert says the check failed, and nothing changes

### Requirement: Update signature verification
Clair SHALL install an update only if its EdDSA signature verifies against the Sparkle public key embedded in the running app. The new app SHALL also carry a valid Developer ID signature from the same Apple team as the running app. An update failing either check MUST be rejected and left uninstalled.

#### Scenario: Tampered update is rejected
- **WHEN** a downloaded update's file does not match its EdDSA signature in the appcast
- **THEN** Clair refuses to install it, offers no "Install Update and Relaunch" item for it, and keeps running the current version unchanged

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
When Clair relaunches through "Install and Relaunch" or "Install Update and Relaunch", it SHALL restore the windows and tabs that were open before the relaunch, whatever the user's startup setting. It SHALL warn first if quitting would lose an active download or incognito windows.

#### Scenario: Install and relaunch
- **WHEN** a user chooses "Install Update and Relaunch" while three windows with open tabs exist
- **THEN** Clair quits, installs the update, and relaunches with the same three windows and their tabs restored

#### Scenario: Active download on relaunch
- **WHEN** a user chooses "Install Update and Relaunch" while a download is in progress
- **THEN** Clair warns that relaunching will cancel the download, and lets the user postpone the update
