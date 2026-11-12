# Spec Delta

## ADDED Requirements

### Requirement: Windows and tabs restored at launch
When Clair launches, it SHALL reopen the windows and tabs that were open when it quit, as Arc does, unless the user chose otherwise in Chromium's "On startup" setting. This SHALL hold for a new profile without any setting being changed. Incognito windows SHALL NOT come back.

#### Scenario: Quit and relaunch
- **WHEN** a user who never changed a setting quits Clair with two windows open, each with several tabs, and launches it again
- **THEN** both windows reopen with their tabs

#### Scenario: The user chose a new tab page
- **WHEN** the user set "On startup" to "Open the New Tab page" in `chrome://settings`, quits and relaunches
- **THEN** Clair opens one window on a new tab page

#### Scenario: After a crash
- **WHEN** Clair crashes with tabs open and is launched again
- **THEN** the tabs reopen
