# browser-window Specification

## Purpose
Defines Clair's native browser window: which windows are native, how the window looks and hosts the page and DevTools, the native replacements for UI that lived in Chromium's window, and how Chromium's remaining UI, its bookmarks UI and unsupported features behave inside it.

## Requirements

### Requirement: Normal browser windows are native
Every normal browser window, including incognito and guest windows, SHALL be a native window drawn by the native layer, with no Chromium tab strip, toolbar, omnibox or bookmarks bar. Pop-up, app, Picture-in-Picture and undocked DevTools windows SHALL keep Chromium's own windows.

#### Scenario: Launching packaged Clair
- **WHEN** a user launches packaged Clair
- **THEN** each browser window it opens, restored or new, is the native window, and none shows Chromium's tab strip or toolbar

#### Scenario: Incognito window
- **WHEN** a user opens a new incognito window
- **THEN** it is the native window in a dark appearance, labelled as incognito in its sidebar with a crossed-out eye, and its tabs use the incognito profile

#### Scenario: A page opens a pop-up
- **WHEN** a page calls `window.open` with window features that make Chromium open a pop-up window
- **THEN** the pop-up opens in Chromium's own pop-up window

### Requirement: No Chromium browser window in packaged Clair
Packaged Clair SHALL never show Chromium's own browser window, and SHALL have no setting that brings it back. If `ClairUI.framework` is present but fails to load, Clair SHALL show an alert saying it couldn't start its interface, and quit without opening a window. Only a bare engine build, which has no native layer and isn't shipped, SHALL open Chromium's own window.

#### Scenario: Bare engine
- **WHEN** an engine build without the native layer opens a window
- **THEN** it is Chromium's standard window, and the browser works as ungoogled-chromium does

#### Scenario: Native layer fails to load
- **WHEN** packaged Clair is launched and its `ClairUI.framework` can't be loaded
- **THEN** an alert says Clair couldn't start its interface, and Clair quits without opening any browser window

### Requirement: Window layout
The native window SHALL have no title bar. The sidebar SHALL sit at its leading edge with the window controls in it, and the page SHALL sit in a card with rounded corners and a soft shadow, inset from the window's other edges. The sidebar and the window's background SHALL be one continuous translucent material.

#### Scenario: Default layout
- **WHEN** a native window opens with the sidebar shown
- **THEN** the close, minimize and zoom buttons sit at the top of the sidebar, and the page card is inset by about 10 points at the top, trailing and bottom edges, with no inset on the sidebar side

#### Scenario: Window not focused
- **WHEN** another window becomes key
- **THEN** the native window shows as inactive: the active tab's highlight lightens and loses its shadow, the sidebar's glyphs and the window controls dim, as other macOS windows do

### Requirement: Page shown in the card
The card SHALL show the active tab's page, resized with the window and the sidebar, and SHALL switch to the newly active tab's page as soon as the active tab changes. Hidden tabs' pages SHALL be reported to the page as hidden. When the active tab has a Peek, the card SHALL show the tab's page behind the Peek, as `peek` describes, and both pages SHALL be reported as visible.

#### Scenario: Switching tabs
- **WHEN** the user selects another tab
- **THEN** the card shows that tab's page, and the previous page reports `document.visibilityState` as `hidden`

#### Scenario: Resizing the window
- **WHEN** the user resizes the window
- **THEN** the page's viewport follows the card's size, with no stretched or stale frame left once resizing stops

#### Scenario: Tab with a Peek
- **WHEN** the active tab has a Peek
- **THEN** the card shows the tab's page behind the Peek, and both report `document.visibilityState` as `visible`

#### Scenario: Leaving a tab with a Peek
- **WHEN** the user selects another tab while a Peek shows
- **THEN** both the Peek's page and its parent's page report `document.visibilityState` as `hidden`

### Requirement: DevTools docked in the card
DevTools SHALL open docked inside the card by default, beside the page, on the side its dock setting names (right, bottom or left), with the page resized to the remaining space. Each tab SHALL keep its own DevTools, shown and hidden with the tab. Choosing DevTools' undock option SHALL move it to Chromium's own DevTools window, and docking it again SHALL bring it back into the card.

#### Scenario: Opening DevTools
- **WHEN** the user presses Opt+Cmd+I on a page with DevTools' default settings
- **THEN** DevTools opens inside the card to the right of the page, and the page's viewport narrows to the space left of it

#### Scenario: Switching tabs with DevTools open
- **WHEN** DevTools is docked in one tab and the user selects another tab without DevTools
- **THEN** the card shows only the other tab's page, and selecting the first tab again shows its page with DevTools docked

