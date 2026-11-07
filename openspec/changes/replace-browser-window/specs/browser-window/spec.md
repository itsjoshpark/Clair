# Spec Delta

## Purpose

Defines Clair's native browser window: which windows are native, how the window looks and hosts the page and DevTools, the native replacements for UI that lived in Chromium's window, and how Chromium's remaining UI, its bookmarks UI and unsupported features behave inside it.

## ADDED Requirements

### Requirement: Normal browser windows are native
Every normal browser window, including incognito and guest windows, SHALL be a native window drawn by the native layer, with no Chromium tab strip, toolbar, omnibox or bookmarks bar. Pop-up, app, Picture-in-Picture and undocked DevTools windows SHALL keep Chromium's own windows.

#### Scenario: Launching packaged Clair
- **WHEN** a user launches packaged Clair
- **THEN** each browser window it opens, restored or new, is the native window, and none shows Chromium's tab strip or toolbar

#### Scenario: Incognito window
- **WHEN** a user opens a new incognito window
- **THEN** it is the native window in a dark appearance, labelled as incognito in its sidebar, and its tabs use the incognito profile

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
- **THEN** the native window shows as inactive: the active tab's highlight fades and the window controls dim, as other macOS windows do

### Requirement: Page shown in the card
The card SHALL show the active tab's page, resized with the window and the sidebar, and SHALL switch to the newly active tab's page as soon as the active tab changes. Hidden tabs' pages SHALL be reported to the page as hidden.

#### Scenario: Switching tabs
- **WHEN** the user selects another tab
- **THEN** the card shows that tab's page, and the previous page reports `document.visibilityState` as `hidden`

#### Scenario: Resizing the window
- **WHEN** the user resizes the window
- **THEN** the page's viewport follows the card's size, with no stretched or stale frame left once resizing stops

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
The native window SHALL support macOS full screen. When a page asks for full screen, as a video does, the page SHALL fill the screen alone, without the sidebar or card insets, and Esc SHALL end it.

#### Scenario: Window full screen
- **WHEN** the user chooses View > Enter Full Screen
- **THEN** the window enters macOS full screen and keeps its sidebar state

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

### Requirement: Link status
Hovering a link SHALL show its URL in a small capsule at the bottom-leading corner of the card, which SHALL disappear when the pointer leaves the link.

#### Scenario: Hovering a link
- **WHEN** the pointer rests on a link
- **THEN** the link's URL shows in a capsule at the card's bottom-leading corner, and leaving the link hides it

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
Chromium bubbles that remain, including permission prompts, page info, extension popups and extension install prompts, SHALL open attached to their control in the sidebar while the sidebar is shown, or to the card's top-leading corner while it is hidden or the window is in full screen. They SHALL work as they do in Chromium.

#### Scenario: Permission prompt with the sidebar shown
- **WHEN** a page asks for the user's location while the sidebar is shown
- **THEN** Chromium's permission prompt opens attached to the site controls in the sidebar, and choosing Allow grants the permission to the page

#### Scenario: Permission prompt with the sidebar hidden
- **WHEN** a page asks for the user's location while the sidebar is hidden
- **THEN** the prompt opens at the card's top-leading corner, fully on screen, and choosing Block denies the permission

### Requirement: Dialogs and windows Chromium keeps
Tab-modal dialogs SHALL show over the card of the tab they belong to, including JavaScript alerts and confirms, HTTP authentication and print preview. File pickers SHALL open as sheets or panels of the native window. The task manager and profile picker SHALL open in Chromium's own windows.

#### Scenario: JavaScript alert
- **WHEN** a page calls `alert("hi")`
- **THEN** the alert shows over that tab's card, and dismissing it returns control to the page

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
