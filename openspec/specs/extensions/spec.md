# extensions Specification

## Purpose
Defines how Clair installs, updates, confirms, pins and shows Chrome extensions, following Arc: installs from the Chrome Web Store, automatic updates, native confirmations, and popups in a small window.

## Requirements

### Requirement: Installing from the Chrome Web Store
Clair SHALL let users install extensions from `https://chromewebstore.google.com`. The store's install button SHALL be enabled, and installing SHALL download the extension from Google and install it after the user confirms.

#### Scenario: Installing a store extension
- **WHEN** the user opens an extension's page in the Chrome Web Store, clicks its install button and confirms
- **THEN** the extension is downloaded from Google, installed and enabled, and the store page shows it as installed

#### Scenario: The store's download stays out of Downloads
- **WHEN** an extension is installed from the store
- **THEN** its package doesn't appear in the sidebar's downloads list

### Requirement: Other installation paths kept
Clair SHALL keep the installation paths it had before, including CRX files with the "Always prompt for install" flag (`--extension-mime-request-handling=always-prompt-for-install`). Installed extensions SHALL run with full Chrome extension API support, except for APIs that show UI the native window doesn't host, such as side panels, as `browser-window` defines.

#### Scenario: Installing an extension from a CRX file
- **WHEN** a user enables "Always prompt for install" for extension MIME handling in `chrome://flags`, and then opens a link to an extension's CRX file
- **THEN** Clair asks to confirm the install, and after installation the extension runs and its action is listed in the Site Control Center

### Requirement: Store wording names Clair
On the Chrome Web Store's pages, the install button SHALL read "Add to Clair" and, for an installed extension, "Remove from Clair", and the store's prompts to switch to Chrome SHALL be removed. The rest of the store's text SHALL be left as the store wrote it.

#### Scenario: Extension not installed
- **WHEN** the user opens the store page of an extension that isn't installed
- **THEN** its button reads "Add to Clair", and no banner or popup asks the user to switch to Chrome

#### Scenario: Extension installed
- **WHEN** the user opens the store page of an installed extension
- **THEN** its button reads "Remove from Clair"

### Requirement: Extensions update automatically
Clair SHALL check for updates to installed extensions whose update URL is the Chrome Web Store's, or that set their own, and SHALL install the updates, as Chrome does. Checks SHALL contact the extension's update server only, and a profile with no such extensions SHALL make no update requests.

#### Scenario: A newer version is published
- **WHEN** a store extension is installed and the store publishes a newer version
- **THEN** Clair installs the newer version at its next update check without the user doing anything

#### Scenario: No store extensions
- **WHEN** a profile has no extensions with an update URL
- **THEN** Clair makes no extension update requests to Google

### Requirement: Install confirmation as a native sheet
Before an extension is installed, Clair SHALL ask in a Clair dialog (`dialogs`) on the window. The dialog SHALL show the extension's icon, the title "Add “<name>” to Clair?", the heading "It can:" followed by the extension's permissions as a list, and the buttons "Add Extension" (default, Return) and "Cancel" (Esc). The window SHALL stay blocked until the user answers.

#### Scenario: Confirming an install
- **WHEN** the user clicks "Add to Clair" on a store page
- **THEN** a sheet asks "Add “<name>” to Clair?" with the extension's permissions under "It can:", and pressing Return installs the extension

#### Scenario: Cancelling an install
- **WHEN** the install sheet is shown and the user presses Esc or clicks "Cancel"
- **THEN** the sheet closes, the extension isn't installed, and the store page shows it as not installed

#### Scenario: Extension without permissions
- **WHEN** the extension being installed asks for no permissions
- **THEN** the sheet shows the title and buttons without the "It can:" list

#### Scenario: Many permissions
- **WHEN** the extension being installed asks for more permissions than fit
- **THEN** the list scrolls inside the dialog, and the buttons stay visible

### Requirement: Other install prompts as native sheets
Chromium's other install prompts, such as re-enabling an extension whose update asks for new permissions or an extension asking for optional permissions, SHALL use the same kind of sheet. Each SHALL show Chromium's own title, permissions and button labels for that prompt, and answering it SHALL have the effect Chromium's prompt has.

#### Scenario: Optional permission request
- **WHEN** an extension calls `chrome.permissions.request` for a permission it doesn't have
- **THEN** a sheet shows Chromium's request text and the permission, and accepting grants it while cancelling leaves it denied

### Requirement: Remove confirmation as a native sheet
When an extension is removed through a path that asks for confirmation, such as the store's "Remove from Clair" button, Clair SHALL ask in a Clair dialog (`dialogs`) on the window. The dialog SHALL have the title "Remove “<name>” from Clair?", the extension's icon, a "Remove Extension" button (default, Return) that isn't marked destructive, as Arc's isn't, "Cancel" (Esc), and no "report abuse" option.

#### Scenario: Removing from the store
- **WHEN** the user clicks "Remove from Clair" on an installed extension's store page and clicks "Remove Extension"
- **THEN** the extension is removed, its button leaves the sidebar, and the store page shows it as not installed

#### Scenario: Keeping the extension
- **WHEN** the remove sheet is shown and the user presses Esc
- **THEN** the extension stays installed

### Requirement: No post-install box
After an extension is installed, Clair SHALL NOT show Chromium's "has been added" box or any other dialog about the install.

#### Scenario: Installed from the store
- **WHEN** the user confirms an install from the store
- **THEN** no box, bubble or dialog appears after the extension is installed, and the window stays usable

### Requirement: New extensions pinned to the sidebar
An extension the user has just installed through a confirmation SHALL be pinned, so its action shows as a button in the sidebar. Extensions installed without the user, such as by policy or sync, and updates to installed extensions SHALL keep their pinned state.

