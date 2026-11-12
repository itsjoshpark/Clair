# Spec Delta

## Purpose

Spaces separate a user's tabs into named sets, as in Arc. This covers creating, switching, editing, reordering and deleting Spaces, how tabs belong to a Space, and how Spaces come back after a relaunch.

## ADDED Requirements

### Requirement: Spaces
Clair SHALL keep an ordered list of Spaces. Each Space SHALL have a name and an optional icon, which is one emoji. There SHALL always be at least one Space. Spaces and their order SHALL persist across launches.

#### Scenario: First launch
- **WHEN** Clair launches with no stored Spaces
- **THEN** there is one Space, named "Home", and the window shows it

#### Scenario: Spaces persist
- **WHEN** the user creates the Spaces "Work" and "Travel", quits Clair and relaunches it
- **THEN** the Spaces "Home", "Work" and "Travel" exist in that order, each with its name and icon

### Requirement: Space header
Above the tab list, the sidebar SHALL show the current Space's icon, if it has one, and its name. Right-clicking the header SHALL open a menu offering Change Space Icon…, Rename Space…, Manage Spaces… and Delete Space. An incognito or guest window SHALL show no Space header.

#### Scenario: Header shows the Space
- **WHEN** a window shows the Space "Work", whose icon is 💼
- **THEN** the sidebar shows 💼 and "Work" above the "New Tab" row

#### Scenario: Incognito window
- **WHEN** the user opens an incognito window
- **THEN** its sidebar shows "Incognito" and no Space header or Space switcher

### Requirement: Switching Spaces
A window SHALL show one Space at a time. The user SHALL be able to switch with the footer's Space switcher, with Spaces › Next Space (Opt+Cmd+Right) and Previous Space (Opt+Cmd+Left), and with Spaces › the Space's name (Ctrl+1 to Ctrl+9 for the first nine). Next and Previous SHALL wrap around at the ends of the list, as in Arc. Switching SHALL keep the window's frame, sidebar width and sidebar visibility.

#### Scenario: Switching from the footer
- **WHEN** a window shows "Home" and the user clicks "Work" in the footer's switcher
- **THEN** the sidebar shows "Work" and its tabs, and the card shows the tab last active in "Work" in this window

#### Scenario: Switching with the keyboard
- **WHEN** a window shows the first of three Spaces and the user presses Ctrl+3
- **THEN** the window shows the third Space

#### Scenario: At the end of the list
- **WHEN** a window shows the last of three Spaces and the user presses Opt+Cmd+Right
- **THEN** the window shows the first Space

### Requirement: Switching animation
Switching Spaces SHALL slide the sidebar's content between the URL field and the footer sideways, as in Arc, with the new Space coming from the side it is on in the Space order. The top row, URL field, footer and card SHALL not slide. With Reduce Motion on, the content SHALL change without sliding.

#### Scenario: Space to the right
- **WHEN** a window shows the first Space and the user switches to the second
- **THEN** the first Space's header and tabs slide out to the left while the second's slide in from the right, settling in about 300 ms

#### Scenario: Reduce Motion
- **WHEN** Reduce Motion is on and the user switches Spaces
- **THEN** the sidebar shows the new Space without a slide

### Requirement: Showing a Space that has no tab here
A window SHALL always show a tab. When it switches to a Space that has no tab in this window, it SHALL open a new tab page in that Space, with the command bar open. A new window SHALL show the Space of the window it was opened from, or the Space last shown when no window is open, on a new tab page with the command bar open.

#### Scenario: Empty Space
- **WHEN** the user switches to a Space that has no tabs
- **THEN** the window shows a new tab page in that Space, with the command bar open

#### Scenario: New window
- **WHEN** the user presses Cmd+N in a window showing "Work"
- **THEN** a new window shows "Work" with a new tab page and the command bar open

### Requirement: Creating a Space
Spaces › New Space… and the footer's plus menu SHALL replace the sidebar's content with a form, as in Arc: a name field with an icon button, "Create Space" and "Cancel". "Create Space" SHALL be disabled until a name is typed. Creating SHALL add the Space after the last one and show it in the window. Cancel or Esc SHALL return to the Space shown before, creating nothing.

