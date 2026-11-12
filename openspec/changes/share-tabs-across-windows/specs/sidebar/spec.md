# Spec Delta

## MODIFIED Requirements

### Requirement: Tab list
Below the URL field and the Space header, the sidebar SHALL show a "New Tab" row and then every tab of the Space the window shows, from every window, in the Space's tab order, with its favicon and title. The active tab SHALL be highlighted, more lightly while the window isn't key. A tab that plays sound or is muted SHALL show a speaker between its favicon and title, as in Arc, that mutes or unmutes it, with the tooltip "Mute this tab" or "Unmute this tab". The list SHALL scroll when it doesn't fit.

#### Scenario: Selecting a tab
- **WHEN** the user clicks a tab row
- **THEN** that tab becomes active and its row is highlighted

#### Scenario: Muting a tab
- **WHEN** a tab plays sound and the user clicks its speaker
- **THEN** the tab is muted and its speaker shows as muted

#### Scenario: Many tabs
- **WHEN** the window has more tabs than the sidebar can show
- **THEN** the tab list scrolls, and the top row, URL field and footer stay in place

#### Scenario: Another Space's tabs
- **WHEN** "Home" has two tabs and "Work" has three, and the window shows "Work"
- **THEN** the list shows the three tabs of "Work" and none of "Home"

#### Scenario: A tab opened in another window
- **WHEN** two windows show "Home" and a tab is opened in the first
- **THEN** the second window's list shows it too
