# Spec Delta

## MODIFIED Requirements

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

### Requirement: Link status
Hovering a link SHALL show its URL in a small capsule at the bottom-leading corner of the card. The capsule SHALL fade in once the pointer has rested on links for about half a second, and fade out about half a second after the pointer leaves them; moving to another link while it shows SHALL update it at once. While a Peek shows, the capsule SHALL show at the Peek's bottom-leading corner instead.

#### Scenario: Hovering a link
- **WHEN** the pointer rests on a link
- **THEN** after about half a second the link's URL fades in, in a capsule at the card's bottom-leading corner, and about half a second after the pointer leaves the link it fades out

#### Scenario: Hovering a link in a Peek
- **WHEN** the pointer rests on a link inside a Peek
- **THEN** the link's URL fades in at the Peek's bottom-leading corner
