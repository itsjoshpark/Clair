# Spec Delta

## ADDED Requirements

### Requirement: A tab's row stands for its Peek
A Peek SHALL NOT have a row of its own: its parent tab's row SHALL show the Peek page's favicon as a small badge at its trailing end, and SHALL be highlighted while the Peek shows. Clicking that row SHALL show the tab with its Peek.

#### Scenario: Tab with a Peek
- **WHEN** a tab has a Peek open
- **THEN** the tab list has no row for the Peek, and the tab's row shows the Peek page's favicon as a badge

#### Scenario: Returning to a tab with a Peek
- **WHEN** the user selects another tab and then clicks the row of a tab with a Peek
- **THEN** that row is highlighted and the card shows the tab's page with its Peek

### Requirement: An expanded Peek goes below its tab
A Peek expanded into a tab SHALL be inserted directly below its parent tab, the one exception to new tabs going to the top of the list.

#### Scenario: Expanded Peek
- **WHEN** the user expands a Peek open on the third tab of five
- **THEN** the new tab is fourth in the list, directly below the third, and active

### Requirement: Row actions apply to the tab, not its Peek
A row's actions SHALL apply to the tab, not its Peek: closing the tab SHALL close its Peek too, moving it SHALL keep its Peek with it, and Copy Link and Duplicate SHALL use the tab's own page.

#### Scenario: Moving a tab with a Peek
- **WHEN** the third tab has a Peek and the user drags it above the first
- **THEN** it becomes the first tab and still has its Peek

#### Scenario: Copy Link on a tab with a Peek
- **WHEN** the user chooses Copy Link on the row of a tab with a Peek
- **THEN** the tab's own URL is copied, not the Peek's

### Requirement: Stop waits for a slow load
Reload SHALL turn into stop only once the active tab's load has run about 750 ms, as in Arc, so a page that loads quickly, or a Peek opening on one, never flashes stop. A tab that becomes active while it loads SHALL count from then, unless stop shows already. The button SHALL crossfade between reload and stop.

#### Scenario: A quick load
- **WHEN** the user opens a Peek, or follows a link, to a page that loads in 300 ms
- **THEN** the button shows reload throughout

#### Scenario: A slow load
- **WHEN** a page takes two seconds to load
- **THEN** the button turns into stop about 750 ms after the load starts, and back into reload when it ends
