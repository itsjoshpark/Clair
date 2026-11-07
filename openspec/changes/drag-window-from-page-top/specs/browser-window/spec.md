# Spec Delta

## ADDED Requirements

### Requirement: Dragging the window from the top of the page
While the preference is on, a drag that starts in the top 59 points of the page SHALL move the window, unless the page keeps it (see the next requirement). The strip SHALL span the page's width, follow the page with the sidebar shown or hidden, and depend neither on how far the page is scrolled nor on the page's content, such as the height of its header. Only a press inside the strip SHALL start a window drag; a drag that starts anywhere else on the page SHALL reach the page as before.

#### Scenario: Drag from empty space at the top of the page
- **WHEN** the user presses on empty space 20 points below the page's top edge and drags 40 points down and to the right
- **THEN** the window moves with the pointer, and the page's content doesn't scroll, select or change

#### Scenario: Sidebar hidden
- **WHEN** the sidebar is hidden and the user drags from empty space 20 points below the page's top edge
- **THEN** the window moves with the pointer

#### Scenario: Edge of the strip
- **WHEN** the user drags from empty space 58 points below the page's top edge, and then from 60 points below it
- **THEN** the first drag moves the window, and the second reaches the page and leaves the window in place

#### Scenario: Tall page header
- **WHEN** the page has a 120-pixel header and the user drags from empty space in it 80 points below the page's top edge
- **THEN** the drag reaches the page and the window stays in place

#### Scenario: Drag from below into the strip
- **WHEN** the user presses on empty space 100 points below the page's top edge and drags up into the strip
- **THEN** the drag reaches the page and the window stays in place

#### Scenario: Scrolled page
- **WHEN** the page is scrolled down and the user drags from empty space 20 points below the page's top edge
- **THEN** the window moves with the pointer

#### Scenario: Inactive window
- **WHEN** another app is active and the user drags from empty space at the top of a Clair window's page
- **THEN** Clair becomes active and the window comes forward, without moving

### Requirement: The page keeps drags under its own cursors
A press in the strip SHALL reach the page first. If the pointer shows any cursor other than the arrow when the press starts or when the drag begins, such as the I-beam over selectable text, the pointing hand over a link, or a cursor the page sets itself, the drag SHALL stay with the page and the window SHALL NOT move. Under the arrow cursor, the window SHALL move, whether or not the page handles the press.

#### Scenario: Selecting text at the top of the page
- **WHEN** the user drags across selectable text in the strip
- **THEN** the text is selected and the window doesn't move

#### Scenario: Dragging a link at the very top of the page
- **WHEN** the user drags a link 10 points below the page's top edge, where the window's title bar overlaps the page
- **THEN** the link is dragged as a link, as elsewhere on the page, and the window doesn't move

#### Scenario: Element with its own cursor
- **WHEN** an element in the strip sets `cursor: crosshair` and the user drags from it
- **THEN** the page receives the movement and the window doesn't move

#### Scenario: Drag from a button
- **WHEN** the user drags from a button in the strip that shows the arrow cursor
- **THEN** the window moves with the pointer

#### Scenario: Page that cancels the press under the arrow
- **WHEN** an element in the strip cancels `mousedown`, shows the arrow cursor, and the user drags from it
- **THEN** the window moves with the pointer, as in Arc

### Requirement: Clicks at the top of the page
Presses in the strip that don't move the window SHALL reach the page as anywhere else on it. A double-click in the strip SHALL go to the page and SHALL NOT zoom or minimize the window. Once the window has moved, the page SHALL receive the release, so it isn't left with the button held down.

#### Scenario: Clicking a link at the top of the page
- **WHEN** the user clicks a link in the strip without moving the pointer
- **THEN** the link opens as it would anywhere else on the page

#### Scenario: Double-clicking at the top of the page
- **WHEN** the user double-clicks empty space in the strip
- **THEN** the page receives the double-click, and the window keeps its size and place

#### Scenario: Page after the window moved
- **WHEN** the user drags the window from the strip, releases, and then moves the pointer over the page with no button pressed
- **THEN** the page receives ordinary pointer movement, with no text being selected and no element left pressed

### Requirement: Where the strip doesn't apply
The strip SHALL apply only to the page in the card. Native views over the page, such as the command bar, find, toasts, infobars and the revealed sidebar, docked DevTools, and the crashed-page view SHALL take presses as before. In window or page full screen, no press on the page SHALL move the window.

#### Scenario: Find field over the strip
- **WHEN** the find field is open over the top of the page and the user drags from it
- **THEN** the find field gets the press and the window doesn't move

#### Scenario: Full screen
- **WHEN** the window is in full screen and the user drags from the top of the page
- **THEN** the drag reaches the page and the window doesn't move

### Requirement: Window dragging preference
A preference, on by default and kept for the user across launches, SHALL turn dragging the window from the top of the page on and off for every native window, including incognito ones. A change SHALL apply to open windows at once. With it off, presses on the page SHALL reach the page as they did before this change, and no press on the page SHALL move the window, in key and inactive windows alike.

#### Scenario: Default
- **WHEN** Clair starts with no stored value for the preference
- **THEN** dragging from the top of the page moves the window

#### Scenario: Turned off
- **WHEN** the preference is turned off while a window is open and the user drags from empty space at the top of its page
- **THEN** the drag reaches the page and the window doesn't move, without relaunching Clair

#### Scenario: Turned off in an inactive window
- **WHEN** the preference is off, another app is active, and the user drags from the top of a Clair window's page
- **THEN** Clair becomes active, and the window doesn't move
