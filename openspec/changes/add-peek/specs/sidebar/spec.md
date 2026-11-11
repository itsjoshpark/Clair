# Spec Delta

## MODIFIED Requirements

### Requirement: Tab list
Below the URL field, the sidebar SHALL show a "New Tab" row and then every tab of the window, in the window's tab order, with its favicon and title. The active tab SHALL be highlighted, more lightly while the window isn't key. A tab that plays sound or is muted SHALL show a speaker between its favicon and title, as in Arc, that mutes or unmutes it, with the tooltip "Mute this tab" or "Unmute this tab". The list SHALL scroll when it doesn't fit. A Peek SHALL NOT have a row of its own: its parent tab's row SHALL show the Peek page's favicon as a small badge at its trailing end, and SHALL be highlighted while the Peek shows. Clicking that row SHALL show the tab with its Peek.

#### Scenario: Selecting a tab
- **WHEN** the user clicks a tab row
- **THEN** that tab becomes active and its row is highlighted

#### Scenario: Muting a tab
- **WHEN** a tab plays sound and the user clicks its speaker
- **THEN** the tab is muted and its speaker shows as muted

#### Scenario: Many tabs
- **WHEN** the window has more tabs than the sidebar can show
- **THEN** the tab list scrolls, and the top row, URL field and footer stay in place

#### Scenario: Tab with a Peek
- **WHEN** a tab has a Peek open
- **THEN** the tab list has no row for the Peek, and the tab's row shows the Peek page's favicon as a badge

#### Scenario: Returning to a tab with a Peek
- **WHEN** the user selects another tab and then clicks the row of a tab with a Peek
- **THEN** that row is highlighted and the card shows the tab's page with its Peek

### Requirement: New tabs at the top
Every new tab SHALL be inserted at the top of the tab list, directly under the "New Tab" row, whether it comes from Cmd+T, the "New Tab" row, the command bar, a link opened in a new tab, or an extension or page that doesn't ask for a position. Whether it becomes active SHALL follow Chromium, so a link opened in the background stays in the background. Tabs that come back through session restore or Reopen Closed Tab SHALL return to their previous positions. A Peek expanded into a tab SHALL be the exception: it SHALL be inserted directly below its parent tab.

#### Scenario: Command bar tab
- **WHEN** the user opens a URL from the command bar with Cmd+T
- **THEN** the new tab is first in the list and active

#### Scenario: Link opened in a new tab
- **WHEN** the user Cmd-clicks a link in the third tab of five
- **THEN** the new tab is first in the list, and the third tab stays active

#### Scenario: Expanded Peek
- **WHEN** the user expands a Peek open on the third tab of five
- **THEN** the new tab is fourth in the list, directly below the third, and active

### Requirement: Closing, reordering and tab menu
Hovering a tab row SHALL show a close button, as large as Arc's, which highlights under the pointer. Clicking it, or middle-clicking the row, SHALL close the tab. Tabs SHALL be reorderable by dragging. A row's context menu SHALL offer Copy Link, Duplicate, Mute or Unmute, Close Tab and Close Tabs Below, and opening it SHALL draw no selection ring around the row. A row's actions SHALL apply to the tab, not its Peek: closing the tab SHALL close its Peek too, moving it SHALL keep its Peek with it, and Copy Link and Duplicate SHALL use the tab's own page.

#### Scenario: Reordering
- **WHEN** the user drags the third tab above the first
- **THEN** it becomes the first tab, and Cmd+1 selects it

#### Scenario: Close Tabs Below
- **WHEN** the user chooses Close Tabs Below on the second of five tabs
- **THEN** the third to fifth tabs close, each with its usual leave-page confirmation

#### Scenario: Moving a tab with a Peek
- **WHEN** the third tab has a Peek and the user drags it above the first
- **THEN** it becomes the first tab and still has its Peek

#### Scenario: Copy Link on a tab with a Peek
- **WHEN** the user chooses Copy Link on the row of a tab with a Peek
- **THEN** the tab's own URL is copied, not the Peek's
