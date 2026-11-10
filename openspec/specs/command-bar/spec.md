# command-bar Specification

## Purpose
Defines the command bar, the floating field where users type URLs and searches, switch to open tabs and open sites, with suggestions from Chromium's autocomplete.

## Requirements

### Requirement: Opening a new tab from the command bar
Cmd+T, File > New Tab and the sidebar's "New Tab" row SHALL open the command bar empty. Choosing a result SHALL open it in a new tab. No tab SHALL be created until a result is chosen, and the "New Tab" row SHALL be highlighted while the command bar is open for it.

#### Scenario: Typing a URL
- **WHEN** the user presses Cmd+T, types `example.com` and presses Return
- **THEN** a new tab opens `https://example.com/` at the top of the tab list, and it is active

#### Scenario: Dismissing
- **WHEN** the user presses Cmd+T and then Esc
- **THEN** the command bar closes and no tab is created

#### Scenario: Pressing Cmd+T again
- **WHEN** the user presses Cmd+T twice
- **THEN** the second press closes the command bar, as in Arc, and no tab is created

### Requirement: Editing the current URL
Cmd+L, File > Open Location Bar and a click on the URL field SHALL open the command bar holding the active tab's full URL, all selected. Choosing a result SHALL navigate the active tab. Cmd+L while that command bar is open SHALL close it. The menu item SHALL read "Open Location Bar" rather than Chromium's "Open Location…".

#### Scenario: Navigating the current tab
- **WHEN** the user presses Cmd+L, types `example.org` and presses Return
- **THEN** the active tab navigates to `https://example.org/`, and no new tab is created

#### Scenario: Pressing Cmd+L again
- **WHEN** the user presses Cmd+L twice
- **THEN** the second press closes the command bar and the active tab is unchanged

### Requirement: Command bar in a new window
A window that opens on a single new tab page SHALL open with the command bar showing, so typing goes straight into it, as in Arc. Esc SHALL close it and leave the new tab page.

#### Scenario: New window
- **WHEN** the user presses Cmd+N and types `example.org` and Return
- **THEN** the new window's tab navigates to `https://example.org/`

### Requirement: Command bar appearance
The command bar SHALL float over the window, horizontally centered on the whole window and about a third of the way down, above the sidebar and the page, without dimming the page. It SHALL have a search icon, the placeholder "Search or Enter URL…" (or "Search…" while searching a site by its keyword), and the results below the field.

#### Scenario: Position
- **WHEN** the command bar opens in a window that is wider than the command bar
- **THEN** it is centered on the window, not on the card, and the page behind it isn't dimmed

#### Scenario: Results appearing
- **WHEN** the user presses Cmd+L and starts typing
- **THEN** the field stays where it opened, and the results grow the panel downwards

#### Scenario: Window too narrow
- **WHEN** the command bar opens in a window narrower than its usual width
- **THEN** it shrinks to fit inside the window

### Requirement: Suggestions from Chromium's autocomplete
As the user types, the command bar SHALL list suggestions from Chromium's autocomplete for the window's profile, the sources the omnibox uses apart from bookmarks: what-you-typed, history, open tabs and the default search engine. Bookmarks SHALL NOT be suggested, as the interface has none. Each row SHALL show an icon, a title and, when it differs, the URL's domain. The first row SHALL be selected.

#### Scenario: History match
- **WHEN** the user has visited `https://en.wikipedia.org/wiki/Arc` and types `wiki arc`
- **THEN** a row for that page is listed with its title and `en.wikipedia.org`

#### Scenario: Search
- **WHEN** the user types `clair browser` and presses Return
- **THEN** the default search engine's results page for "clair browser" opens

#### Scenario: Incognito
- **WHEN** the command bar is used in an incognito window
- **THEN** it suggests from the incognito profile's autocomplete, and what is typed isn't added to the regular profile's history

### Requirement: Switching to an open tab
A suggestion for a page that is already open in a tab of the same profile SHALL show "Switch to Tab", and choosing it SHALL activate that tab, in its window, instead of opening the page again.

