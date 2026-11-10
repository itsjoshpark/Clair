# Tasks

Group 1 changes the engine key, so build the engine first and push docs afterwards, as `CLAUDE.md` describes. "CI" is the merge gate in `ci.yml`. "By hand" means the owner launches a test build of the branch. `quality.yml` runs on the branch before merging (`gh workflow run quality.yml --ref <branch>`).

Suggested order: 1, 2, 3, then 4. Groups 2 and 3 can start in `ClairUI` against `FakeBrowser` while the engine builds.

## 1. Contract and engine

- [x] 1.1 Add `canDelete` to `ClairSuggestion` and `deleteSuggestion:` to `ClairAutocomplete` in `native/ClairHost.h` (D2), and implement both in `FakeSuggestion` and `FakeAutocomplete`, the fake recording each deletion. Verify in CI that ClairUI builds and its unit tests pass.
- [x] 1.2 In `overlay/chrome/browser/clair/window/clair_autocomplete.mm`, keep each match in `Destination`, set `canDelete` from `SupportsDeletion()`, leave it `NO` for the empty-query rows, and implement `deleteSuggestion:` with `AutocompleteController::DeleteMatch`, also deleting a page's other `http:`/`https:` address from history (D1). Verify by the engine build in 1.3.
- [x] 1.3 Build the engine with `gh workflow run engine.yml -f ref=<branch>`. Verify that `chromium-engine-<key>` is published and CI's engine check passes.

## 2. Deleting in the model and with ⌥⌘⌫

- [x] 2.1 Add `delete(_:)` and `deleteSelected()` to `CommandBarModel`, keeping the deleted row's index selected on the next update and clearing it when the text changes (D3). Verify with unit tests in CI: a deletion reaches the session; nothing happens for a suggestion that can't be deleted; after the shorter list arrives the same index is selected, or the last row when the last was deleted; deleting another row keeps the selected row selected; typing afterwards selects the first row.
- [x] 2.2 Handle ⌥⌘⌫ with a hidden button's keyboard shortcut (D4). Verify by hand: ⌥⌘⌫ deletes a selected history row and selects the row that moved up, does nothing on a search row, and never changes the field's text; Delete alone still edits text, and behaves as on `main` in keyword mode (where Delete in an empty field doesn't leave it: a bug that predates this change).

## 3. The × on the row

- [x] 3.1 Add the × to `SuggestionRow` with D5's size, position, colours, hover background, tooltip and `.focusable(false)`, shown only while the row is hovered and `canDelete`, and add the "Delete Suggestion" accessibility action. Verify by hand against Arc side by side in Light and Dark Mode: a hovered history row, the selected row hovered, a search row with none, the empty-query rows with none, and the tooltip.
- [x] 3.2 Verify clicking the × by hand: the row leaves the list without being opened, the command bar stays open, and after closing and reopening it, the page isn't suggested again and is gone from `chrome://history`, including a page typed without a scheme and deleted in the same session (both its `http://` and `https://` entries).

## 4. Release notes and integration

- [x] 4.1 Add a Changie fragment (`changie new`, kind New) for deleting suggestions from the command bar. Verify that it's in the PR.
- [x] 4.2 Run `openspec validate --all --strict` and the merge gate, and verify that CI passes.
- [x] 4.3 Run `quality.yml` on the branch and verify that it passes before merging.

## Workflow follow-up

- Archive the change once it's merged, in its own PR, as earlier changes were.
- Fix separately: two keyword-mode bugs found while testing, both already on `main`. Delete in the empty field doesn't leave keyword mode (see 2.2), and with the engine pill showing, the field's hint should read "Search…" rather than "Search or Enter URL…", which also needs the `command-bar` spec's "Command bar appearance" requirement updated.
