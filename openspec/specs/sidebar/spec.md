# sidebar Specification

## Purpose
Defines the native window's sidebar: the browser controls it carries in place of Chromium's toolbar, the window's tab list, and how the sidebar is hidden, revealed and resized.

## Requirements

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

### Requirement: Tooltips in Arc's wording
The sidebar's controls SHALL have Clair's own tooltips, never the system's, in Arc's wording and with their shortcuts: "Hide sidebar" ("Lock sidebar" while the hidden sidebar is revealed), "Go back", "Go forward", "Reload this page" or "Stop loading this page", "Copy URL", "Site Control Center", "Close tab" and "More options".

#### Scenario: Tooltip on back
- **WHEN** the pointer rests on the back button
- **THEN** a tooltip reads "Go back"

#### Scenario: Tooltip on a tab's close button
- **WHEN** the pointer rests on a tab's close button
- **THEN** a tooltip reads "Close tab" with the keys ⌘ and W

#### Scenario: Tooltip on the revealed sidebar's button
- **WHEN** the hidden sidebar is revealed and the pointer rests on its sidebar button
- **THEN** a tooltip reads "Lock sidebar"

### Requirement: Tab titles and clicks in tooltips
Resting the pointer on a tab row for about 2 seconds SHALL show the tab's full title in a tooltip. A click on a control, including the right click that opens a context menu, SHALL put its tooltip away until the pointer leaves the control.

#### Scenario: Full title of a tab
- **WHEN** the pointer rests on a tab row for 2 seconds
- **THEN** a tooltip shows the tab's full title

#### Scenario: Context menu on a tab
- **WHEN** the user right-clicks a tab row and leaves its context menu open
- **THEN** no tooltip shows the tab's title

### Requirement: URL field
Below the top row, the sidebar SHALL show the active tab's host without a leading `www.`, or its full URL for pages without a host such as `chrome://` pages and files, with a search icon and "Search or Enter URL…" for a new tab page. Clicking the field SHALL open the command bar on the current URL, and its context menu SHALL offer Copy URL. While the pointer is over the field, its background SHALL darken.

#### Scenario: Web page
- **WHEN** the active tab shows `https://news.ycombinator.com/item?id=1`
- **THEN** the URL field reads `news.ycombinator.com`

#### Scenario: Host with www
- **WHEN** the active tab shows `https://www.apple.com/mac/`
- **THEN** the URL field reads `apple.com`

#### Scenario: Clicking the field
- **WHEN** the user clicks the URL field
- **THEN** the command bar opens with the tab's full URL selected

#### Scenario: Copying the URL
- **WHEN** the pointer is over the URL field and the user clicks its copy button
- **THEN** the tab's full URL is on the pasteboard, and Arc's "Copied Current URL" popup shows in the card's top-trailing corner

### Requirement: URL field buttons
While the pointer is anywhere over the key window's sidebar, the URL field's trailing end SHALL show a copy button and the site-controls button, fading in and out.

#### Scenario: Pointer over the tab list
- **WHEN** the pointer moves over the tab list of the key window
- **THEN** the URL field shows its copy and site-controls buttons

### Requirement: Site controls and indicators
The URL field SHALL have a site-controls button, shown while the pointer is over the field, that opens Chromium's page info for the active tab, showing its connection security and permissions. While the active tab uses the camera, microphone, location or screen capture, the URL field SHALL show an indicator for each, which opens the matching controls. A blocked permission SHALL show no indicator; page info lists it.

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
The sidebar SHALL always show a downloads button in its footer, where Arc has its library button. It SHALL show progress while a download is running and mark finished downloads the user hasn't looked at. Clicking it SHALL open a list of recent downloads that can open, reveal in Finder, cancel or retry each one, and open `chrome://downloads`; with no downloads from this session, the list SHALL say so.

#### Scenario: Download in progress
- **WHEN** a download starts
- **THEN** the downloads button shows the download's progress until it finishes

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
Hovering a tab row SHALL show a close button, as large as Arc's, which highlights under the pointer. Clicking it, or middle-clicking the row, SHALL close the tab. Tabs SHALL be reorderable by dragging. A row's context menu SHALL offer Copy Link, Duplicate, Mute or Unmute, Close Tab and Close Tabs Below, and opening it SHALL draw no selection ring around the row.

#### Scenario: Reordering
- **WHEN** the user drags the third tab above the first
- **THEN** it becomes the first tab, and Cmd+1 selects it

#### Scenario: Close Tabs Below
- **WHEN** the user chooses Close Tabs Below on the second of five tabs
- **THEN** the third to fifth tabs close, each with its usual leave-page confirmation

