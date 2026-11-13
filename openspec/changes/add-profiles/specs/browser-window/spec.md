# Spec Delta

## ADDED Requirements

### Requirement: Windows restored at launch
With "When opening Clair, restore windows from previous session" (`settings-window`) off, as it is by default and in Arc, Clair SHALL launch with one window, showing the Space last shown, on a new tab page with the command bar open. With it on, Clair SHALL reopen each window that was open, showing the Space and the tab it showed. Either way the tabs come back in their Spaces, and incognito and guest windows SHALL NOT come back.

#### Scenario: Off, two windows
- **WHEN** the setting is off, and the user quits with one window showing "Work" and, last active, another showing "Travel", and relaunches
- **THEN** one window opens, showing "Travel" on a new tab page with the command bar open, and "Work" and "Travel" list the tabs they had

#### Scenario: On, two windows
- **WHEN** the setting is on, and the user quits with one window showing the tab "Docs" in "Work" and another showing "Maps" in "Travel", and relaunches
- **THEN** two windows open, one showing "Docs" in "Work" and the other "Maps" in "Travel"

#### Scenario: Never changed
- **WHEN** a user who never changed the setting quits with three windows open and relaunches
- **THEN** one window opens

### Requirement: New tab pages aren't restored
A tab showing the new tab page when Clair quits SHALL NOT come back at the next launch, so the new tab page a launch opens is the only one it adds. A restored window that showed one SHALL show a new tab page in its Space, and a window that held nothing else SHALL NOT come back.

#### Scenario: Two launches
- **WHEN** restoring windows is off, and the user launches Clair, quits without using the new tab page it opened, and launches again
- **THEN** the Space lists one new tab page, not two

#### Scenario: New tab pages left around
- **WHEN** the user quits with the tabs "Docs" and "Maps" and two new tab pages in "Work", and relaunches
- **THEN** "Work" lists "Docs" and "Maps", and no new tab page from before

#### Scenario: A restored window on a new tab page
- **WHEN** restoring windows is on, and the user quits with a window showing a new tab page in "Work", which also lists "Docs", and relaunches
- **THEN** the window comes back showing "Work" on a new tab page, and "Work" lists that page and "Docs"

## MODIFIED Requirements

### Requirement: Window size and placement restored
A window restored at launch SHALL have the size, position, minimized and full-screen state Chromium's session restore records, as Chromium's window would. With restoring windows off, the one window SHALL have those of the window that was last active.

#### Scenario: Relaunch with two windows
- **WHEN** restoring windows is on, and Clair relaunches after two native windows were open at different sizes
- **THEN** both windows reopen at their previous sizes and positions with their tabs

#### Scenario: Relaunch into one window
- **WHEN** it is off, and Clair relaunches after two native windows were open at different sizes
- **THEN** one window opens, at the size and position of the one that was last active
