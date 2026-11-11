# Spec Delta

## MODIFIED Requirements

### Requirement: Settings pages
The Settings window SHALL show a toolbar of pages, General, Links and Advanced in that order, with each page's rows grouped in rounded cards. Choosing a toolbar item SHALL show that page in place of the current one, and the window's title SHALL be the shown page's name. The window SHALL open on General the first time, and afterwards on the page last shown, across launches.

#### Scenario: First opening
- **WHEN** the user opens Settings for the first time
- **THEN** the window shows the General page, titled "General", with toolbar items General, Links and Advanced

#### Scenario: Switching pages
- **WHEN** the Settings window shows General and the user chooses Advanced in the toolbar
- **THEN** the window shows the Advanced page in place of General, and its title becomes "Advanced"

#### Scenario: Last page remembered
- **WHEN** the user leaves the Settings window on Advanced, quits Clair, relaunches it and opens Settings
- **THEN** the window shows the Advanced page

## ADDED Requirements

### Requirement: Peek toggle
The Links page SHALL have a toggle labelled "Open a Peek window when clicking on links with Shift held" that shows and changes the Peek preference, kept for the user across launches. It SHALL be on when no value is stored. A change SHALL apply to open windows at once. While it's off, Shift+clicking a link SHALL open a new window, as in Chromium.

#### Scenario: Default
- **WHEN** Clair has no stored value for the preference and the user opens the Links page
- **THEN** the toggle is on

#### Scenario: Turning it off
- **WHEN** the user turns the toggle off and Shift+clicks a link in an open window
- **THEN** the link opens in a new window, and no Peek opens

#### Scenario: Turning it back on
- **WHEN** the user turns the toggle on again and Shift+clicks a link
- **THEN** the link opens in a Peek
