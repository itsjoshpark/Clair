# Proposal

## Why

In Arc, a mistyped or unwanted page can be removed from the command bar's suggestions, and from history, without opening the History page. Clair's command bar can't: Chromium's autocomplete knows which suggestions can be deleted and how, but the engine doesn't tell `ClairUI`, and there's no control for it. Arc stops working on 2026-12-22, and the command bar is used all the time.

## What Changes

- **An × on rows that can be deleted, as in Arc.** Hovering a suggestion Chromium can delete, such as a page from history or an earlier search, shows an × at the row's trailing end, with the tooltip "Delete Suggestion ⌥⌘⌫". Clicking it deletes the suggestion straight away, with no confirmation. The row leaves the list, and the command bar stays open.
- **⌥⌘⌫ deletes the selected suggestion,** as in Arc, when it can be deleted. It needs no Fn key, so it also works on keyboards that have none. Chromium's own Shift+Fn+Delete is not added.
- **Deleting goes through Chromium.** The engine calls the omnibox's own deletion, so the suggestion is removed wherever Chromium keeps it, such as the profile's history, and isn't suggested again.
- **Contract additions** in `ClairHost.h`: a suggestion says whether it can be deleted, and the autocomplete session gains a call to delete one. Nothing existing changes.

**Out of scope:**
- The rows listed with an empty query (open tabs and most visited sites), which Arc's command bar doesn't offer to delete either. The rows are built by the engine rather than Chromium's autocomplete, and have no ×.
- A confirmation or undo, which Arc doesn't have.
- Deleting from the History page, which stays Chromium's.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `command-bar`: a new requirement, "Deleting a suggestion", for the ×, its tooltip and ⌥⌘⌫.

## Impact

- **Contract and engine:** `native/ClairHost.h` gains `canDelete` on `ClairSuggestion` and `deleteSuggestion:` on `ClairAutocomplete`. `overlay/chrome/browser/clair/window/clair_autocomplete.mm` keeps each match so it can pass it to `AutocompleteController::DeleteMatch`. The engine key changes, so `engine.yml` builds one new engine.
- **Native layer:** `native/ClairUI/OverlayViews.swift` (the ×), `native/ClairUI/CommandBarModel.swift` (deleting, ⌥⌘⌫, the selection after a deletion), `FakeBrowser` and unit tests in `native/ClairUITests/`.
- **Tests:** unit tests for the model. The × and ⌥⌘⌫ against real history are checked by hand.
- **Users:** a Changie fragment. Deleting a history suggestion deletes that page from the profile's history, as in Chrome and Arc.
