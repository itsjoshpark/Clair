# Spec Delta

## ADDED Requirements

### Requirement: Sidebar footer
The sidebar SHALL end in a footer at its bottom edge, as in Arc, however short the tab list is: the downloads button at its leading end and a plus button at its trailing end. The plus button SHALL open a menu offering New Tab with its shortcut, which opens the command bar as Cmd+T does. While the tab list scrolls, a thin line SHALL separate it from the footer.

#### Scenario: Plus menu
- **WHEN** the user clicks the footer's plus button
- **THEN** a menu shows New Tab with ⌘T, and choosing it opens the command bar for a new tab

#### Scenario: Line above the footer
- **WHEN** the window has more tabs than the list can show
- **THEN** a line shows between the list and the footer, and it goes once tabs are closed until the rest fit

## MODIFIED Requirements

### Requirement: Downloads indicator
The sidebar SHALL always show a downloads button in its footer, where Arc has its library button. It SHALL mark finished downloads the user hasn't looked at. Clicking it SHALL open a list of recent downloads that can open, reveal in Finder, cancel or retry each one, and open `chrome://downloads`; with no downloads from this session, the list SHALL say so.

#### Scenario: Opening a finished download
- **WHEN** the user opens the downloads list and clicks a finished download
- **THEN** the file opens in its default app, and the button stops marking unseen downloads

#### Scenario: No downloads yet
- **WHEN** the user opens the downloads list before downloading anything in this session
- **THEN** the list says there are no recent downloads and still offers to show all downloads

### Requirement: Tab list
Below the URL field, the sidebar SHALL show a "New Tab" row and then every tab of the window, in the window's tab order, with its favicon and title. The active tab SHALL be highlighted, more lightly while the window isn't key. A tab that plays sound or is muted SHALL show a speaker between its favicon and title, as in Arc, that mutes or unmutes it, with the tooltip "Mute this tab" or "Unmute this tab". The list SHALL scroll when it doesn't fit.

#### Scenario: Selecting a tab
- **WHEN** the user clicks a tab row
- **THEN** that tab becomes active and its row is highlighted

#### Scenario: Muting a tab
- **WHEN** a tab plays sound and the user clicks its speaker
- **THEN** the tab is muted and its speaker shows as muted

#### Scenario: Many tabs
- **WHEN** the window has more tabs than the sidebar can show
- **THEN** the tab list scrolls, and the top row, URL field and footer stay in place
