# Spec Delta

## ADDED Requirements

### Requirement: Pinned extensions wrap to the sidebar's width
Pinned extensions SHALL be tiles of equal width that fill the row. At most five SHALL fit across, and fewer if a tile would be under 29 points wide. They SHALL take as few rows as that allows and as few columns as those rows allow. A shorter last row SHALL stay at the leading edge with tiles of the same width.

#### Scenario: A single pinned extension
- **WHEN** one extension is pinned
- **THEN** its tile fills the row

#### Scenario: Five pinned with room for four across
- **WHEN** five extensions are pinned and the row has room for four tiles across
- **THEN** they show as a row of three and a row of two

#### Scenario: Nine pinned with room for four across
- **WHEN** nine extensions are pinned and the row has room for four tiles across
- **THEN** they show as three rows of three

#### Scenario: Ten pinned with room for four across
- **WHEN** ten extensions are pinned and the row has room for four tiles across
- **THEN** they show as rows of four, four and two

#### Scenario: Ten pinned at the default width
- **WHEN** ten extensions are pinned and the sidebar is at its default width
- **THEN** they show as two rows of five

#### Scenario: A very wide sidebar
- **WHEN** ten extensions are pinned and the user widens the sidebar as far as it goes
- **THEN** they still show in rows of five below the URL field, and the tiles grow to fill the row

#### Scenario: Resizing the sidebar
- **WHEN** the user narrows the sidebar until a row of five no longer fits
- **THEN** the tiles move into rows of four, and the tab list moves down to make room

### Requirement: Not-secure indicator
While Chromium rates the active tab's page as not secure, the URL field SHALL show a red `lock.slash.fill` icon at its leading end, before the host. Hovering it SHALL show the tooltip "Site is not secure", which SHALL also be its VoiceOver label. It SHALL be informational, not a control.

#### Scenario: HTTP page
- **WHEN** the active tab shows a plain HTTP page on a public host
- **THEN** the red icon shows before the host in the URL field

#### Scenario: Certificate error
- **WHEN** the user proceeds past a certificate error on an HTTPS page
- **THEN** the red icon shows before the host in the URL field

#### Scenario: Secure page
- **WHEN** the active tab shows an HTTPS page with a valid certificate
- **THEN** the URL field shows no such icon

#### Scenario: Localhost and internal pages
- **WHEN** the active tab shows a page on `localhost`, the new tab page or a `chrome:` page
- **THEN** the URL field shows no such icon

#### Scenario: Hovering the icon
- **WHEN** the pointer rests on the red icon
- **THEN** a tooltip reads "Site is not secure"

#### Scenario: Clicking the icon
- **WHEN** the user clicks the red icon
- **THEN** the icon doesn't respond and nothing opens

### Requirement: A revealed sidebar waits for its popovers
While the Site Control Center or the downloads list is open from a revealed sidebar, the sidebar SHALL stay revealed, wherever the pointer is. Once the popover closes, the sidebar SHALL conceal as usual if the pointer is outside it.

#### Scenario: Site Control Center open
- **WHEN** the Site Control Center is open from a revealed sidebar and the pointer moves over the page
- **THEN** the sidebar stays revealed

#### Scenario: Downloads list open
- **WHEN** the downloads list is open from a revealed sidebar and the pointer moves over the page
- **THEN** the sidebar stays revealed

#### Scenario: The popover closes
- **WHEN** a popover open from a revealed sidebar closes and the pointer is over the page
- **THEN** the sidebar conceals

## MODIFIED Requirements

### Requirement: Tooltips in Arc's wording
The sidebar's controls SHALL have Clair's own tooltips, never the system's, in Arc's wording and with their shortcuts: "Hide sidebar" ("Lock sidebar" while the hidden sidebar is revealed), "Go back", "Go forward", "Reload this page" or "Stop loading this page", "Copy URL", "Site Control Center", "Close tab" and "More options"; also "Downloads", "New" on the footer's plus, and a pinned extension's own name.

#### Scenario: Tooltip on back
- **WHEN** the pointer rests on the back button
- **THEN** a tooltip reads "Go back"

#### Scenario: Tooltip on a tab's close button
- **WHEN** the pointer rests on a tab's close button
- **THEN** a tooltip reads "Close tab" with the keys ⌘ and W

#### Scenario: Tooltip on the revealed sidebar's button
- **WHEN** the hidden sidebar is revealed and the pointer rests on its sidebar button
- **THEN** a tooltip reads "Lock sidebar"

### Requirement: Site controls and indicators
The URL field SHALL have a site-controls button, with the `slider.horizontal.2.square` symbol, on every tab including the new tab page, shown as `URL field buttons` defines, that opens the Site Control Center. While the active tab uses the camera, microphone, location or screen capture, the URL field SHALL show an indicator for each, which opens the matching controls. A blocked permission SHALL show no indicator; page info lists it.

#### Scenario: Page using the camera
- **WHEN** the active page is capturing the camera
- **THEN** a camera indicator shows in the URL field, and clicking it shows the camera permission controls for the site

#### Scenario: Opening site controls
- **WHEN** the user rests the pointer on the URL field of an HTTPS page and clicks the site-controls button
- **THEN** the Site Control Center opens attached to the button

#### Scenario: Opening site controls on the new tab page
- **WHEN** the active tab is the new tab page and the user rests the pointer on the URL field
- **THEN** the site-controls button shows, and clicking it opens the Site Control Center

### Requirement: Extension actions
The sidebar SHALL show the actions of extensions the user has pinned as tiles with their icons and badges, in a row of their own below the URL field at every sidebar width. Clicking an action SHALL run it as Chromium's toolbar would, opening its popup window beside the tile, as `extensions` defines. An action that's off for the active tab SHALL be dimmed and SHALL NOT run when clicked. The row SHALL show only while some extension is pinned.

#### Scenario: Pinned extension with a popup
- **WHEN** the user clicks a pinned extension's tile and its action has a popup
- **THEN** the popup window opens beside that tile and is interactive

#### Scenario: Pinned extension that's off for the tab
- **WHEN** a pinned extension's action is off for the active tab and the user clicks its tile
- **THEN** the tile stays dimmed and the action doesn't run, and right-clicking the tile still shows the extension's menu

#### Scenario: Badge text
- **WHEN** an extension sets its action's badge text to "3"
- **THEN** its tile in the sidebar shows a "3" badge

#### Scenario: Badge with the default colours
- **WHEN** an extension sets badge text without setting its colours
- **THEN** the badge shows black text on white in Light Mode, and white text on near-black in Dark Mode

#### Scenario: Badge colours set by the extension
- **WHEN** an extension sets its badge's background with `chrome.action.setBadgeBackgroundColor` and its text colour with `chrome.action.setBadgeTextColor`
- **THEN** the badge uses both colours, and without a text colour it uses black or white, whichever contrasts more with the background

#### Scenario: Extension without a pin
- **WHEN** the user opens the Site Control Center and chooses an unpinned extension
- **THEN** its action runs, and its popup window opens beside the site-controls button

#### Scenario: Nothing pinned
- **WHEN** extensions are installed and none of them is pinned
- **THEN** the sidebar shows no row for them

#### Scenario: Newly installed extension
- **WHEN** the user installs an extension with an action
- **THEN** its tile appears among the pinned actions, and the row shows if it was hidden
