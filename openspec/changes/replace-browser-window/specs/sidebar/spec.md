# Spec Delta

## Purpose

Defines the native window's sidebar: the browser controls it carries in place of Chromium's toolbar, the window's tab list, and how the sidebar is hidden, revealed and resized.

## ADDED Requirements

### Requirement: Navigation controls
The sidebar's top row SHALL hold, after the window controls, a button that hides the sidebar, then back, forward and reload. Back and forward SHALL be dimmed and inert when the active tab can't go that way. Reload SHALL become stop while the active tab loads. When the sidebar is too narrow for that row, as in Arc, the row SHALL hold back, forward and a menu offering reload (or stop) and Hide Sidebar.

#### Scenario: Going back
- **WHEN** the user has followed a link in the active tab and clicks back
- **THEN** the tab returns to the previous page, and forward becomes available

#### Scenario: Loading
- **WHEN** the active tab starts loading a page
- **THEN** reload shows as stop until loading ends, and clicking it stops the load

#### Scenario: Narrow sidebar
- **WHEN** the user narrows the sidebar below 214 points
- **THEN** the top row shows back, forward and a "More" menu with Reload and Hide Sidebar

### Requirement: URL field
Below the top row, the sidebar SHALL show the active tab's host, or its full URL for pages without a host such as `chrome://` pages and files, with a search icon and "Search or Enter URL…" for a new tab page. Clicking the field SHALL open the command bar on the current URL. While the pointer is over the field, its trailing end SHALL show a copy button and the site-controls button.

#### Scenario: Web page
- **WHEN** the active tab shows `https://news.ycombinator.com/item?id=1`
- **THEN** the URL field reads `news.ycombinator.com`

#### Scenario: Clicking the field
- **WHEN** the user clicks the URL field
- **THEN** the command bar opens with the tab's full URL selected

#### Scenario: Copying the URL
- **WHEN** the pointer is over the URL field and the user clicks its copy button
- **THEN** the tab's full URL is on the pasteboard and a toast confirms it

### Requirement: Site controls and indicators
The URL field SHALL have a site-controls button, shown while the pointer is over the field, that opens Chromium's page info for the active tab, showing its connection security and permissions. While the active tab uses the camera, microphone, location or screen capture, or has had a permission blocked, the URL field SHALL show an indicator for each, which opens the matching controls.

#### Scenario: Page using the camera
- **WHEN** the active page is capturing the camera
- **THEN** a camera indicator shows in the URL field, and clicking it shows the camera permission controls for the site

#### Scenario: Opening site controls
- **WHEN** the user rests the pointer on the URL field of an HTTPS page and clicks the site-controls button
- **THEN** page info opens attached to the button and shows that the connection is secure

### Requirement: Extension actions
The sidebar SHALL show the actions of extensions the user has pinned as buttons with their icons and badges, and an extensions button that lists every extension with an action. Clicking an action SHALL run it as Chromium's toolbar would, opening its popup attached to the button.

#### Scenario: Pinned extension with a popup
- **WHEN** the user clicks a pinned extension's button and its action has a popup
- **THEN** the popup opens attached to that button and is interactive

#### Scenario: Badge text
- **WHEN** an extension sets its action's badge text to "3"
- **THEN** its button in the sidebar shows a "3" badge

#### Scenario: Extension without a pin
- **WHEN** the user opens the extensions button's list and chooses an unpinned extension
- **THEN** its action runs, and its popup opens attached to the extensions button

### Requirement: Downloads indicator
The sidebar SHALL show a downloads button while the window's profile has downloads from this session. It SHALL show progress while a download is running and mark finished downloads the user hasn't looked at. Clicking it SHALL open a list of recent downloads that can open, reveal in Finder, cancel or retry each one, and open `chrome://downloads`.

#### Scenario: Download in progress
- **WHEN** a download starts
- **THEN** the downloads button appears and shows the download's progress until it finishes

#### Scenario: Opening a finished download
- **WHEN** the user opens the downloads list and clicks a finished download
- **THEN** the file opens in its default app, and the button stops marking unseen downloads