#### Scenario: Creating a Space
- **WHEN** the user opens the form, types "Work" and clicks "Create Space"
- **THEN** a Space "Work" is last in the switcher, and the window shows it with a new tab page

#### Scenario: No name
- **WHEN** the form's name field is empty
- **THEN** "Create Space" is disabled

#### Scenario: Cancelling
- **WHEN** the user types a name and presses Esc
- **THEN** the sidebar shows the earlier Space again and no Space is created

### Requirement: Renaming a Space
Rename Space… SHALL turn the header's name into a field with its text selected. Return or "Done" SHALL keep a non-empty name, and Esc SHALL discard the edit.

#### Scenario: Renaming
- **WHEN** the user chooses Rename Space…, types "Research" and presses Return
- **THEN** the header and the Spaces menu show "Research"

#### Scenario: Empty name
- **WHEN** the user clears the name and presses Return
- **THEN** the Space keeps its earlier name

### Requirement: Space icon
Change Space Icon…, and the icon button in the New Space form, SHALL open macOS's emoji picker, and the emoji the user chooses SHALL become the Space's icon. Only one emoji SHALL be kept, and text that isn't an emoji SHALL be ignored. Deleting the icon SHALL leave the Space without one. The header SHALL show the icon before the name, and the switcher SHALL show a Space's icon, or a dot for a Space without one.

#### Scenario: Choosing an icon
- **WHEN** the user chooses Change Space Icon… and picks 📚 in the emoji picker
- **THEN** the header and the Space's item in the switcher show 📚

#### Scenario: Replacing an icon
- **WHEN** a Space's icon is 📚 and the user picks ✈️
- **THEN** the Space's icon is ✈️ alone

#### Scenario: Typing a letter
- **WHEN** the user types "a" while choosing an icon
- **THEN** the Space's icon doesn't change

#### Scenario: Removing the icon
- **WHEN** the user chooses Change Space Icon… and presses Delete
- **THEN** the header shows the name alone, and the switcher shows a dot for the Space

### Requirement: Reordering Spaces
The user SHALL be able to reorder Spaces by dragging a Space's item in the footer's switcher to another place in it. The new order SHALL show at once in every window's switcher and in the Spaces menu, and Ctrl+1 to Ctrl+9 and Next and Previous Space SHALL follow it.

#### Scenario: Dragging a Space
- **WHEN** the Spaces are "Home", "Work" and "Travel", and the user drags "Travel" before "Home" in the switcher
- **THEN** the switcher and the Spaces menu show "Travel", "Home", "Work", and Ctrl+1 shows "Travel"

#### Scenario: The order persists
- **WHEN** the user reorders Spaces, quits Clair and relaunches it
- **THEN** the Spaces are in the new order

### Requirement: Deleting a Space
Delete Space SHALL be disabled for the only Space. Deleting a Space with no tabs SHALL happen at once. For a Space with tabs, Clair SHALL first ask for confirmation in a dialog, saying that its tabs will close; on confirmation its tabs SHALL close in every window. Each window that showed the Space SHALL then show the Space before it, or the one after when it was first.

#### Scenario: The only Space
- **WHEN** there is one Space and the user opens its header's menu
- **THEN** Delete Space is disabled

#### Scenario: Space with tabs
- **WHEN** the user deletes the second of three Spaces, which has two tabs, and confirms
- **THEN** the two tabs close, the Space leaves the switcher, and the window shows the first Space

#### Scenario: Cancelled
- **WHEN** the user cancels the confirmation
- **THEN** the Space and its tabs are untouched

### Requirement: Manage Spaces dialog
Manage Spaces…, in the Spaces menu and the Space header's menu, SHALL open a dialog on the window, with every Space in order on the left, each with its icon, name and number of tabs, and the selected Space's name and icon on the right. It SHALL open with the window's Space selected, and "Done" or Esc SHALL close it.

#### Scenario: Opening
- **WHEN** a window shows "Work" and the user chooses Manage Spaces…
- **THEN** the dialog lists every Space in order with "Work" selected, and shows its name and icon

#### Scenario: Closing
- **WHEN** the user clicks "Done"
- **THEN** the dialog closes and the window shows the Space it showed before, unless that Space was removed