#### Scenario: Undocking DevTools
- **WHEN** the user chooses DevTools' undock-into-separate-window option
- **THEN** DevTools moves to its own window, and the page fills the card again

### Requirement: Window size and placement restored
The native window SHALL be restored with the size, position, minimized and full-screen state Chromium's session restore records, as Chromium's window would be.

#### Scenario: Relaunch with two windows
- **WHEN** Clair relaunches with session restore after two native windows were open at different sizes
- **THEN** both windows reopen at their previous sizes and positions with their tabs

### Requirement: Full screen
The native window SHALL support macOS full screen. When a page asks for full screen, as a video does, the page SHALL fill the screen alone, without the sidebar or card insets, and Esc SHALL end it. The notice saying so SHALL use the same popup as Copy URL, with Esc drawn as a key.

#### Scenario: Window full screen
- **WHEN** the user chooses View > Enter Full Screen
- **THEN** the window enters macOS full screen and keeps its sidebar state

#### Scenario: Top row in full screen
- **WHEN** the window is in macOS full screen with the sidebar shown
- **THEN** the top row stays where it is in a window, and the hide-sidebar button moves to the sidebar's leading edge in place of the window controls

#### Scenario: Page full screen
- **WHEN** a page's video enters full screen
- **THEN** the video fills the screen with no sidebar, card margin or rounded corners, and pressing Esc returns the window to its previous state

### Requirement: Find in page
Cmd+F SHALL open a floating find field at the top-trailing corner of the card. It SHALL highlight matches as the user types, show the active match's position and the total, step through matches with Return, Shift+Return, Cmd+G and Shift+Cmd+G, and close with Esc.

#### Scenario: Finding text
- **WHEN** the user presses Cmd+F on a page containing "clair" three times and types "clair"
- **THEN** the field shows "1 of 3", the first match is selected, and Cmd+G moves to "2 of 3"

#### Scenario: Closing find
- **WHEN** the user presses Esc in the find field
- **THEN** the field closes, the highlights are cleared, and focus returns to the page

### Requirement: Copy URL from the menu bar
Edit SHALL offer Copy URL after Copy, on Shift+Cmd+C, as in Arc, copying the active tab's URL. Opt+Cmd+C SHALL still inspect an element.

#### Scenario: Copying with the shortcut
- **WHEN** a page is focused and the user presses Shift+Cmd+C
- **THEN** the page's URL is on the pasteboard, Arc's "Copied Current URL" popup with a share button springs in at the card's top-trailing corner for about 5 seconds, and DevTools doesn't open

### Requirement: Clearing history
Clearing browsing data, history included, from Chromium's settings or history page SHALL work in a native window.

#### Scenario: Deleting all history
- **WHEN** the user deletes all browsing history from `chrome://settings/clearBrowserData`
- **THEN** the history is deleted and Clair keeps running

### Requirement: Link status
Hovering a link SHALL show its URL in a small capsule at the bottom-leading corner of the card. The capsule SHALL fade in once the pointer has rested on links for about half a second, and fade out about half a second after the pointer leaves them; moving to another link while it shows SHALL update it at once. While a Peek shows, the capsule SHALL show at the Peek's bottom-leading corner instead.

#### Scenario: Hovering a link
- **WHEN** the pointer rests on a link
- **THEN** after about half a second the link's URL fades in, in a capsule at the card's bottom-leading corner, and about half a second after the pointer leaves the link it fades out

#### Scenario: Hovering a link in a Peek
- **WHEN** the pointer rests on a link inside a Peek
- **THEN** the link's URL fades in at the Peek's bottom-leading corner

### Requirement: Infobars
Infobars that Chromium attaches to a tab, such as the warning that the browser is being controlled by automated software or that an extension is debugging the browser, SHALL show as a bar at the top of that tab's card with their message, link and buttons, and SHALL act as Chromium's do.

#### Scenario: Extension debugging the browser
- **WHEN** an extension attaches the debugger to a tab
- **THEN** a bar at the top of the card says that the extension started debugging the browser, and its cancel button detaches the debugger

### Requirement: Toasts
Short confirmations that Chromium shows as toasts, such as "Image copied", SHALL show as a native toast at the bottom of the card that disappears on its own.

#### Scenario: Copying an image from the context menu
- **WHEN** the user chooses Copy Image from the page's context menu
- **THEN** a toast with Chromium's message appears at the bottom of the card and disappears after a few seconds

### Requirement: Crashed page
When a tab's page crashes or its renderer is killed, the card SHALL show a native view saying the page crashed, with a Reload button that reloads it.

#### Scenario: Renderer killed
- **WHEN** the user opens `chrome://crash` in a tab
- **THEN** the card shows that the page crashed with a Reload button, and Reload loads the tab's previous page again

