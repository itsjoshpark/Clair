# Design

## Context

See proposal.md, "Why". What's there today:

- **The engine snapshots matches.** `clair_autocomplete.mm` turns each `AutocompleteMatch` into a `ClairSuggestion` and keeps only a `Destination` (URL, transition, tab) per suggestion ID, so it can't hand a match back to Chromium.
- **Chromium already deletes matches.** `AutocompleteController::DeleteMatch(match)` asks the match's provider, and each of its duplicates' providers, to delete it, then calls `UpdateResult(kMatchDeletion)`, which notifies observers straight away. `AutocompleteMatch::SupportsDeletion()` says whether it can. History matches are deletable when the page has visits and the `AllowDeletingBrowserHistory` pref is on (the default). Search matches are deletable when they come from the user's earlier searches, or when the engine gave a deletion URL.
- **The empty-query list is built by the engine** from the tab strip and `TopSites`, not from `AutocompleteController`, so its rows have no match to delete.
- **`CommandBarModel` resets the selection to the first row** on every update from the session.
- **The row hides its children from accessibility** (`.accessibilityElement(children: .ignore)`) and reads as one element.

**Arc, as measured** with XCUITest, in Light and Dark Mode (Arc 1.170):

| | Measured |
|---|---|
| Which rows | Hovered history pages, including the selected row. Not search suggestions from the engine, open tabs or Arc's own rows |
| Button | Drawn about 24.5 × 23 pt, its trailing edge 15 pt inside the row's (its accessibility frame is 26 × 22.5 pt); accessibility label "Close" |
| Glyph | A thin ×, about 9.5 pt square |
| Glyph colour | Grey on a hovered row: (137) on (242) in Light, (193) on (46) in Dark. White on the selected row in both |
| Button hover | A rounded background about 6% black in Light ((160) → (151) on the selected row) and 7% white in Dark ((81) → (97)) |
| Tooltip | "Delete Suggestion" with the keys ⌥ ⌘ ⌫ |
| Clicking | Deletes at once from history, with no confirmation; the command bar stays open |
| ⌥⌘⌫ | Deletes the selected history row. Shift+Delete and Shift+Fn+Delete do nothing special |

## Goals / Non-Goals

**Goals:**
- Use Chromium's own deletion, so whatever the omnibox would delete is deleted, plus a page's other `http:`/`https:` address (D1).
- Keep the contract change additive.

**Non-Goals:**
- Deleting the empty-query rows (proposal, "Out of scope").
- A runtime test. The model's logic gets unit tests; the × and ⌥⌘⌫ against real history are checked by hand.

## Decisions

### D1. The engine keeps a copy of each match

`Destination` gains `std::optional<AutocompleteMatch> match`, set in `resultChanged` and left empty for the empty-query rows. A suggestion's `canDelete` is `match && match->SupportsDeletion()`.

`deleteSuggestion:` finds the destination by ID and, if the session isn't stopped and its match supports deletion, calls `_controller->DeleteMatch(*match)`. Chromium then notifies the observer, `resultChanged` publishes the list without the row, and the IDs are reissued as on any update. An unknown ID or a match that can't be deleted does nothing.

A copy is safe to pass: providers delete by the match's URL or contents, not by its address, and the copy's `provider` pointer stays valid while the controller lives, which it does for the whole session.

For a deletable page (not a search), the engine also deletes the same URL with the other of `http:` and `https:` through the profile's `HistoryService`. A page typed without a scheme is saved twice, as `http:` and as the `https:` page it was upgraded to, and the history index only learns the `http:` entry later. Until then the match doesn't carry it as a duplicate, so `DeleteMatch` alone left it, and the page came back on the next query (found by hand: after a restart both went together). The history service tells the index, so the other entry leaves the suggestions too.

*Alternatives:* looking the match up in `_controller->result()` by URL when deleting. The result may have changed since the row was shown, so it could find nothing or the wrong match. Keeping the suggestion's own match is what the row showed.

### D2. Contract additions

