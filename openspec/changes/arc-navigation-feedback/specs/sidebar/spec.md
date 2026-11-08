# Spec Delta

## ADDED Requirements

### Requirement: Reload and stop follow the page's own loading
Reload SHALL become stop only while the active tab loads a new document in its main frame, as Chromium's toolbar decides. A frame inside the page loading on its own, or a same-document navigation, SHALL leave reload in place. A tab row's loading spinner SHALL follow the same state.

#### Scenario: Frames loading after the page
- **WHEN** a page finishes loading and then an iframe in it reloads every second for ten seconds
- **THEN** the button shows reload throughout, and the tab row shows no spinner

#### Scenario: Same-document navigation
- **WHEN** the page calls `history.pushState` or changes the URL's fragment
- **THEN** the button keeps showing reload

### Requirement: Stop held under the pointer
When a load ends while the pointer is on the stop button, the button SHALL stay inert until the pointer leaves it or about 1.35 seconds pass, and then show reload, so a second click doesn't start a reload by accident.

#### Scenario: Load ends under the pointer
- **WHEN** the user rests the pointer on stop while a page loads, and the load ends
- **THEN** the button stays inert while the pointer stays on it, for up to about 1.35 seconds, and then shows reload

### Requirement: Navigation history menu
Right-clicking or Control-clicking the back or forward button SHALL open a native menu attached to the button listing the active tab's pages in that direction, nearest first, each with its favicon and title (or its URL when it has no title), up to the number of entries Chromium's own back/forward menu shows. The compact top row's back and forward buttons SHALL behave the same. When the tab can't go that way, the button SHALL open no menu.

#### Scenario: Right-click
- **WHEN** the user right-clicks the back button after visiting two pages
- **THEN** the history menu opens under the button without a navigation, listing the previous page first

#### Scenario: Nothing to go back to
- **WHEN** the active tab has no previous page and the user right-clicks back
- **THEN** no menu opens

### Requirement: Choosing a history entry
Choosing an entry in the history menu SHALL take the tab to that page. Choosing it with Cmd held SHALL open that page in a new background tab at the top of the tab list and leave the active tab where it is.

#### Scenario: Going back two pages
- **WHEN** the user has visited pages A, B and C in one tab, right-clicks back and chooses A
- **THEN** the tab shows A, and forward lists B then C

#### Scenario: Opening an entry in a new tab
- **WHEN** the user Cmd-chooses an entry in the back menu
- **THEN** a new tab opens at the top of the tab list on that page, in the background, and the active tab doesn't navigate
