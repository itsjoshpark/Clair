# Spec Delta

## ADDED Requirements

### Requirement: Warn before quitting toggle
The Advanced page SHALL have a toggle labelled "Warn before quitting" that shows and changes Chromium's warn-before-quitting setting, which makes Cmd+Q quit only when held. It SHALL be on when the user never changed it, as in Chromium, and a change SHALL apply at once. The menu bar SHALL NOT have Chromium's own "Warn Before Quitting" item, which the toggle replaces.

#### Scenario: On
- **WHEN** the toggle is on and the user presses Cmd+Q briefly
- **THEN** Clair shows "Hold ⌘Q to Quit" and keeps running

#### Scenario: Off
- **WHEN** the user turns the toggle off and presses Cmd+Q
- **THEN** Clair quits at once

#### Scenario: Menu bar
- **WHEN** the user opens the Clair menu
- **THEN** it has no "Warn Before Quitting" item

### Requirement: Restore windows toggle
The Advanced page SHALL have a toggle labelled "When opening Clair, restore windows from previous session", as Arc's has, that shows and changes whether Clair reopens the previous session's windows at launch (`browser-window`, "Windows restored at launch"). It SHALL be off when no value is stored, and a change SHALL apply from the next launch.

#### Scenario: Default
- **WHEN** Clair has no stored value for the preference and the user opens the Advanced page
- **THEN** the toggle is off

#### Scenario: Turning it on
- **WHEN** the user turns the toggle on, quits with two windows open and relaunches
- **THEN** both windows reopen

## MODIFIED Requirements

### Requirement: Settings pages
The Settings window SHALL show a toolbar of pages, General, Profiles, Links and Advanced in that order, with each page's rows grouped in rounded cards. Choosing a toolbar item SHALL show that page in place of the current one, and the window's title SHALL be the shown page's name. The window SHALL open on General the first time, and afterwards on the page last shown, across launches.

#### Scenario: First opening
- **WHEN** the user opens Settings for the first time
- **THEN** the window shows the General page, titled "General", with toolbar items General, Profiles, Links and Advanced

#### Scenario: Switching pages
- **WHEN** the Settings window shows General and the user chooses Advanced in the toolbar
- **THEN** the window shows the Advanced page in place of General, and its title becomes "Advanced"

#### Scenario: Last page remembered
- **WHEN** the user leaves the Settings window on Advanced, quits Clair, relaunches it and opens Settings
- **THEN** the window shows the Advanced page

#### Scenario: Profiles page
- **WHEN** the user chooses Profiles in the toolbar
- **THEN** the window shows the Profiles page, wider than the other pages, and its title becomes "Profiles"
