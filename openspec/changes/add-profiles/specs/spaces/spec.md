# Spec Delta

## MODIFIED Requirements

### Requirement: Space header
Above the tab list, the sidebar SHALL show the current Space's icon, if it has one, and its name. Right-clicking the header SHALL open a menu offering Change Space Icon…, Rename Space…, Set Profile (`profiles`), Manage Spaces… and Delete Space. An incognito or guest window SHALL show no Space header.

#### Scenario: Header shows the Space
- **WHEN** a window shows the Space "Work", whose icon is 💼
- **THEN** the sidebar shows 💼 and "Work" above the "New Tab" row

#### Scenario: Header menu
- **WHEN** the user right-clicks the header
- **THEN** the menu lists Change Space Icon…, Rename Space…, Set Profile, Manage Spaces… and Delete Space, in that order

#### Scenario: Incognito window
- **WHEN** the user opens an incognito window
- **THEN** its sidebar shows "Incognito" and no Space header or Space switcher

### Requirement: Creating a Space
Spaces › New Space… and the footer's plus menu SHALL replace the sidebar's content with a form, as in Arc: a name field with an icon button, a profile popup (`profiles`), "Create Space" and "Cancel". "Create Space" SHALL be disabled until a name is typed. Creating SHALL add the Space after the last one and show it in the window. Cancel or Esc SHALL return to the Space shown before, creating nothing.

#### Scenario: Creating a Space
- **WHEN** the user opens the form, types "Work" and clicks "Create Space"
- **THEN** a Space "Work" is last in the switcher, and the window shows it with a new tab page

#### Scenario: No name
- **WHEN** the form's name field is empty
- **THEN** "Create Space" is disabled

#### Scenario: Cancelling
- **WHEN** the user types a name and presses Esc
- **THEN** the sidebar shows the earlier Space again and no Space is created

### Requirement: Manage Spaces dialog
Manage Spaces…, in the Spaces menu and the Space header's menu, SHALL open a dialog on the window, with every Space in order on the left, each with its icon, name and number of tabs, and the selected Space's name, icon and profile popup (`profiles`) on the right. It SHALL open with the window's Space selected, and "Done" or Esc SHALL close it.

#### Scenario: Opening
- **WHEN** a window shows "Work" and the user chooses Manage Spaces…
- **THEN** the dialog lists every Space in order with "Work" selected, and shows its name, icon and profile

#### Scenario: Closing
- **WHEN** the user clicks "Done"
- **THEN** the dialog closes and the window shows the Space it showed before, unless that Space was removed

### Requirement: Moving a tab to another Space
With more than one Space, a tab row's context menu SHALL offer "Move to Space" with every other Space. Choosing one SHALL put the tab at the top of that Space's list and remove it from this one, leaving the window on the Space it shows. A tab moved to a Space using the same profile SHALL keep its page as it is; moving to a Space of another profile follows `profiles`.

#### Scenario: Moving a tab
- **WHEN** the user moves a tab with a half-filled form from "Home" to "Research", which uses the same profile
- **THEN** the tab is first in "Research" with the form as it was, and "Home" no longer lists it

#### Scenario: Moving the active tab
- **WHEN** the user moves the active tab to another Space
- **THEN** the window stays on its Space and shows the tab it would show had the moved tab been closed

#### Scenario: One Space
- **WHEN** there is one Space
- **THEN** the tab's menu has no "Move to Space"

### Requirement: Tab chosen after a close
When the user closes the active tab, the window SHALL show, in order: the tab the user selected it from, if it's still listed in the Space; otherwise the row above it; otherwise the row below it, among every row the sidebar lists. A tab another window shows SHALL NOT be skipped: this window shows it, and the other window its still. When the Space has no other tab, the window SHALL stay on the Space, as Arc keeps an empty Space, and show a new tab page in it with the command bar open, using one the Space already lists if the user never navigated it. It SHALL never show a tab of another Space instead. Closing a new tab page that is the Space's only tab SHALL close the window.

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
- **WHEN** the user closes the only tab of "Work" while "Home" has tabs
- **THEN** the window keeps showing "Work", on a new tab page with the command bar open, and no tab of "Home" is shown or moved

#### Scenario: Closing an empty Space's new tab page
- **WHEN** the only tab of "Work" is a new tab page and the user closes it
- **THEN** the window closes

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

### Requirement: Spaces restored after a relaunch
After Clair quits and relaunches, each restored tab SHALL return to its Space at its place in the Space's order, whichever windows come back (`browser-window`, "Windows restored at launch"). A tab whose Space no longer exists SHALL join the Space its window shows.

#### Scenario: Relaunch
- **WHEN** the user quits with a window showing "Work", which has three tabs, while "Home" has two, and relaunches
- **THEN** the window shows "Work", listing its three tabs in order, and switching to "Home" lists its two

#### Scenario: Two windows, not restored
- **WHEN** the user quits with two windows open, which opened tabs of "Work" between them, and relaunches with restoring windows off (`browser-window`)
- **THEN** the one window lists every one of those tabs in "Work", in order

#### Scenario: Reopen Closed Tab
- **WHEN** the user closes a tab of "Work", switches to "Home" and chooses Restore Last Closed Tab
- **THEN** the tab comes back in "Work", and the window shows "Work"
