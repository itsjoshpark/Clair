# Spec Delta

## ADDED Requirements

### Requirement: One tab list for every window
Every window showing a Space SHALL list the same tabs for it, in the same order, whichever window they were opened in. A change made in one window, such as opening, closing or reordering a tab, SHALL show in the others at once.

#### Scenario: Two windows on one Space
- **WHEN** two windows show "Home" and the user opens a tab in the first
- **THEN** the second window's sidebar lists the new tab at the top too

#### Scenario: Reordering
- **WHEN** the user drags a tab to the bottom of the list in one window
- **THEN** it is at the bottom of the list in the other window

#### Scenario: New window
- **WHEN** the user presses Cmd+N in a window showing "Work", which has three tabs
- **THEN** the new window shows a new tab page, and its sidebar lists that tab and the three others

### Requirement: A tab shows in one window at a time
Selecting a tab that another window shows SHALL show its live page in this window, without reloading it. The other window SHALL keep the tab's row highlighted and show a dimmed still of the page as it was at that moment, with an empty URL field and with back, forward and reload disabled. Focusing that window SHALL bring the live page back to it and leave the still in the window it came from.

#### Scenario: Taking a tab
- **WHEN** window A shows the tab "Docs" and the user selects "Docs" in window B
- **THEN** B shows the live page, and A shows a dimmed still of it with "Docs" still highlighted

#### Scenario: Taking it back
- **WHEN** the user then clicks anywhere in window A
- **THEN** A shows the live page and B shows the dimmed still

#### Scenario: The still doesn't update
- **WHEN** the page changes while window A shows its still
- **THEN** A's still stays as it was

#### Scenario: A tab no window shows
- **WHEN** the user selects a tab that was opened in another window and isn't showing there
- **THEN** this window shows its page as it was, and the other window is unchanged

### Requirement: A window that loses its tab shows a new tab page
When the tab a window shows a still of is closed, the window SHALL show a new tab page in the Space it shows, with the command bar open. When the user selects another tab or Space in a window showing a still, the still SHALL go.

#### Scenario: The still's tab closes
- **WHEN** window A shows a still of "Docs" and the user closes "Docs" in window B
- **THEN** A shows a new tab page with the command bar open

#### Scenario: Moving on
- **WHEN** window A shows a still of "Docs" and the user selects another tab in A
- **THEN** A shows that tab's page, and "Docs" stays live in window B

### Requirement: Closing a window keeps its tabs
Closing a window while another window that isn't incognito or guest is open SHALL keep its tabs, which stay listed in their Spaces in the remaining windows. Closing the last such window SHALL close its tabs, each with its usual leave-page confirmation.

#### Scenario: Another window is open
- **WHEN** two windows are open and the user closes the one showing the tab "Docs"
- **THEN** "Docs" is still listed in the other window, and selecting it shows the page without reloading it

#### Scenario: The last window
- **WHEN** one window is open and the user closes it
- **THEN** its tabs close, and Reopen Closed Window brings them back

### Requirement: A Peek closes when its tab moves
When a tab with a Peek moves to another window, by being selected there or because its window closed, its Peek SHALL close.

#### Scenario: Tab with a Peek taken by another window
- **WHEN** window A shows a tab with a Peek and the user selects that tab in window B
- **THEN** B shows the tab without a Peek

### Requirement: Stills end with the session
After a relaunch with session restore, no window SHALL show a still, and no tab SHALL be listed twice.

#### Scenario: Relaunch with a still showing
- **WHEN** the user quits while a window shows a still of a tab, and relaunches
- **THEN** that window shows a new tab page, and the tab is listed once

## MODIFIED Requirements

### Requirement: Showing a Space that has no tab here
A window SHALL always show a tab. When it switches to a Space, it SHALL show the tab last active in that Space in this window, unless another window shows it; otherwise the Space's most recently active tab that no window is showing, whichever window it was opened in; otherwise a new tab page in that Space, with the command bar open. A new window SHALL show the Space of the window it was opened from, or the Space last shown when no window is open, on a new tab page with the command bar open.