### Requirement: Chromium bubbles placed in the native window
Chromium bubbles that remain, including permission prompts and page info, SHALL open attached to their control in the sidebar while the sidebar is shown, or to the card's top-leading corner while it is hidden or the window is in full screen. They SHALL work as they do in Chromium. Extension popups, and the install and remove confirmations, are not bubbles: `extensions` defines them.

#### Scenario: Permission prompt with the sidebar shown
- **WHEN** a page asks for the user's location while the sidebar is shown
- **THEN** Chromium's permission prompt opens attached to the site controls in the sidebar, and choosing Allow grants the permission to the page

#### Scenario: Permission prompt with the sidebar hidden
- **WHEN** a page asks for the user's location while the sidebar is hidden
- **THEN** the prompt opens at the card's top-leading corner, fully on screen, and choosing Block denies the permission

#### Scenario: Extension popup with the sidebar hidden
- **WHEN** an extension opens its popup while the sidebar is hidden
- **THEN** the popup window opens at the card's top-leading corner, fully on screen

### Requirement: Dialogs and windows Chromium keeps
Tab-modal dialogs SHALL show over the card of the tab they belong to, including JavaScript alerts and confirms, HTTP authentication and print preview. File pickers SHALL open as sheets or panels of the native window. The task manager and profile picker SHALL open in Chromium's own windows.

#### Scenario: JavaScript alert
- **WHEN** a page calls `alert("hi")`
- **THEN** the alert shows over that tab's card, and dismissing it returns control to the page

#### Scenario: Tab-scoped dialog
- **WHEN** HTTPS-first can't upgrade a site the user opens and falls back to HTTP, asking first
- **THEN** its "Ask before HTTP" dialog shows over that tab's card, and Clair keeps running

### Requirement: No bookmarks in the interface
Clair SHALL NOT show bookmarks in its interface: there SHALL be no Bookmarks menu, bookmarks bar, bookmark star or bookmark bubble, and their shortcuts (Cmd+D, Shift+Cmd+B, Opt+Cmd+B) SHALL do nothing. Bookmarks already in the profile SHALL be kept, and `chrome://bookmarks` SHALL still open when typed in the command bar.

#### Scenario: Menu bar
- **WHEN** the user looks through the menu bar
- **THEN** there is no Bookmarks menu, and the View menu has no "Always Show Bookmarks Bar" item

#### Scenario: Bookmark shortcut
- **WHEN** the user presses Cmd+D on a page
- **THEN** nothing happens, and no bookmark is created

### Requirement: Features the native window doesn't host
Chromium features with no place in the native window SHALL be unavailable rather than broken. Their menu items SHALL be hidden, and invoking them by shortcut, page API or extension API SHALL neither crash Clair nor leave UI behind. These include side panels, tab search, Chrome Labs, the EyeDropper, tab group UI, the app menu and the profile menu.

#### Scenario: Page asks for the EyeDropper
- **WHEN** a page calls `new EyeDropper().open()` after a click
- **THEN** the promise rejects, and Clair keeps running

#### Scenario: Tab search shortcut
- **WHEN** the user presses Shift+Cmd+A
- **THEN** nothing opens, and Clair keeps running

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
- **WHEN** another app is active and the user drags from the top 59 points of a Clair window's page, over empty space, text or a link
- **THEN** Clair becomes active, and the window comes forward and moves with the pointer

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

### Requirement: Window controls stay in place
The close button SHALL sit at a fixed place near the sidebar's top leading corner, with the minimize and zoom buttons after it at the system's spacing. On macOS 27 that place SHALL be Arc's: 12 points from the sidebar's leading edge and 16 points from its top. The buttons SHALL stay there, without showing anywhere else even for a frame, when the window's title changes, the window becomes or stops being key, or the window is resized.

#### Scenario: Default place on macOS 27
- **WHEN** a native window opens with the sidebar shown on macOS 27
- **THEN** the close button reads 12 points from the sidebar's leading edge and 16 points from its top, as Arc's does

#### Scenario: Page title changes
- **WHEN** the active tab navigates to a page with a different title
- **THEN** the window controls keep their place

#### Scenario: Window loses and regains focus
- **WHEN** another window becomes key and then the native window becomes key again
- **THEN** the window controls dim and brighten in place without moving

#### Scenario: Window resized
- **WHEN** the user resizes the window from any edge
- **THEN** the window controls keep their place relative to the sidebar's top leading corner

### Requirement: Top row laid out from the window controls
The sidebar's top-row buttons SHALL be vertically centred on the window controls, and the first of them SHALL start after the zoom button, wherever the system draws the window controls and whatever their size and spacing. The sidebar SHALL NOT narrow so far that the compact top row reaches the zoom button.