### Requirement: Tab list
Below the URL field, the sidebar SHALL show a "New Tab" row and then every tab of the window, in the window's tab order, with its favicon and title. The active tab SHALL be highlighted. A tab that plays sound or is muted SHALL show a speaker that mutes or unmutes it. The list SHALL scroll when it doesn't fit.

#### Scenario: Selecting a tab
- **WHEN** the user clicks a tab row
- **THEN** that tab becomes active and its row is highlighted

#### Scenario: Muting a tab
- **WHEN** a tab plays sound and the user clicks its speaker
- **THEN** the tab is muted and its speaker shows as muted

#### Scenario: Many tabs
- **WHEN** the window has more tabs than the sidebar can show
- **THEN** the tab list scrolls, and the top row, URL field and bottom bar stay in place

### Requirement: New tabs at the top
Every new tab SHALL be inserted at the top of the tab list, directly under the "New Tab" row, whether it comes from Cmd+T, the "New Tab" row, the command bar, a link opened in a new tab, or an extension or page that doesn't ask for a position. Whether it becomes active SHALL follow Chromium, so a link opened in the background stays in the background. Tabs that come back through session restore or Reopen Closed Tab SHALL return to their previous positions.

#### Scenario: Command bar tab
- **WHEN** the user opens a URL from the command bar with Cmd+T
- **THEN** the new tab is first in the list and active

#### Scenario: Link opened in a new tab
- **WHEN** the user Cmd-clicks a link in the third tab of five
- **THEN** the new tab is first in the list, and the third tab stays active

### Requirement: Closing, reordering and tab menu
Hovering a tab row SHALL show a close button. Clicking it, or middle-clicking the row, SHALL close the tab. Tabs SHALL be reorderable by dragging. A row's context menu SHALL offer Copy Link, Duplicate, Mute or Unmute, Close Tab and Close Tabs Below.

#### Scenario: Reordering
- **WHEN** the user drags the third tab above the first
- **THEN** it becomes the first tab, and Cmd+1 selects it

#### Scenario: Close Tabs Below
- **WHEN** the user chooses Close Tabs Below on the second of five tabs
- **THEN** the third to fifth tabs close, each with its usual leave-page confirmation

### Requirement: Hiding the sidebar
Cmd+S, the sidebar button and View > Hide Sidebar SHALL hide the sidebar with a spring animation, and the card SHALL grow to fill the window with a margin of about 5 points. Hiding SHALL also hide the window controls. The same commands SHALL show it again, and the View menu item SHALL read "Show Sidebar" while it is hidden. File > Save Page As… SHALL move to Shift+Cmd+S, as in Arc.

#### Scenario: Hiding and showing
- **WHEN** the user presses Cmd+S twice
- **THEN** the sidebar animates out and the card fills the window, then the sidebar animates back and the card returns to its inset

#### Scenario: Save Page As on Shift+Cmd+S
- **WHEN** the user presses Cmd+S with a page focused, and then Shift+Cmd+S
- **THEN** Cmd+S hides the sidebar without opening a save panel, and Shift+Cmd+S opens the save panel for the page

### Requirement: Revealing the hidden sidebar
While the sidebar is hidden, resting the pointer at the window's leading edge SHALL slide the sidebar in as a floating overlay above the page, without resizing the page. Moving the pointer away SHALL slide it back out.

#### Scenario: Hover reveal
- **WHEN** the sidebar is hidden and the pointer rests at the window's leading edge
- **THEN** the sidebar slides in over the page, the page keeps its size, and moving the pointer away from the overlay hides it again

### Requirement: Resizing the sidebar
The user SHALL be able to resize the sidebar by dragging its trailing edge, between Arc's limits of 164 and 500 points. New windows SHALL open with the most recently chosen width and hidden state.

#### Scenario: Narrowest sidebar
- **WHEN** the user drags the sidebar's edge as far left as it goes
- **THEN** the sidebar stops at 164 points wide

#### Scenario: Wider sidebar
- **WHEN** the user drags the sidebar's edge to make it wider and opens a new window
- **THEN** the new window's sidebar has the wider width