```objc
// ClairSuggestion
// Whether -deleteSuggestion: can delete it, such as a page from history or
// an earlier search. Always NO in the empty-query list.
@property(nonatomic, readonly) BOOL canDelete;

// ClairAutocomplete
// Deletes a suggestion from the latest results wherever Chromium keeps it,
// as the omnibox does, then sends the updated list. Ignored for a suggestion
// that can't be deleted.
- (void)deleteSuggestion:(NSInteger)suggestionID NS_SWIFT_NAME(delete(suggestion:));
```

Both are additions, so nothing existing changes. `FakeSuggestion` and `FakeAutocomplete` implement them, the fake recording each deletion.

### D3. The model deletes and keeps the selection in place

`CommandBarModel.delete(_ suggestion:)` asks the session to delete it, and `deleteSelected()` does the same for the selected row when it `canDelete`, returning whether it did. Before calling the session, the model works out which index to select next: the selected row's, one less when the deleted row was above it. The same index then holds the row that took the selected row's place when that was the one deleted. On the next update it selects that index, clamped to the list, instead of the first row, then forgets it. Typing or changing keyword mode clears it, so a new query still selects the first row.

The index is remembered before the call because Chromium's update arrives inside it, synchronously.

### D4. ⌥⌘⌫ as a hidden button's shortcut

An invisible `Button` behind the field carries `.keyboardShortcut(.delete, modifiers: [.option, .command])` and calls `deleteSelected()`. Key equivalents are handled before the field editor sees the key, so the shortcut never deletes text, and it exists only while the command bar does. No menu item uses ⌥⌘⌫; "Delete Browsing Data…" is ⇧⌘⌫.

*Alternatives:* the field's `.onKeyPress(.delete)`, which the first build tried: it never receives keys with Command held, so ⌥⌘⌫ did nothing. A menu item with the key equivalent, as Chromium's menus do, would show in the Edit menu for a feature that only works in the command bar, and need enabling and disabling with it.

### D5. The × on the row

`SuggestionRow` shows a `Button` with `xmark` at the trailing end while `isHovered && suggestion.canDelete`, after "Switch to Tab" when both show:

- 24 pt square, its trailing edge 15 pt inside the row's, 4 pt more than the row's padding;
- the glyph at about 10 pt, regular weight, in the row's secondary colour, or white on the selected row;
- under the pointer, a rounded background of `Color.primary` at 6% in Light Mode and 7% in Dark;
- `.tooltip("Delete Suggestion", shortcut: ["⌥", "⌘", "⌫"])`, with the existing tooltip view;
- `.focusable(false)`, so only the field takes focus, as the find field's buttons do.

The button is a sibling of the row's tap gesture, and SwiftUI gives the click to the button, so a click on the × doesn't also choose the row. Since the row reads as one accessibility element, the row gains `.accessibilityAction(named: "Delete Suggestion")` when it can be deleted, which VoiceOver offers in its actions.

### D6. Tests

Unit tests with `FakeAutocomplete`: deleting a deletable suggestion reaches the session; `deleteSelected()` does nothing for one that can't be deleted; after the fake posts the shorter list, the same index is selected, or the last row; typing afterwards selects the first row again. Everything else is checked by hand against Arc.

## Risks / Trade-offs

- [Deleting a history suggestion deletes that page from the profile's history, which can't be undone] → It's what Arc and Chrome do, and what the × and its tooltip say. The page's other data, such as cookies, is untouched.
- [Deleting a search suggestion keeps no blocklist] → `BaseSearchProvider::DeleteMatch` deletes that engine's searches for those words from history, which is what makes an earlier search come back, so it stays gone. For a personalized suggestion the engine sent with a deletion URL, Chromium also sends that request to the engine, and whether it comes back is up to the engine. The engine's other suggestions aren't deletable and get no ×.
- [In an incognito window, history suggestions come from the regular profile's history, so deleting one deletes it there] → Chromium's omnibox does the same, and the spec doesn't promise otherwise.
- [After a deletion the next row moves under a still pointer, and SwiftUI may not report the hover until the pointer moves] → The grey and the × may appear a moment late. Checked by hand; acceptable if they appear on the next move.

## Migration Plan

None: the contract only grows, and there's no stored data. The engine builds once for the new key.
