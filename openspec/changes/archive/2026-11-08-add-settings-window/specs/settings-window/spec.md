# Spec Delta

## Purpose

Clair's native Settings window, in the style of Arc's: how Settings… opens it, its pages and their rows, and the hand-off to `chrome://settings` for Chromium's own settings.

## ADDED Requirements

### Requirement: Settings… opens the Settings window
The application menu SHALL contain exactly one Settings item, titled "Settings…" with the shortcut Cmd+,. Choosing it SHALL open Clair's native Settings window without opening a browser tab or window. There SHALL be at most one Settings window: choosing Settings… while it's open SHALL bring that window to the front.

#### Scenario: Opening Settings from the menu
- **WHEN** the user chooses Clair › Settings…
- **THEN** the native Settings window opens, and no tab showing `chrome://settings` opens

#### Scenario: One Settings item
- **WHEN** the user opens the Clair menu
- **THEN** it has exactly one item titled "Settings…", with the shortcut Cmd+,, and no item titled "Preferences…"

#### Scenario: Opening Settings with the shortcut
- **WHEN** a browser window is key and the user presses Cmd+,
- **THEN** the native Settings window opens

#### Scenario: Opening Settings again
- **WHEN** the Settings window is open behind a browser window and the user chooses Settings… again
- **THEN** the same Settings window comes to the front, and no second one opens

#### Scenario: No browser window open
- **WHEN** no browser window is open and the user chooses Settings…
- **THEN** the Settings window opens, and no browser window opens

### Requirement: Settings pages
The Settings window SHALL show a toolbar of pages, General and Advanced in that order, with each page's rows grouped in rounded cards. Choosing a toolbar item SHALL show that page in place of the current one, and the window's title SHALL be the shown page's name. The window SHALL open on General the first time, and afterwards on the page last shown, across launches.

#### Scenario: First opening
- **WHEN** the user opens Settings for the first time
- **THEN** the window shows the General page, titled "General", with toolbar items General and Advanced

#### Scenario: Switching pages
- **WHEN** the Settings window shows General and the user chooses Advanced in the toolbar
- **THEN** the window shows the Advanced page in place of General, and its title becomes "Advanced"

#### Scenario: Last page remembered
- **WHEN** the user leaves the Settings window on Advanced, quits Clair, relaunches it and opens Settings
- **THEN** the window shows the Advanced page

### Requirement: Default browser row
The General page SHALL say whether Clair is the default web browser. When it isn't, the row SHALL offer "Make Default", which asks macOS to make Clair the default browser, leaving the confirmation to macOS. When it is, the row SHALL say so and offer no button. The row SHALL reflect a change made elsewhere, such as in System Settings, whenever the Settings window comes to the front.

#### Scenario: Clair isn't the default browser
- **WHEN** another browser is the default and the user opens the General page
- **THEN** the row says Clair isn't the default browser and offers "Make Default"

#### Scenario: Making Clair the default
- **WHEN** the user chooses "Make Default" and confirms macOS's prompt
- **THEN** Clair becomes the default web browser, and the row says Clair is the default browser, with no button

#### Scenario: Changed in System Settings
- **WHEN** the Settings window is open on General, the user changes the default browser in System Settings, and then brings the Settings window to the front
- **THEN** the row shows the new state

### Requirement: Window dragging toggle
The Advanced page SHALL have a toggle labelled "Allow window dragging from the top of webpages" that shows and changes the window dragging preference of `browser-window`. It SHALL be on when no value is stored, and a change SHALL apply to open browser windows at once, without relaunching Clair.

#### Scenario: Default
- **WHEN** Clair has no stored value for the preference and the user opens the Advanced page
- **THEN** the toggle is on

#### Scenario: Turning it off
- **WHEN** the user turns the toggle off and then drags from empty space at the top of an open browser window's page
- **THEN** the drag reaches the page and the window doesn't move

#### Scenario: Turning it back on
- **WHEN** the user turns the toggle on again and drags from empty space at the top of the page
- **THEN** the window moves with the pointer

### Requirement: More Settings opens Chromium's settings
The Advanced page SHALL have a "More Settings…" button that opens `chrome://settings` in a new foreground tab of the most recently active browser window, or in a new browser window if none is open, and closes the Settings window. `chrome://settings` SHALL stay reachable by URL as well.

#### Scenario: More Settings with a browser window open
- **WHEN** a browser window is open and the user chooses "More Settings…" on the Advanced page
- **THEN** the Settings window closes, and that window comes to the front with a new tab showing `chrome://settings`

#### Scenario: More Settings with no browser window open
- **WHEN** no browser window is open and the user chooses "More Settings…"
- **THEN** the Settings window closes, and a new browser window opens showing `chrome://settings`
