# site-control-center Specification

## Purpose
Defines the native Site Control Center that the site-controls button opens: the grid of extensions, their pin badges, the tile for adding extensions, the Site Info pill and the "…" menu, following Arc.

## Requirements
### Requirement: Opening the Site Control Center
Clicking the URL field's site-controls button SHALL open the Site Control Center, a native popover attached below the button with its arrow pointing at it. Clicking the button again, pressing Esc or clicking outside the popover SHALL close it.

#### Scenario: Opening
- **WHEN** the user clicks the site-controls button
- **THEN** the Site Control Center opens attached below the button

#### Scenario: Clicking the button again
- **WHEN** the Site Control Center is open and the user clicks the site-controls button
- **THEN** it closes and doesn't open again

#### Scenario: Esc
- **WHEN** the Site Control Center is open and the user presses Esc
- **THEN** it closes

### Requirement: Button stays while the Site Control Center is open
While the Site Control Center is open, the site-controls button SHALL stay shown, wherever the pointer is.

#### Scenario: Pointer moves into the popover
- **WHEN** the Site Control Center is open and the pointer moves off the sidebar
- **THEN** the site-controls button stays shown

### Requirement: Grid of extensions
Under the heading "Extensions", the Site Control Center SHALL show every extension with an action as an icon tile, in rows of four. Pinned extensions SHALL come first, in their pinned order, followed by the others in alphabetical order. A tile's tooltip SHALL be the extension's name, which SHALL also be its VoiceOver label.

#### Scenario: Order
- **WHEN** two of ten extensions are pinned and the Site Control Center opens
- **THEN** the two pinned extensions come first in their pinned order, followed by the other eight from A to Z

#### Scenario: Tooltip
- **WHEN** the pointer rests on a tile
- **THEN** a tooltip shows the extension's name

### Requirement: Running an extension from the grid
Clicking a tile SHALL close the Site Control Center and run the extension's action as Chromium's toolbar would. Its popup window SHALL open beside the site-controls button.

#### Scenario: Extension with a popup
- **WHEN** the user clicks the tile of an extension whose action has a popup
- **THEN** the Site Control Center closes, and the popup window opens beside the site-controls button

### Requirement: Extensions turned off for the tab
A tile whose extension's action is off for the active tab SHALL be dimmed and SHALL NOT run when clicked. Its pin badge and right-click menu SHALL keep working.

#### Scenario: Clicking a dimmed tile
- **WHEN** an extension's action is off for the active tab and the user clicks its tile
- **THEN** the tile stays dimmed, the action doesn't run, and the Site Control Center stays open

### Requirement: Pin badges
A pinned extension's tile SHALL show a solid pin badge at its bottom-trailing corner. Under the pointer, an unpinned extension's tile SHALL show a faint one. Clicking the badge SHALL pin or unpin the extension and leave the Site Control Center open. Its VoiceOver label SHALL be "Pin" or "Unpin".

#### Scenario: Pinning from the grid
- **WHEN** the pointer rests on an unpinned tile and the user clicks its pin badge
- **THEN** the extension is added to the sidebar's pinned extensions, its badge turns solid, and the Site Control Center stays open

#### Scenario: Unpinning from the grid
- **WHEN** the user clicks a pinned tile's pin badge
- **THEN** the extension leaves the sidebar's pinned extensions, and the Site Control Center stays open

### Requirement: Adding an extension
After the last extension, the grid SHALL end with a tile with a plus, with the tooltip "Add Extension". Clicking it SHALL close the Site Control Center and open the Chrome Web Store in a new tab. It SHALL show even when no extension has an action.

#### Scenario: No extensions installed
- **WHEN** no extension has an action and the Site Control Center opens
- **THEN** the grid shows only the plus tile

#### Scenario: Opening the store
- **WHEN** the user clicks the plus tile
- **THEN** the Site Control Center closes, and the Chrome Web Store opens in a new tab

### Requirement: Site Info
The Site Control Center's footer SHALL have a "Site Info" pill. Clicking it SHALL close the Site Control Center and open Chromium's page info for the active tab, attached to the site-controls button, showing its connection security and permissions. The pill SHALL be hidden for `chrome:`, `devtools:`, `view-source:` and `file:` pages.

#### Scenario: HTTPS page
- **WHEN** the active tab shows an HTTPS page and the user clicks "Site Info"
- **THEN** the Site Control Center closes, and page info opens attached to the site-controls button and shows that the connection is secure

#### Scenario: New tab page
- **WHEN** the active tab is the new tab page and the Site Control Center opens
- **THEN** it shows no "Site Info" pill

### Requirement: More menu
The footer's trailing end SHALL have a "…" button whose menu offers "Manage Extensions…", which opens Chromium's extensions page in a new tab, "Add Extension…", which opens the Chrome Web Store in a new tab, and "All Site Settings…", which opens Chromium's site settings in a new tab. Choosing an item SHALL close the Site Control Center.

#### Scenario: Manage Extensions
- **WHEN** the user chooses "Manage Extensions…" in the "…" menu
- **THEN** the Site Control Center closes, and `chrome://extensions` opens in a new tab

#### Scenario: All Site Settings
- **WHEN** the user chooses "All Site Settings…" in the "…" menu
- **THEN** the Site Control Center closes, and Chromium's site settings open in a new tab
