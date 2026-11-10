# Spec Delta

## ADDED Requirements

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

## MODIFIED Requirements

### Requirement: Other installation paths kept
Clair SHALL keep the installation paths it had before, including CRX files with the "Always prompt for install" flag (`--extension-mime-request-handling=always-prompt-for-install`). Installed extensions SHALL run with full Chrome extension API support, except for APIs that show UI the native window doesn't host, such as side panels, as `browser-window` defines.

#### Scenario: Installing an extension from a CRX file
- **WHEN** a user enables "Always prompt for install" for extension MIME handling in `chrome://flags`, and then opens a link to an extension's CRX file
- **THEN** Clair asks to confirm the install, and after installation the extension runs and its action is listed in the Site Control Center

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