#### Scenario: Switching
- **WHEN** a tab has `https://example.com/` open and the user presses Cmd+T, types `example.com` and chooses the "Switch to Tab" row
- **THEN** that existing tab becomes active, and no tab is created

### Requirement: Results with an empty query
With an empty query, the command bar SHALL list the window's other open tabs (not the active one), most recently used first, followed by the profile's most visited sites.

#### Scenario: Empty command bar
- **WHEN** the user presses Cmd+T in a window with three tabs
- **THEN** the results list the two tabs not shown with "Switch to Tab", the most recently used first, followed by most visited sites

### Requirement: Keyboard control
Up and Down SHALL move the selection, Return SHALL choose the selected row, and Esc SHALL close the command bar. Shift+Return or Cmd+Return SHALL open the selected row in a new tab even when the command bar was opened with Cmd+L. As in Arc, the pointer SHALL NOT move the selection: the row under it SHALL show a faint grey background rather than the accent colour, and clicking a row SHALL choose it.

#### Scenario: Choosing the second row
- **WHEN** the user types a query, presses Down and then Return
- **THEN** the second row's result opens

#### Scenario: Hovering a row
- **WHEN** the user types a query, rests the pointer on the third row and presses Down
- **THEN** the third row shows a grey background, the second row is selected in the accent colour, and Return opens the second row's result

### Requirement: Site search keywords
When the query starts with a search engine's keyword, the command bar SHALL show that engine's icon and offer "Search <engine>" with Tab. After Tab, the rest of the query SHALL search that engine. Delete in the empty field SHALL leave keyword mode and put the keyword back as text, as the omnibox does.

#### Scenario: Searching a site
- **WHEN** a search engine with keyword `wiki` is configured, and the user types `wiki`, presses Tab, types `Arc` and presses Return
- **THEN** that engine's results page for "Arc" opens

#### Scenario: Leaving keyword mode
- **WHEN** the user types `wiki`, presses Tab and then Delete
- **THEN** the engine's name leaves the field, the field reads `wiki`, and its placeholder is "Search or Enter URL…" again

### Requirement: Deleting a suggestion with the pointer
As in Arc, a suggestion that Chromium's autocomplete can delete, such as a page from history or an earlier search, SHALL show an × at its trailing end while the pointer is over its row, with the tooltip "Delete Suggestion ⌥⌘⌫". Clicking the × SHALL delete the suggestion without confirmation and without choosing the row. Other rows, and every row listed with an empty query, SHALL show no ×.

#### Scenario: Deleting a page from history
- **WHEN** the user has visited `https://example.com/?probe`, types `probe`, rests the pointer on that page's row and clicks its ×
- **THEN** the row leaves the list, the command bar stays open, and typing `probe` again no longer suggests that page

#### Scenario: A page upgraded to HTTPS in this session
- **WHEN** the user has just opened `example.com/?probe` by typing it, so history holds both its `http://` and `https://` addresses, and deletes its row with the ×
- **THEN** typing `probe` again doesn't suggest the page under either address

#### Scenario: Deleting a row that isn't selected
- **WHEN** the first row is selected and the user clicks the × on the third row
- **THEN** the third row leaves the list and the first row stays selected

#### Scenario: A row that can't be deleted
- **WHEN** the pointer rests on the row searching the default engine for what was typed
- **THEN** the row shows no ×

#### Scenario: Empty query
- **WHEN** the user presses Cmd+T and rests the pointer on a tab's row or a most visited site's row
- **THEN** the row shows no ×

### Requirement: Deleting a suggestion with the keyboard
Option+Command+Delete SHALL delete the selected suggestion when it can be deleted, as clicking its × does, and SHALL do nothing otherwise; it SHALL never edit the field's text. After any deletion the selected row SHALL stay selected; when it was the row deleted, the row that takes its place SHALL be selected, or the last row when it was last.

#### Scenario: Deleting the selected row
- **WHEN** the selected row is a page from history and the user presses Option+Command+Delete
- **THEN** that page leaves the list and the row that moved into its place is selected

#### Scenario: Selected row can't be deleted
- **WHEN** the selected row searches the default engine and the user presses Option+Command+Delete
- **THEN** the list and the field's text are unchanged
