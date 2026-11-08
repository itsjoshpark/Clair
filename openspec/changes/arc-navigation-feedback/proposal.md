# Proposal

## Why

The owner's pass over the native window (`replace-browser-window`) left three gaps in how Clair reports and moves through a tab's navigation, all of which Arc handles and all of which need more from Chromium than the window contract gives today. The reload button flips to stop and back after a page has loaded, while the tab shows no spinner. Right-clicking back or forward does nothing, where Arc lists the tab's history. And a loading page shows nothing, where Arc animates a small capsule above the page. People moving from Arc expect all three, and Arc stops working on 2026-12-22.

## What Changes

- **Reload and stop follow the page's loading state, as Chromium's toolbar does.** Stop shows only while the page itself loads (a navigation to a new document), not while a frame inside it or a same-document navigation loads. When a load ends with the pointer on the button, the button holds briefly before turning back into reload, as Chromium's does, so a second click doesn't reload by accident. The tab list's spinner uses the same state.
- **Back and forward show the tab's history.** Right-clicking or Control-clicking either button opens a native menu of the pages in that direction, nearest first, each with its favicon and title. Choosing one goes there; Cmd-choosing opens it in a new background tab. The entries and their order come from Chromium's own back/forward menu (up to 12 pages).
- **A loading indicator in the card's top inset.** While the active tab loads, a small capsule centred above the page card pulses, then sweeps, and flashes and shrinks away when the load ends, as Arc's does. Like Arc's, it runs on time, not on the load's progress. Its look and timing follow a recording of Arc's.
- **New Incognito Window in the Dock menu with no windows open.** Chromium only offers it while a profile is loaded, and it unloads the profile when the last window closes, so the Dock menu then offers only New Window. A small patch keeps the item, which loads the profile when chosen, as New Window does.
- **One contract addition, one engine build.** `ClairHost.h` gains load progress on the tab snapshot (reported, though the indicator doesn't use it) and a history-menu session; the overlay fixes which loading state it reports; the Dock menu patch rides along. All of it ships from one engine.

**Out of scope:** tooltips, which `replace-browser-window` already draws in Arc's style; a history page or history search; showing progress for background tabs; changing which entries Chromium keeps in a tab's history.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `sidebar`: adds the back/forward history menu and states which loading state drives reload/stop and the tab spinner.
- `browser-window`: adds the loading indicator in the card's top inset.

Both capabilities are introduced by `replace-browser-window`, which isn't archived yet, so this change adds requirements to them and is archived after it.

## Impact

- **Engine:** the overlay, plus one small patch to Chromium's Dock menu (`patches/clair/dock-incognito.patch`). `clair_browser_bridge.mm` reports `ShouldShowLoadingUI()` instead of `IsLoading()`, adds load progress to the tab snapshot and pushes it on `LoadProgressChanged`, and hosts Chromium's `BackForwardMenuModel` for the history menu. `native/ClairHost.h` grows by one tab property and one small session protocol. The engine key changes, so `engine.yml` builds one new engine.
- **Native layer:** the reload/stop hold (Chromium's, which Arc lacks), the history menu on the back and forward buttons (both the full and the compact row), and the loading indicator view, in `native/ClairUI/`, with unit tests for their logic against `FakeBrowser`.
- **Tests:** one runtime test for the reload/stop fix and one for choosing a history entry, both fundamentals of navigation; the loading indicator and the rest are checked by hand against Arc.
- **Users:** a Changie fragment for the history menu and the loading indicator; the reload/stop fix rides along in the same fragment.
