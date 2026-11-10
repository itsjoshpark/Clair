# Spec Delta

## ADDED Requirements

### Requirement: Deleting a suggestion with the pointer
As in Arc, a suggestion that Chromium's autocomplete can delete, such as a page from history or an earlier search, SHALL show an × at its trailing end while the pointer is over its row, with the tooltip "Delete Suggestion ⌥⌘⌫". Clicking the × SHALL delete the suggestion without confirmation and without choosing the row. Other rows, and every row listed with an empty query, SHALL show no ×.

#### Scenario: Deleting a page from history
- **WHEN** the user has visited `https://example.com/?probe`, types `probe`, rests the pointer on that page's row and clicks its ×
- **THEN** the row leaves the list, the command bar stays open, and typing `probe` again no longer suggests that page

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
