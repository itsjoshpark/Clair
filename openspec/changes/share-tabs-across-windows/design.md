# Design

**Draft.** These decisions were made while planning the three changes together. Revise them against `add-spaces` as built, then write `tasks.md`.

## Context

See proposal.md, "Why", and the `add-spaces` change's `arc-reference.md`, "Tabs across windows" and "Which tab becomes active after a close". What shapes the approach:

- **`add-spaces` leaves this in place:** `ClairSpaceTabs`, one per profile, with an ordered tab list per Space across every browser of the profile; each `ClairTab` carrying its `browserID`; `ClairUI` filtering a Space's rows to its own window; the shown-Space invariant; and the came-from rule for closes.
- **A tab can move between browsers of one profile.** `TabStripModel::DetachTabAtForInsertion` returns the `tabs::TabModel` and `InsertDetachedTabAt` takes it, so the tab and its handle survive. `chrome::MoveTabsToExistingWindow` does this too, but appends at the end and calls `Show()` on the target, so the overlay uses the two strip calls directly (verified in 156.0.8078.73).
- **A browser closes when its strip empties,** and needs an active tab while it lives.
- **A tab strip can't be changed while it notifies its observers.**
- **`RenderWidgetHostView::CopyFromSurface` copies a page once,** asynchronously, and may fail for an occluded page.

## Goals / Non-Goals

**Goals:**
- Keep every tab in a real browser, so every Chromium feature keeps working per tab.
- Add behaviour on top of `add-spaces`' structures without reshaping them.

**Non-Goals:**
- A tab that lives in no window.
- Showing one live page in two windows.

## Decisions

### D1. Selecting a tab held elsewhere moves it here

`-[ClairBrowser activateTab:]` on a tab another browser holds runs **take**:

1. If the holder is showing the tab, start its still and placeholder (D2).
2. Close the tab's Peek, if any, then detach the tab from the holder's strip and insert it into this strip, active.

`ClairUI` stops filtering rows by `browserID`.

### D2. A window that gives its tab away keeps a still over a hidden placeholder tab

When a browser's active tab is taken:

1. The overlay asks for the page's copy with `CopyFromSurface`, with a 250 ms timeout, before the tab leaves.
2. It inserts a **placeholder**: a new tab page tab, marked as a placeholder in its `WebContents` user data, and activates it. A placeholder is in no Space list and has no row.
3. The browser records the taken tab's ID. `ClairUI` shows the still dimmed over the card, highlights the taken tab's row, empties the URL field and disables back, forward and reload. If the copy fails, it dims the card's background alone.

The still ends when:

- **the window becomes key:** it takes the tab back (D1), and the placeholder closes;
- **the user selects another row or switches Space:** the placeholder closes once the other tab is active;
- **the taken tab closes:** the placeholder becomes an ordinary tab of the shown Space, at the top of its list, and the command bar opens.

A placeholder needs no session work: restored, it is an ordinary new tab page in the Space its window shows.

- **Why a placeholder:** Chromium needs an active tab, and activating any real tab would run its page as visible behind the still.

### D3. Showing a Space, and choosing the next tab, look across windows

- Showing a Space activates the tab last active in it in this browser; failing that, the Space's most recently active tab that no browser is showing, taken from its holder; failing that, a new tab page.
- The came-from rule and the tab commands run over the Space's whole list, taking the chosen tab when another browser holds it.
- Closing a tab that isn't active here closes it in whichever browser holds it.

### D4. Closing a window hands its tabs to another window

When the user closes a window and another regular window is open, its tabs (not a placeholder) move to the most recently active other window, and the emptied browser closes. No tab closes, so no leave-page prompt shows. Closing the last regular window goes through Chromium's close flow, as today.

### D5. The contract (`native/ClairHost.h`)

- **`ClairBrowser` gains** `stillTabID` and `stillImage`.
- **`ClairWindow` gains** `stillDidChange`.

## Risks / Trade-offs

- **[A page copy can fail or come late]** → The still is optional: the card dims without it.
- **[Two windows on one tab move it on every focus change]** → Accepted; Arc does the same.
- **[Extensions see tabs move between windows]** → Accepted; these are ordinary Chromium events.
- **[Reopen Closed Window brings back an empty window]** when its tabs moved to another window. → Accepted.
- **[`add-spaces`' requirements written for a window's own rows]** ("Showing a Space that has no tab here", "Tab chosen after a close", "Tab commands follow the Space") overlap this change's added ones. → Fold them into MODIFIED requirements when the design is finished, once `spaces` is a main spec.