#### Scenario: Installing an extension with an action
- **WHEN** the user installs an extension that has a toolbar action
- **THEN** its button appears in the sidebar's pinned extensions, after those already pinned

#### Scenario: Update keeps an unpinned extension unpinned
- **WHEN** the user has unpinned an extension and it updates
- **THEN** it stays unpinned

### Requirement: Extension popups in a window
An extension's popup SHALL open in a small titled window whose only enabled control is the close button. The window SHALL be movable by its title bar, and SHALL first open beside the control that opened it, following `sidebar`. Its page SHALL show whole, at the size the extension asks for, within Chromium's limits of 25×25 to 800×600 points.

#### Scenario: Opening a popup
- **WHEN** the user clicks a pinned extension's button whose action has a popup
- **THEN** a window with a close button opens beside the button, showing the whole popup page with no part clipped

#### Scenario: Moving a popup
- **WHEN** the user drags the popup window's title bar
- **THEN** the window moves and stays open, and the popup keeps working

#### Scenario: Page grows after it opens
- **WHEN** the popup page's content grows after the window has opened
- **THEN** the window grows to fit it, keeping its top-leading corner where it is, and stays on screen

### Requirement: Closing an extension popup
The popup window SHALL close when the user clicks its close button, presses Esc, clicks anywhere outside it, or clicks the button that opened it, and when the page or Chromium closes it. Clicking the opening button SHALL only close the popup, not open it again.

#### Scenario: Clicking outside
- **WHEN** a popup window is open and the user clicks the page in the browser window
- **THEN** the popup closes and the click reaches the page

#### Scenario: Esc
- **WHEN** a popup window is key and the user presses Esc
- **THEN** the popup closes

#### Scenario: Close button
- **WHEN** the user clicks the popup window's close button
- **THEN** the popup closes, and Chromium treats it as closed by the user

### Requirement: Opening a popup from the extension API
An extension SHALL be able to open its own popup with `chrome.action.openPopup()` in an active Clair window. The popup SHALL open as if its button had been clicked: beside its pinned tile, or beside the site-controls button when it isn't pinned.

#### Scenario: openPopup from a background script
- **WHEN** an extension with a popup calls `chrome.action.openPopup()` while a Clair window is active
- **THEN** the call succeeds and the extension's popup window opens beside its tile

#### Scenario: openPopup for an unpinned extension
- **WHEN** an unpinned extension with a popup calls `chrome.action.openPopup()` while a Clair window is active
- **THEN** the call succeeds and the extension's popup window opens beside the site-controls button

### Requirement: Extension context menu
Right-clicking or Control-clicking a pinned extension's tile, or a tile in the Site Control Center's grid, SHALL show a native menu built from Chromium's extension menu. It SHALL offer the items Chromium offers for that extension, including its name (which opens its home page), its own `chrome.contextMenus` action items, site access where it applies, Options, Pin or Unpin, Remove and Manage. It SHALL NOT offer a side panel item or Inspect Popup.

#### Scenario: Right-clicking a pinned button
- **WHEN** the user right-clicks a pinned extension's tile
- **THEN** a native menu with that extension's items opens, and the extension's popup doesn't open

#### Scenario: Pinning from a list row
- **WHEN** the user right-clicks an unpinned extension's tile in the Site Control Center and chooses Pin
- **THEN** its tile appears among the sidebar's pinned actions

#### Scenario: Right-clicking a tile in the Site Control Center
- **WHEN** the user right-clicks a tile in the Site Control Center's grid
- **THEN** a native menu with that extension's items opens, and the extension's popup doesn't open

#### Scenario: Removing from the menu
- **WHEN** the user chooses the menu's Remove item
- **THEN** the remove sheet asks for confirmation, as `Remove confirmation as a native sheet` defines

#### Scenario: Unpinning from the menu
- **WHEN** the user chooses Unpin in a pinned extension's menu
- **THEN** its tile leaves the sidebar's pinned actions

### Requirement: No uninstall pages
When an extension is removed, Clair SHALL NOT open the page the extension set with `chrome.runtime.setUninstallURL`. The API call SHALL still succeed.

#### Scenario: Removing an extension with an uninstall page
- **WHEN** the user removes an extension that has set an uninstall URL
- **THEN** the extension is removed and no new tab opens

### Requirement: Extensions menu
The menu bar SHALL have an Extensions menu just left of Window. It SHALL list every extension with an action in the frontmost browser window's profile, with its icon, in alphabetical order, followed by a separator, "Add Extension…" and "Manage Extensions…".

#### Scenario: Listing extensions
- **WHEN** three extensions are installed and the user opens the Extensions menu
- **THEN** it lists the three with their icons from A to Z, then a separator, "Add Extension…" and "Manage Extensions…"

#### Scenario: Managing extensions
- **WHEN** the user chooses "Manage Extensions…"
- **THEN** `chrome://extensions` opens in a new tab

#### Scenario: Adding an extension
- **WHEN** the user chooses "Add Extension…"
- **THEN** the Chrome Web Store opens in a new tab

### Requirement: Running an extension from the Extensions menu
Choosing an extension in the Extensions menu SHALL run its action as Chromium's toolbar would, with its popup opening beside the site-controls button. An extension whose action is off for the active tab SHALL be listed but unavailable.

#### Scenario: Choosing an extension
- **WHEN** the user chooses an extension with a popup from the Extensions menu
- **THEN** its popup window opens beside the site-controls button

#### Scenario: Extension off for the tab
- **WHEN** an extension's action is off for the active tab and the user opens the Extensions menu
- **THEN** the extension is listed but can't be chosen
