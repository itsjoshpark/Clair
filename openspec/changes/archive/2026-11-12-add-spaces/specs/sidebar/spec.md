# Spec Delta

## MODIFIED Requirements

### Requirement: Sidebar footer
The sidebar SHALL end in a footer at its bottom edge, as in Arc, however short the tab list is: the downloads button at its leading end, the Space switcher in the middle and a plus button at its trailing end. The switcher SHALL show one item per Space, in order, with the current Space's item darker than the others, and SHALL be absent while there is one Space or the window is incognito or guest. Clicking an item SHALL switch the window to that Space. The plus button SHALL open a menu offering New Space… and New Tab with its shortcut, which opens the command bar as Cmd+T does. While the tab list scrolls, a thin line SHALL separate it from the footer.

#### Scenario: Plus menu
- **WHEN** the user clicks the footer's plus button
- **THEN** a menu shows New Space… and New Tab with ⌘T, and choosing New Tab opens the command bar for a new tab

#### Scenario: Line above the footer
- **WHEN** the window has more tabs than the list can show
- **THEN** a line shows between the list and the footer, and it goes once tabs are closed until the rest fit

#### Scenario: Switcher with two Spaces
- **WHEN** there are two Spaces and the window shows the first
- **THEN** the footer shows two items between the downloads button and the plus, the first darker

#### Scenario: One Space
- **WHEN** there is one Space
- **THEN** the footer shows no switcher

### Requirement: Tab list
Below the URL field and the Space header, the sidebar SHALL show a "New Tab" row and then every tab of the window that belongs to the Space it shows, in the Space's tab order, with its favicon and title. The active tab SHALL be highlighted, more lightly while the window isn't key. A tab that plays sound or is muted SHALL show a speaker between its favicon and title, as in Arc, that mutes or unmutes it, with the tooltip "Mute this tab" or "Unmute this tab". The list SHALL scroll when it doesn't fit.

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