#### Scenario: Empty Space
- **WHEN** the user switches to a Space that has no tabs
- **THEN** the window shows a new tab page in that Space, with the command bar open

#### Scenario: New window
- **WHEN** the user presses Cmd+N in a window showing "Work"
- **THEN** a new window shows "Work" with a new tab page and the command bar open

#### Scenario: The Space's tabs are elsewhere
- **WHEN** "Work" has two tabs, both opened in window A and neither showing there, and the user switches window B to "Work"
- **THEN** B shows the more recently active of the two

#### Scenario: Every tab is showing elsewhere
- **WHEN** the only tab of "Work" is showing in window A, and the user switches window B to "Work"
- **THEN** B shows a new tab page in "Work", and A is unchanged

### Requirement: Tab chosen after a close
When the user closes the active tab, the window SHALL show, in order: the tab the user selected it from, if that tab is still listed in the Space; otherwise the row above it; otherwise the row below it. The tab SHALL be chosen from the whole list the sidebar shows. A tab that another window shows SHALL NOT be skipped: this window shows it, and the other window shows its still. When the Space has no other tab, the window SHALL show a tab of another Space that no window is showing, switching to that Space, or close if there is none.

#### Scenario: Back to where the user came from
- **WHEN** the rows are E, D, C, B, A, and the user selects A, then C, then closes C
- **THEN** A is active

#### Scenario: The row above
- **WHEN** a close has just made E active in the rows F, E, B, and the user closes E
- **THEN** F, the row above, is active

#### Scenario: The top row
- **WHEN** the top row is active, wasn't selected from another tab, and the user closes it
- **THEN** the row below is active

#### Scenario: The Space's last tab
- **WHEN** the user closes the only tab of "Work" while "Home" has a tab that no window is showing
- **THEN** the window shows "Home"

#### Scenario: Staying on a page that asks
- **WHEN** the user closes the active tab, its page asks whether to leave, and the user cancels
- **THEN** the tab stays active, and closing it again still returns to the tab the user selected it from

#### Scenario: Leaving a page that asks
- **WHEN** the rows are B, P, A, the user selects A, then P, closes P, and confirms leaving its page
- **THEN** A is active, and the window shows the same Space

#### Scenario: The row above lives in another window
- **WHEN** the user closes the active tab, and the row above it was opened in another window and isn't showing there
- **THEN** this window shows the row above

#### Scenario: The next tab is showing in another window
- **WHEN** the user closes the active tab, and the row above it is showing in another window
- **THEN** this window shows the row above, and the other window shows its still

### Requirement: Tab commands follow the Space
Tabs › Next Tab (Opt+Cmd+Down), Previous Tab (Opt+Cmd+Up), Ctrl+Tab, Cmd+1 to Cmd+9 and Close Tabs Below SHALL act on the rows the sidebar lists, in its order, whichever window holds them, and never on a tab of another Space. Ctrl+Shift+PageDown and Ctrl+Shift+PageUp SHALL move the active row one row down or up in the list, stopping at its ends.

#### Scenario: Moving a row with the keyboard
- **WHEN** a window shows "Work", whose rows are X, Y and Z, Z is active, and the user presses Ctrl+Shift+PageUp
- **THEN** the rows are X, Z and Y, and Z is still active

#### Scenario: Cmd+number
- **WHEN** a window shows "Work", whose rows are X, Y and Z, and the user presses Cmd+2
- **THEN** Y is active

#### Scenario: Next tab at the Space's end
- **WHEN** the last row of the Space is active and the user presses Opt+Cmd+Down
- **THEN** the first row of the same Space is active

#### Scenario: Cmd+number on a tab from another window
- **WHEN** a window shows "Work", whose rows are X, Y and Z, Y was opened in another window, and the user presses Cmd+2
- **THEN** this window shows Y
