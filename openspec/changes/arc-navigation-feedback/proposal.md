# Proposal

## Why

The owner's pass over the native window (`replace-browser-window`) left three gaps in how Clair reports and moves through a tab's navigation, all of which Arc handles and all of which need more from Chromium than the window contract gives today. The reload button flips to stop and back after a page has loaded, while the tab shows no spinner. Right-clicking back or forward does nothing, where Arc lists the tab's history. And a loading page shows no progress, where Arc draws a glow along the top of the page. People moving from Arc expect all three, and Arc stops working on 2026-12-22.

## What Changes

- **Reload and stop follow the page's loading state, as Chromium's toolbar does.** Stop shows only while the page itself loads (a navigation to a new document), not while a frame inside it or a same-document navigation loads. When a load ends with the pointer on the button, the button holds briefly before turning back into reload, as Chromium's does, so a second click doesn't reload by accident. The tab list's spinner uses the same state.
- **Back and forward show the tab's history.** Right-clicking either button, or pressing and holding it, opens a menu of the pages in that direction, newest first, each with its favicon and title. Choosing one goes there; Cmd-choosing opens it in a new background tab. The menu's contents and order come from Chromium's own back/forward menu, trimmed to what Arc shows.
- **A loading indicator in the card's top inset.** While the active tab loads, a thin glow runs along the top edge of the page card, following Chromium's load progress, and fades out when the load ends. Its look and timing follow a recording of Arc's.
- **One contract addition, one engine build.** `ClairHost.h` gains load progress on the tab snapshot and a history-menu session; the overlay fixes which loading state it reports. All three ship from one engine.

**Out of scope:** tooltips, which `replace-browser-window` already draws in Arc's style; a history page or history search; showing progress for background tabs; changing which entries Chromium keeps in a tab's history.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `sidebar`: adds the back/forward history menu and states which loading state drives reload/stop and the tab spinner.
- `browser-window`: adds the loading indicator in the card's top inset.

Both capabilities are introduced by `replace-browser-window`, which isn't archived yet, so this change adds requirements to them and is archived after it.

## Impact

- **Engine:** the overlay only, no patch to a Chromium file. `clair_browser_bridge.mm` reports `ShouldShowLoadingUI()` instead of `IsLoading()`, adds load progress to the tab snapshot and pushes it on `LoadProgressChanged`, and hosts Chromium's `BackForwardMenuModel` for the history menu. `native/ClairHost.h` grows by one tab property and one small session protocol. The engine key changes, so `engine.yml` builds one new engine.
- **Native layer:** the reload/stop hold, the history menu on the back and forward buttons (both the full and the compact row), and the loading indicator view, in `native/ClairUI/`, with unit tests for their logic against `FakeBrowser`.
- **Tests:** one runtime test for the reload/stop fix and one for choosing a history entry, both fundamentals of navigation; the loading indicator and the rest are checked by hand against Arc.
- **Users:** a Changie fragment for the history menu and the loading indicator; the reload/stop fix rides along in the same fragment.
