# Proposal

## Why

In Arc, a Space's tabs are the same in every window: the sidebar is one list, and a window is a view onto it. After `add-spaces`, each Clair window still lists only the tabs it opened, so a second window on the same Space looks empty, and closing a window closes its tabs. Arc users expect neither. Arc stops working on 2026-12-22.

This is the second of three changes; `add-spaces` comes before it and `add-profiles` after.

## What Changes

- **One tab list for every window.** Every window lists the tabs of the Space it shows, whichever window they were opened in, and a change in one window shows in the others at once.
- **A tab shows in one window at a time.** Selecting a tab that another window shows brings its live page here, without reloading it. The other window keeps a dimmed still of the page, as Arc does, until it is focused again, when it takes the page back.
- **Closing a window keeps its tabs** while another window is open. Closing the last window closes them, as today.
- **The next tab after a close** is chosen from the whole list, and a tab showing in another window isn't skipped.
- **BREAKING (`ClairHost.h`):** `ClairBrowser` gains the still of a tab it gave away, and `ClairWindow` learns when it changes.

**Out of scope:**
- A still that updates live.
- Incognito and guest windows, whose tabs stay per window.
- Reopen Closed Window bringing back tabs that moved to another window when their window closed.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `spaces`: adds the shared tab list, a tab showing in one window at a time with a still in the other, tabs outliving their window, and choosing the next tab and running tab commands over the shared list. These are added requirements; the ones `add-spaces` wrote for a window's own rows are revised when this change's design is finished.
- `sidebar`: "Tab list" lists the Space's tabs from every window.

## Impact

- **Depends on `add-spaces`,** whose per-profile tab lists and contract this change extends. Its design and tasks are finished once `add-spaces` has landed and shown how those behave; `design.md` holds the decisions made so far.
- **`native/ClairHost.h`** changes, so the engine key changes and the engine is rebuilt once.
- **Overlay:** `clair_space_tabs`, the browser window and the bridge. No new patch is expected.
- **`ClairUI`:** the window model stops filtering rows to its own window; the card draws the still.
- **Chromium behaviour:** extensions see tabs move between windows as the user moves between windows.
