# Spec Delta

## Purpose

Peek opens a link in a card over the current tab's page, as Arc does, so the user can read it and then dismiss it or keep it as a tab, without leaving the page they were on.

## ADDED Requirements

### Requirement: Shift+click opens a Peek
While the Peek preference is on, Shift+clicking a link in a page in a native browser window SHALL open the link in a Peek attached to that page's tab instead of a new window, whatever the link's target. A tab SHALL have at most one Peek. Opening a link in a new window from the page's context menu SHALL still open a new window.

#### Scenario: Shift+click on a link
- **WHEN** the user Shift+clicks a link to another site in the active tab
- **THEN** the link opens in a Peek over that tab's page, and no window or sidebar row is added

#### Scenario: Link with a target
- **WHEN** the user Shift+clicks a link with `target="_blank"`
- **THEN** it opens in a Peek

#### Scenario: Context menu
- **WHEN** the user chooses Open Link in New Window from a link's context menu
- **THEN** the link opens in a new window

### Requirement: Peek layout
The Peek SHALL be a card with rounded corners centred over the page card, about 80% of the page card's width and its full height less about 2 points at the top and bottom. Behind it, the parent page SHALL shrink by about 9 points on each side and be washed out toward the window's background colour, in Light and Dark Mode.

#### Scenario: Peek open
- **WHEN** a Peek is open in a window whose page card is 1723 by 1030 points
- **THEN** the Peek is about 1386 by 1026 points, centred on the card, over a smaller, washed-out parent page

#### Scenario: Resizing the window
- **WHEN** the user resizes the window with a Peek open
- **THEN** the Peek and the parent page keep their proportions to the card

### Requirement: Peek buttons
A column of round buttons SHALL sit outside the Peek's top-trailing corner, beside the card: Close (×) and then Expand. Each SHALL highlight under the pointer and have a VoiceOver label naming its action, and Arc's tooltip: "Close" with ⌘W, and "Expand" with ⌘O.

#### Scenario: Buttons shown
- **WHEN** a Peek is open
- **THEN** Close and Expand show in a column beside its top-trailing corner, outside the card

### Requirement: Peek animation
Opening a Peek SHALL grow the card from the point the user clicked to its full size in about 190 ms, fast at first and then settling, while the parent page shrinks and washes out and the buttons move with the card's corner. Closing it SHALL reverse this toward the same point. With Reduce Motion on, the Peek SHALL fade in and out instead.

#### Scenario: Opening
- **WHEN** the user Shift+clicks a link near the top-leading corner of the page
- **THEN** the Peek grows from that point to full size in about 190 ms, most of the way in the first 50 ms

#### Scenario: Closing
- **WHEN** the user closes the Peek
- **THEN** it shrinks back toward the point it grew from and the parent page returns to full size and colour

### Requirement: A Peek belongs to its tab
A Peek SHALL stay with its parent tab until it's closed or expanded. Selecting another tab, from the sidebar or with a shortcut, SHALL hide the Peek with its parent and leave it open, and selecting the parent tab again SHALL show the parent with its Peek as they were.

#### Scenario: Switching tabs and back
- **WHEN** a Peek is open on one tab, and the user selects another tab in the sidebar and then the first tab again
- **THEN** the other tab shows normally, and then the first tab shows with its Peek, at the same page and scroll position

### Requirement: The window acts on the Peek
While a Peek shows, the URL field, back, forward, reload and stop, Copy URL, find in page, DevTools, site controls and page info SHALL act on the Peek's page, as they act on the active tab's page otherwise. Back and forward SHALL move through the Peek's own history.

#### Scenario: URL field
- **WHEN** a Peek of `example.com` is open over a page from another site
- **THEN** the URL field shows `example.com`

#### Scenario: Back in a Peek
- **WHEN** the user follows a link inside a Peek and then chooses back
- **THEN** the Peek goes back to its first page, and the parent page doesn't change

### Requirement: Links inside a Peek
A link followed with a plain click inside a Peek SHALL navigate the Peek. A link Shift+clicked inside a Peek SHALL open as a normal new tab at the top of the tab list. Other ways of opening a link in a new tab SHALL open as from any page.

#### Scenario: Plain click
- **WHEN** the user clicks a link inside a Peek
- **THEN** the Peek shows the linked page