#### Scenario: Default top row on macOS 27
- **WHEN** a native window opens with the sidebar shown on macOS 27
- **THEN** the top-row buttons are centred 24 points below the sidebar's top, on the window controls' centre line, and the hide-sidebar button starts 7 points after the zoom button, at 81 points

#### Scenario: Window controls drawn elsewhere
- **WHEN** the system draws the window controls a few points higher or lower, or wider apart, than on macOS 27
- **THEN** the top-row buttons move to stay centred on them, and the hide-sidebar button still starts after the zoom button

#### Scenario: Narrowest sidebar
- **WHEN** the user drags the sidebar's edge as far left as it goes
- **THEN** the compact top row's back button starts after the zoom button

### Requirement: Window controls follow the sidebar
The window controls SHALL move with the sidebar: they SHALL slide with it while it hides, shows or is revealed over the page, sit at the same place relative to the revealed sidebar's corner, and be hidden while the sidebar is hidden and not revealed, and in page full screen. Where the system can't move them while the sidebar moves, they SHALL instead be hidden during the motion and shown at their place once it ends, and Clair SHALL log that once per launch.

#### Scenario: Hiding the sidebar
- **WHEN** the user presses Cmd+S with the sidebar shown
- **THEN** the window controls slide out with the sidebar and are hidden once it is hidden

#### Scenario: Revealed sidebar
- **WHEN** the sidebar is hidden and the pointer rests on the window's leading edge
- **THEN** the window controls slide in with the revealed sidebar and sit at the same place relative to its top leading corner as in the shown sidebar

#### Scenario: Page full screen
- **WHEN** a page enters full screen
- **THEN** the window controls are hidden until it leaves full screen

#### Scenario: System that can't move them during motion
- **WHEN** the sidebar hides, shows or is revealed on a macOS where the window controls can't follow it
- **THEN** the window controls are hidden while it moves, appear at their place once it stops, and Clair's log says once that they can't follow the sidebar on this macOS

### Requirement: New Incognito Window from the Dock with no windows
Clair's Dock menu SHALL offer New Incognito Window whether or not a window is open.

#### Scenario: No windows open
- **WHEN** the user closes every window, right-clicks Clair in the Dock and chooses New Incognito Window
- **THEN** an incognito window opens

### Requirement: Loading indicator
While the active tab loads a new document in its main frame (the state that shows stop), the window SHALL show Arc's loading indicator: a small capsule in the inset above the page card, centred on the card. As Arc's does, it SHALL run on time rather than on the load's progress: it pulses from the start of the load, then, if the load is still running after two pulses, widens into a track with a looping sweep.

#### Scenario: Loading a page
- **WHEN** the user opens a slow page in the active tab
- **THEN** a capsule pulses above the centre of the page card, widens into a sweeping track after about three seconds, and shrinks away once the page has loaded

#### Scenario: Sidebar hidden
- **WHEN** the sidebar is hidden and the active tab loads a page
- **THEN** the indicator shows above the centre of the card as it does with the sidebar shown

### Requirement: Loading indicator ends with the load
When the load ends, whether it finished, was stopped or failed, the loading indicator SHALL flash and shrink away, as Arc's does.

#### Scenario: Stopping a load
- **WHEN** the user clicks stop while a page loads
- **THEN** the indicator shrinks away

### Requirement: Loading indicator shows the active tab only
The loading indicator SHALL NOT show for frames loading on their own, same-document navigations or background tabs, nor in page full screen. Switching tabs SHALL show the newly active tab's state at once.

#### Scenario: Background tab loading
- **WHEN** a link opens in a background tab and loads there
- **THEN** the active tab's card shows no indicator

#### Scenario: Switching to a loading tab
- **WHEN** the user switches to a tab that is still loading
- **THEN** the indicator shows straight away

### Requirement: Tabs restored at launch
When Clair launches, it SHALL reopen the tabs that were open when it quit, as Arc does, unless the user chose otherwise in Chromium's "On startup" setting. This SHALL hold for a new profile without any setting being changed. Incognito tabs SHALL NOT come back.

#### Scenario: Quit and relaunch
- **WHEN** a user who never changed a setting quits Clair with several tabs open and launches it again
- **THEN** those tabs are open again

#### Scenario: The user chose a new tab page
- **WHEN** the user set "On startup" to "Open the New Tab page" in `chrome://settings`, quits and relaunches
- **THEN** Clair opens one window on a new tab page

#### Scenario: After a crash
- **WHEN** Clair crashes with tabs open and is launched again
- **THEN** the tabs reopen
