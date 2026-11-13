# Design

## Context

See proposal.md, "Why", and `openspec/changes/archive/2026-11-12-add-spaces/arc-reference.md`, "Tabs across windows" and "Which tab becomes active after a close". "`add-spaces` D*n*" below is a decision in that change's `design.md`. What shapes the approach:

- **`add-spaces` leaves this in place:**
  - `ClairSpaceTabs`, one per profile, with an ordered tab list per Space across every browser of the profile. It owns the tab snapshots, and each `ClairTab` carries its `browserID`.
  - Each `BrowserWindowController` copying its own rows of its shown Space from `SpacesModel`, and mapping a dragged row around other windows' tabs.
  - The shown-Space invariant (`add-spaces` D3), and the came-from rule for closes with its wait for a page that asks before leaving (`add-spaces` D4).
  - `ClairBrowserWindow::ExecuteTabCommand`, which runs the tab commands over the window's rows (`add-spaces` D5).
  - An incognito or guest window's own Space (`private-<n>`), listed by `browserID`.
  - Session restore at every launch (`add-spaces` D11).
- **A tab can move between browsers of one profile.** `TabStripModel::DetachTabAtForInsertion` returns the `tabs::TabModel` and `InsertDetachedTabAt` takes it, so the tab and its handle survive. `chrome::MoveTabsToExistingWindow` does this too, but appends at the end and calls `Show()` on the target, so the overlay uses the two strip calls directly (verified in 156.0.8078.79).
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
2. Detach the tab from the holder's strip and insert it into this strip, active. Its Peek, if any, moves with it: the overlay detaches both, inserts the Peek directly after its parent, moves their link from the holder's table to this browser's, and activates the Peek, as selecting its parent's row does (`add-peek` D3).

`add-peek`'s bridge closes a Peek when its parent leaves the window. A take is the exception: the observer leaves a pair alone while the overlay moves it.

A take changes the tab's `browserID`, which `ClairSpaceTabs` pushes as a tab change.

In `ClairUI`, a `BrowserWindowController` copies its shown Space's whole list, not only the rows with its own `browserID`, and a dragged row's index is its index in the Space's list, with no mapping. An incognito or guest window keeps listing by `browserID`: its tabs never move.

### D2. A window that gives its tab away keeps a still over a hidden placeholder tab

When a browser's active tab is taken:

1. The overlay asks for the page's copy with `CopyFromSurface`, with a 250 ms timeout, before the tab leaves. For a tab with a Peek it copies the parent's page, never the Peek's, as Arc's still shows the page without its Peek. The parent stays visible under its Peek (`add-peek` D3), so the copy can be taken.
2. It inserts a **placeholder**: a new tab page tab, marked as a placeholder in its `WebContents` user data, and activates it. A placeholder is in no Space list and has no row. It is the one exception to two `add-spaces` rules: `ClairSpaceTabs` doesn't put it in the Space its browser shows (D2 there), and while it is active the browser keeps its shown Space (D3 there).
3. The browser records the taken tab's ID. `ClairUI` shows the still dimmed over the card, highlights the taken tab's row without its Peek badge, as Arc does, empties the URL field and disables back, forward and reload. If the copy fails, it dims the card's background alone.

The still ends when:

- **the window becomes key:** it takes the tab back (D1), and the placeholder closes;
- **the user selects another row or switches Space:** the placeholder closes once the other tab is active;
- **the taken tab closes:** the placeholder becomes an ordinary tab of the shown Space, at the top of its list, and the command bar opens.

A placeholder carries no session tags, so it needs no session work: restored, it is an ordinary new tab page, which joins the Space its window shows as any untagged tab does (`add-spaces` D2).

Found while implementing:

- **The copy isn't waited for.** `CopyFromSurface` copies whatever the page's surface shows when viz serves the request, which is the same frame whether the tab has moved yet or not, so the overlay moves the tab at once and records the image when it arrives; `stillDidChange` then fires a second time.
- **A click that makes the window key finishes first.** Taking back on becoming key waits for the mouse-up of the click that made the window key. A click on another row then selects that row, which ends the still, and the tab stays where it is, as "Moving on" in the spaces spec asks.
- **While a still shows, the still's row stands for the active row**: Cmd+W closes it in the window that holds it, and the tab commands count from it, as the sidebar highlights it.
- **Duplicate of a row another window holds** opens the copy in this window, right below the row, as `WebContents::Clone` and an insert, since Chromium's `DuplicateTabAt` works only within one strip.

- **Why a placeholder:** Chromium needs an active tab, and activating any real tab would run its page as visible behind the still.

### D3. Showing a Space, and choosing the next tab, look across windows

- **Showing a Space** (`add-spaces` D3) activates the tab last active in it in this browser, unless another browser is showing it; failing that, the Space's most recently active tab that no browser is showing; failing that, a new tab page. A tab another browser holds is taken (D1).
- **The came-from rule** (`add-spaces` D4) chooses among all the Space's rows, not only this browser's, and takes the chosen tab when another browser holds it. Its wait for a page that asks before leaving is unchanged.
- **The Space's last tab.** When the Space has no other row, a close Clair starts first takes the most recently active tab of another Space that no browser is showing, and the browser's shown Space follows it. With no such tab, the close goes ahead and the browser closes with its last tab. `moveTab:toSpace:` on the last row still opens a new tab page in the Space (`add-spaces` D7).
- **The tab commands** run through `ClairBrowserWindow::ExecuteTabCommand` over the Space's whole list, taking the chosen tab when another browser holds it. `closeTabsBelowTab:` and Close Other Tabs close rows in whichever browser holds them.
- **Closing a tab that isn't active here** closes it in whichever browser holds it. If it is that browser's active tab, that browser chooses its next tab as for a close of its own. A leave-page confirmation shows in the browser that holds the tab, as Chromium shows one for any tab.

### D4. Closing a window hands its tabs to another window

When the user closes a window and another regular window is open, its tabs (not a placeholder) move to the most recently active other window, each Peek with its parent as in D1, and the emptied browser closes. No tab closes, so no leave-page prompt shows. Closing the last regular window goes through Chromium's close flow, as today.

### D5. The contract (`native/ClairHost.h`)

- **`ClairBrowser` gains** `stillTabID` and `stillImage`.
- **`ClairWindow` gains** `stillDidChange`.
- **Comments change** on `-[ClairHost tabsInSpace:]` and `ClairBrowser.shownSpaceID`, which say a window lists the tabs with its own `browserID`: only an incognito or guest window does now.

`FakeHost` and `FakeBrowser` follow: a take, the still, and a closed window's tabs moving.

## Risks / Trade-offs

- **[A page copy can fail or come late]** → The still is optional: the card dims without it.
- **[Two windows on one tab move it on every focus change]** → Accepted; Arc does the same.
- **[Extensions see tabs move between windows]** → Accepted; these are ordinary Chromium events.
- **[Reopen Closed Window brings back an empty window]** when its tabs moved to another window. → Accepted.
- **[A page that closes its own tab can close the window]** when it is the only tab the browser holds, even while the Space lists tabs other windows hold: Chromium picks the next tab from the strip, and the strip can't be changed while it notifies (`add-spaces` D4). → Accepted, as `add-spaces` accepted it for a window's only tab.