#### Scenario: Shift+click inside a Peek
- **WHEN** the user Shift+clicks a link inside a Peek
- **THEN** the link opens in a new active tab at the top of the tab list, and the Peek stays open on its tab

### Requirement: Closing a Peek
Clicking the Close button, pressing Cmd+W, clicking the parent page outside the card, or pressing Esc when the page doesn't use it SHALL close the Peek and show its parent tab's page as it was. Cmd+W SHALL close only the Peek, not the parent tab.

#### Scenario: Close button
- **WHEN** the user clicks the Peek's Close button
- **THEN** the Peek closes and the parent tab shows its page as before

#### Scenario: Cmd+W
- **WHEN** a Peek is open and the user presses Cmd+W
- **THEN** the Peek closes and its parent tab stays open

#### Scenario: Clicking outside
- **WHEN** the user clicks the washed-out parent page beside the Peek
- **THEN** the Peek closes, and the click doesn't reach the parent page

#### Scenario: Esc
- **WHEN** focus is in a Peek's page that doesn't use Esc and the user presses Esc
- **THEN** the Peek closes

### Requirement: Esc the page keeps
When the Peek's page uses an Esc, by preventing its default action or because a text field takes it, the page SHALL handle it and the Peek SHALL stay open. The Close button SHALL then turn into a red pill reading "Confirm" with the ×, for about one second. Pressing Esc again or clicking the pill while it shows SHALL close the Peek without the page receiving that Esc.

#### Scenario: Page closes its own dialog
- **WHEN** a page in a Peek closes its own dialog on Esc and prevents the key's default action
- **THEN** the dialog closes, the Peek stays open, and the Close button shows "Confirm" for about one second before returning to ×

#### Scenario: Esc again
- **WHEN** the Close button shows "Confirm" and the user presses Esc
- **THEN** the Peek closes

#### Scenario: Confirm times out
- **WHEN** the Close button shows "Confirm" and the user waits two seconds and then presses Esc
- **THEN** the page receives the Esc as before, and the Peek closes only if the page doesn't use it

### Requirement: Expanding a Peek
Clicking Expand, or pressing Cmd+O while the Peek shows, SHALL turn the Peek into a normal, active tab directly below its parent in the tab list, keeping its page, scroll position and history. The parent tab SHALL then have no Peek. Cmd+O SHALL open a file, as in Chromium, only while no Peek shows.

#### Scenario: Expand
- **WHEN** a Peek is open on the second of three tabs and the user clicks Expand
- **THEN** the Peek's page becomes the third of four tabs, is active and shows full size, and back returns through its Peek history

#### Scenario: Cmd+O
- **WHEN** a Peek shows and the user presses Cmd+O
- **THEN** the Peek expands into a tab, as with the Expand button

### Requirement: Closing the parent closes its Peek
Closing a tab that has a Peek SHALL close its Peek with it. A leave-page confirmation from either page SHALL work as it does for a tab, and cancelling it SHALL keep both open.

#### Scenario: Closing the parent row
- **WHEN** a tab with a Peek is closed from its row's close button
- **THEN** the tab and its Peek close, and no Peek is left in the window

### Requirement: Peeks end with the session
Peeks SHALL NOT outlive the session. Quitting Clair or closing a window SHALL close the Peeks in it, and session restore and Reopen Closed Window SHALL restore their parent tabs without them.

#### Scenario: Quit with a Peek open
- **WHEN** a tab has a Peek open, and the user quits and relaunches Clair with session restore on
- **THEN** the tab is restored without its Peek, and no tab for the Peek's page is restored

### Requirement: Tab shortcuts treat a tab and its Peek as one
Ctrl+Tab, Ctrl+Shift+Tab, Cmd+Opt+Right and Left, and Cmd+1 to Cmd+9 SHALL count the tabs in the tab list, so a tab and its Peek are one stop. Selecting a tab that has a Peek SHALL show the Peek.

#### Scenario: Ctrl+Tab across a Peek
- **WHEN** the first of three tabs has a Peek open and shows it, and the user presses Ctrl+Tab
- **THEN** the second tab becomes active, and the first tab's Peek stays open

#### Scenario: Cmd+number
- **WHEN** the second tab has a Peek and the user presses Cmd+2
- **THEN** the second tab shows with its Peek