### Requirement: Editing Spaces in the dialog
In the Manage Spaces dialog the user SHALL be able to add a Space, remove the selected one, drag Spaces to reorder them, and edit the selected Space's name and icon. Each change SHALL apply at once, in every window. Removing a Space SHALL follow the same rules and confirmation as Delete Space.

#### Scenario: Reordering
- **WHEN** the user drags the last Space to the top of the list
- **THEN** it is first in the list and in every window's switcher

#### Scenario: Renaming
- **WHEN** the user changes the selected Space's name to "Research"
- **THEN** its row, the sidebar's header and the Spaces menu show "Research"

#### Scenario: Adding
- **WHEN** the user clicks Add
- **THEN** a new Space is last in the list, selected, with its name field focused

#### Scenario: Removing a Space with tabs
- **WHEN** the user selects a Space with tabs and clicks Remove
- **THEN** the dialog asks for confirmation in place of its list, and on confirmation the Space leaves the list

#### Scenario: The only Space
- **WHEN** there is one Space
- **THEN** Remove is disabled

### Requirement: Tabs belong to a Space
Every tab outside incognito and guest windows SHALL belong to exactly one Space. A new tab SHALL join the Space its window shows, whether it comes from Cmd+T, a link, an extension or another app.

#### Scenario: New tab
- **WHEN** a window shows "Work" and the user opens a tab with Cmd+T
- **THEN** the tab is listed in "Work" and in no other Space

#### Scenario: Link opened in a new tab
- **WHEN** the user Cmd-clicks a link in a tab of "Work"
- **THEN** the new tab is listed in "Work"

### Requirement: Moving a tab to another Space
With more than one Space, a tab row's context menu SHALL offer "Move to Space" with every other Space. Choosing one SHALL put the tab at the top of that Space's list and remove it from this one, keeping its page as it is and leaving the window on the Space it shows.

#### Scenario: Moving a tab
- **WHEN** the user moves a tab with a half-filled form from "Home" to "Research"
- **THEN** the tab is first in "Research" with the form as it was, and "Home" no longer lists it

#### Scenario: Moving the active tab
- **WHEN** the user moves the active tab to another Space
- **THEN** the window stays on its Space and shows the tab it would show had the moved tab been closed

#### Scenario: One Space
- **WHEN** there is one Space
- **THEN** the tab's menu has no "Move to Space"

### Requirement: Tab chosen after a close
When the user closes the active tab, the window SHALL show, in order: the tab the user selected it from, if that tab is still listed in the Space; otherwise the row above it; otherwise the row below it. When the Space has no other tab in the window, the window SHALL show a tab of another Space, switching to that Space, or close if it has no other tab.

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
- **WHEN** the user closes the only tab of "Work" in a window that also has tabs in "Home"
- **THEN** the window shows "Home"

### Requirement: Tab commands follow the Space
Tabs › Next Tab (Opt+Cmd+Down), Previous Tab (Opt+Cmd+Up), Ctrl+Tab, Cmd+1 to Cmd+9 and Close Tabs Below SHALL act on the rows the sidebar lists, in its order, and never on a tab of another Space.

#### Scenario: Cmd+number
- **WHEN** a window shows "Work", whose rows are X, Y and Z, and the user presses Cmd+2
- **THEN** Y is active

#### Scenario: Next tab at the Space's end
- **WHEN** the last row of the Space is active and the user presses Opt+Cmd+Down
- **THEN** the first row of the same Space is active

### Requirement: Spaces restored after a relaunch
After Clair quits and relaunches, each restored tab SHALL return to its Space at its place in the Space's order, and each window SHALL show the Space it showed. A tab whose Space no longer exists SHALL join the Space its window shows.

#### Scenario: Relaunch
- **WHEN** the user quits with a window showing "Work", which has three tabs, while "Home" has two, and relaunches
- **THEN** the window shows "Work" with its three tabs in order, and switching to "Home" lists its two

#### Scenario: Reopen Closed Tab
- **WHEN** the user closes a tab of "Work", switches to "Home" and chooses Restore Last Closed Tab
- **THEN** the tab comes back in "Work", and the window shows "Work"