### Requirement: Hiding the sidebar
Cmd+S, the sidebar button and View > Hide Sidebar SHALL hide the sidebar with a spring animation, and the card SHALL grow to fill the window, keeping a margin of about 10 points on every edge, as in Arc. Hiding SHALL also hide the window controls. The same commands SHALL show it again, and the View menu item SHALL read "Show Sidebar" while it is hidden. File > Save Page As… SHALL move to Shift+Cmd+S, as in Arc.

#### Scenario: Hiding and showing
- **WHEN** the user presses Cmd+S twice
- **THEN** the sidebar animates out and the card grows towards the leading edge with its other margins unchanged, then the sidebar animates back and the card returns to its inset

#### Scenario: Save Page As on Shift+Cmd+S
- **WHEN** the user presses Cmd+S with a page focused, and then Shift+Cmd+S
- **THEN** Cmd+S hides the sidebar without opening a save panel, and Shift+Cmd+S opens the save panel for the page

### Requirement: Revealing the hidden sidebar
While the sidebar is hidden, resting the pointer anywhere in the window's leading inset for about 100 ms SHALL slide the sidebar in as a floating overlay above the page, without resizing the page. Moving the pointer away SHALL slide it back out. Showing the sidebar while it's revealed SHALL dock it where it is, with only the card moving to make room.

#### Scenario: Hover reveal
- **WHEN** the sidebar is hidden and the pointer rests at the window's leading edge
- **THEN** the sidebar slides in over the page, the page keeps its size, and moving the pointer away from the overlay hides it again

#### Scenario: Showing a revealed sidebar
- **WHEN** the sidebar is revealed over the page and the user presses Cmd+S
- **THEN** the sidebar stays where it is and becomes the docked sidebar, and the card narrows to make room

### Requirement: Moving the window from the sidebar
Dragging the sidebar's empty areas, docked or revealed, SHALL move the window, as in Arc. Controls, tab rows and dragging tabs to reorder them SHALL work as before.

#### Scenario: Dragging below the tabs
- **WHEN** the user drags from the empty space below the last tab
- **THEN** the window moves with the pointer

### Requirement: Resizing the sidebar
The user SHALL be able to resize the sidebar by dragging its trailing edge, between Arc's limits of 164 and 500 points. New windows SHALL open with the most recently chosen width and hidden state.

#### Scenario: Narrowest sidebar
- **WHEN** the user drags the sidebar's edge as far left as it goes
- **THEN** the sidebar stops at 164 points wide

#### Scenario: Wider sidebar
- **WHEN** the user drags the sidebar's edge to make it wider and opens a new window
- **THEN** the new window's sidebar has the wider width

### Requirement: Reload and stop follow the page's own loading
Reload SHALL become stop only while the active tab loads a new document in its main frame, as Chromium's toolbar decides. A frame inside the page loading on its own, or a same-document navigation, SHALL leave reload in place. A tab row's loading spinner SHALL follow the same state.

#### Scenario: Frames loading after the page
- **WHEN** a page finishes loading and then an iframe in it reloads every second for ten seconds
- **THEN** the button shows reload throughout, and the tab row shows no spinner

#### Scenario: Same-document navigation
- **WHEN** the page calls `history.pushState` or changes the URL's fragment
- **THEN** the button keeps showing reload

### Requirement: Stop held under the pointer
When a load ends while the pointer is on the stop button, the button SHALL stay inert until the pointer leaves it or about 1.35 seconds pass, and then show reload, so a second click doesn't start a reload by accident.

#### Scenario: Load ends under the pointer
- **WHEN** the user rests the pointer on stop while a page loads, and the load ends
- **THEN** the button stays inert while the pointer stays on it, for up to about 1.35 seconds, and then shows reload

### Requirement: Navigation history menu
Right-clicking or Control-clicking the back or forward button SHALL open a native menu attached to the button listing the active tab's pages in that direction, nearest first, each with its favicon and title (or its URL when it has no title), up to the number of entries Chromium's own back/forward menu shows. The compact top row's back and forward buttons SHALL behave the same. When the tab can't go that way, the button SHALL open no menu.

#### Scenario: Right-click
- **WHEN** the user right-clicks the back button after visiting two pages
- **THEN** the history menu opens under the button without a navigation, listing the previous page first

#### Scenario: Nothing to go back to
- **WHEN** the active tab has no previous page and the user right-clicks back
- **THEN** no menu opens

### Requirement: Choosing a history entry
Choosing an entry in the history menu SHALL take the tab to that page. Choosing it with Cmd held SHALL open that page in a new background tab at the top of the tab list and leave the active tab where it is.

#### Scenario: Going back two pages
- **WHEN** the user has visited pages A, B and C in one tab, right-clicks back and chooses A
- **THEN** the tab shows A, and forward lists B then C

#### Scenario: Opening an entry in a new tab
- **WHEN** the user Cmd-chooses an entry in the back menu
- **THEN** a new tab opens at the top of the tab list on that page, in the background, and the active tab doesn't navigate
