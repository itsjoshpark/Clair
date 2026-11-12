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

### Requirement: Showing a Space takes a tab from another window
When a window switches to a Space, it SHALL show the tab last active in that Space in this window; otherwise the Space's most recently active tab that no window is showing; otherwise a new tab page with the command bar open.

#### Scenario: The Space's tabs are elsewhere
- **WHEN** "Work" has two tabs, both opened in window A and neither showing there, and the user switches window B to "Work"
- **THEN** B shows the more recently active of the two

#### Scenario: Every tab is showing elsewhere
- **WHEN** the only tab of "Work" is showing in window A, and the user switches window B to "Work"
- **THEN** B shows a new tab page in "Work", and A is unchanged

### Requirement: The next tab after a close can come from another window
The tab chosen after a close SHALL be chosen from the whole list the sidebar shows. A tab that another window shows SHALL NOT be skipped: this window shows it, and the other window shows its still.

#### Scenario: The row above lives in another window
- **WHEN** the row above the closed tab was opened in another window and isn't showing there
- **THEN** this window shows it

#### Scenario: The next tab is showing in another window
- **WHEN** the row above the closed tab is showing in another window
- **THEN** this window shows it, and the other window shows its still

### Requirement: Tab commands act on the shared list
Cmd+1 to Cmd+9, Next Tab, Previous Tab, Ctrl+Tab and Close Tabs Below SHALL act on the rows the sidebar lists, whichever window holds them.

#### Scenario: Cmd+number on a tab from another window
- **WHEN** a window shows "Work", whose rows are X, Y and Z, and Y was opened in another window
- **THEN** Cmd+2 shows Y in this window

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
