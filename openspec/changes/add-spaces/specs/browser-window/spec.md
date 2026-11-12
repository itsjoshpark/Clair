# Spec Delta

## ADDED Requirements

### Requirement: Tabs restored at launch
When Clair launches, it SHALL reopen the tabs that were open when it quit, as Arc does, unless the user chose otherwise in Chromium's "On startup" setting. This SHALL hold for a new profile without any setting being changed. The tabs SHALL come back in one window, whichever windows they were in: Clair SHALL NOT reopen the other windows. Incognito tabs SHALL NOT come back.

#### Scenario: Quit and relaunch
- **WHEN** a user who never changed a setting quits Clair with several tabs open and launches it again
- **THEN** a window opens with those tabs

#### Scenario: Two windows
- **WHEN** the user quits with two windows open, each with three tabs, and relaunches
- **THEN** one window opens, and it has all six tabs

#### Scenario: The user chose a new tab page
- **WHEN** the user set "On startup" to "Open the New Tab page" in `chrome://settings`, quits and relaunches
- **THEN** Clair opens one window on a new tab page

#### Scenario: After a crash
- **WHEN** Clair crashes with tabs open and is launched again
- **THEN** the tabs reopen

## MODIFIED Requirements

### Requirement: Window size and placement restored
The window that opens at launch SHALL be restored with the size, position, minimized and full-screen state Chromium's session restore records for the window that was last active, as Chromium's window would be.

#### Scenario: Relaunch with two windows
- **WHEN** Clair relaunches after two native windows were open at different sizes
- **THEN** one window opens, at the size and position of the one that was last active
