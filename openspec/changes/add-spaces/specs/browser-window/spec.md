# Spec Delta

## ADDED Requirements

### Requirement: Tabs restored at launch
When Clair launches, it SHALL reopen the tabs that were open when it quit, as Arc does, unless the user chose otherwise in Chromium's "On startup" setting. This SHALL hold for a new profile without any setting being changed. Incognito tabs SHALL NOT come back.

#### Scenario: Quit and relaunch
- **WHEN** a user who never changed a setting quits Clair with several tabs open and launches it again
- **THEN** those tabs are open again

#### Scenario: The user chose a new tab page
- **WHEN** the user set "On startup" to "Open the New Tab page" in `chrome://settings`, quits and relaunches
- **THEN** Clair opens one window on a new tab page

#### Scenario: After a crash
- **WHEN** Clair crashes with tabs open and is launched again
- **THEN** the tabs reopen
