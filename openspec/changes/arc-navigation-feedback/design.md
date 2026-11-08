# Design

## Context

See proposal.md for why, and `specs/sidebar/spec.md` and `specs/browser-window/spec.md` for the required behavior. This change builds on `replace-browser-window` (design D3 for the contract's rules, D4 for the layout, D12 for the sidebar) and lands after that change's polish task group, which keeps the card's 10 pt top inset with the sidebar hidden.

**What Clair does today** (`main` at `924b604`):

- The tab snapshot's `isLoading` is `WebContents::IsLoading()` (`clair_browser_bridge.mm`). `ClairBrowserWindow::UpdateReloadStopState(is_loading, force)` ignores its argument and pushes a fresh snapshot of the active tab. The sidebar's reload button and the tab row's spinner (shown only while a tab has no favicon) read `isLoading`.
- Back and forward are `SidebarButton`s (SwiftUI) that run `IDC_BACK` and `IDC_FORWARD`; they have no menu.
- Nothing reports load progress.

**What Chromium does**, read in the runner's patched 156 tree:

- `WebContentsImpl::IsLoading()` is true whenever any frame in the primary frame tree loads: `FrameTree::GetLoadingState()` returns `LOADING_UI_REQUESTED` for a cross-document navigation in the main frame and `LOADING_WITHOUT_UI` for a subframe loading on its own or a same-document navigation (`FrameTreeNode::GetLoadingState`). `IsLoading()` is `!= NONE`; `ShouldShowLoadingUI()` is `== LOADING_UI_REQUESTED`.
- `FrameTree::NodeLoadingStateChanged` notifies on every change between the three states, so `WebContentsDelegate::LoadingStateChanged(source, should_show_loading_ui)` also fires when the main frame finishes while a subframe still loads.
- The toolbar uses the second state only: `BrowserUiController::UpdateWindowForLoadingStateChanged` passes `source->IsLoading() && should_show_loading_ui` to `BrowserCommandController::LoadingStateChanged`, which calls `BrowserWindow::UpdateReloadStopState` and enables `IDC_STOP`. The tab strip's spinner does the same: `tabs::TabNetworkStateForWebContents` returns `kNone` unless `ShouldShowLoadingUI()`.
- Views' `ReloadButton::ChangeMode` doesn't switch from stop to reload while the pointer is on it: it disables the button and switches when the pointer leaves or after `mode_switch_timer_delay_` (1350 ms). It also ignores a switch to stop during the double-click interval after a reload click.
- `WebContentsObserver::LoadProgressChanged(double)` reports `WebContents::GetLoadProgress()` (0.1 when a load starts, 1.0 at the end), throttled by content.
- `BackForwardMenuModel` (`chrome/browser/ui/toolbar/`, platform-neutral) builds the toolbar's back/forward menu for a `BrowserWindowInterface`: up to `kMaxHistoryItems` (12) entries nearest first, then up to 5 "chapter stops" (other domains) when the list is full, a "Show Full History" item, and sometimes a back-to-opener entry. Labels are the entry's title or URL, favicons come from the entry or are fetched through `FaviconService` and reported through `ui::MenuModelDelegate::OnIconChanged`, and `ActivatedAt(index, event_flags)` navigates with `GoToIndex`, or opens a new tab for a Cmd- or middle-click (`ui::DispositionFromEventFlags`).

**So the flicker's root cause** is the bridge reporting `IsLoading()`: every snapshot pushed while an iframe, ad frame or `pushState` load is in flight says "loading", and snapshots are pushed for many unrelated reasons (title, favicon, audio, infobars, `UpdateLoadingAnimations`). The button flips to stop and back each time, while the tab spinner, shown only without a favicon, stays hidden.

**What Arc does**, first from a static read of its binaries (strings and class names only); task 1.1's measurements are in the Measurements section below, and they replace these guesses where they differ (Arc's history list is a popover, and its loading indicator a timed capsule, not a progress glow):

- `ArcCore` exposes `ArcBackForwardList` and `ArcBackForwardListItem` (with an `isAlternate` flag, maybe an Option-key variant), and `ARCUI`'s `BackForwardList.BackForwardListMenuManager` builds a menu anchored to the button (`MenuAnchorProviding`). Arc's buttons include a `LongPressButton` with `longPressDuration`. There's no "Show Full History" string.
- The loading indicator is `GlowProgressLoadingIndicatorView`, drawn with a Metal shader (`ARC_GlowProgressLoadingIndicator.bundle/default.metallib`) beside a `GradientBorderGlowView`, and `ArcCore` reports `loadProgress`.
- Tooltips are Arc's own: an `ArcTooltip` module with its own `TooltipWindow`, a delay and presentation of its own, and keyboard-shortcut hints (`tooltipKeyboardShortcut`, `optionKeyTitle`).

**Constraints:** every engine change goes into one contract addition and one engine build (D3 of `replace-browser-window`); the only patch to a Chromium file is D5's small Dock menu one. Tests stay on fundamentals: unit tests for logic, a runtime test only for core navigation, hand checks for the rest.

## Goals / Non-Goals

**Goals:**
- Reload, stop and the tab spinner driven by the same state as Chromium's toolbar and tab strip.
- Arc's back/forward history menu, with Chromium's entries, favicons and navigation.
- Arc's loading indicator, on Chromium's loading-UI state.
- One engine build for all of it.

**Non-Goals:**
- **Tooltips.** `replace-browser-window`'s polish group (D18) already draws Arc-style tooltips with shortcut key caps, since AppKit's never show in Chromium's window. This change only gives the history menu's buttons their labels through that same tooltip.
- A native history page or history search, or a way to reach `chrome://history` from the history menu (owner's decision, D3).
- Progress for background tabs, or in the tab rows.
- Pruning skippable entries or otherwise changing what Chromium keeps in a tab's history.

## Decisions

### D1. Report Chromium's loading-UI state, not `IsLoading()`

- The snapshot's `isLoading` becomes `contents->IsLoading() && contents->ShouldShowLoadingUI()`, the expression Chromium's toolbar and `TabNetworkStateForWebContents` use. The header's comment for `isLoading` says so. No new property: every reader (reload/stop, the compact row's menu, the tab spinner, the loading indicator) wants this state.
- `UpdateReloadStopState` keeps pushing a snapshot of the active tab. Since `LoadingStateChanged` fires on the `LOADING_UI_REQUESTED` → `LOADING_WITHOUT_UI` transition, the push that ends the visible load arrives as soon as the main frame finishes, even while subframes go on loading.
- Alternative: keep `IsLoading()` and debounce in `ClairUI`. Rejected: it only hides the symptom, still shows stop for a page whose ads load for a minute, and diverges from the tab spinner.
- Alternative: pass `UpdateReloadStopState`'s `is_loading` to `ClairUI` as window state. Rejected: the snapshot is per tab, so a tab switch would need the window state recomputed anyway; one per-tab value is simpler.

### D2. The stop button's hold, in `ClairUI`

- A small AppKit-free state machine, `ReloadStopMode`, takes the tab's `isLoading`, whether the pointer is on the button, and a clock, and answers what the button shows and whether it's enabled, following Views' `ReloadButton`: a change from stop to reload while hovered disables the button and completes when the pointer leaves or 1.35 s pass; a change from reload to stop within the double-click interval after a reload click, while hovered, is deferred the same way. A forced change (tab switch) applies at once.
- The full row's reload button and the compact row's menu item (which only reads the state) use it. It has no automated tests, unit or runtime (owner's decision, 2026-11-07, to keep the quality checks short); task 5.1 checks it by hand.
- Arc has no hold: its ✕ turns back into reload under the pointer as soon as the load ends (task 1.1). The owner kept Chromium's hold (2026-11-07), since it stops a late click on stop from reloading the page.

### D3. The history menu: Chromium's model behind a session

- **Contract.** A session, like autocomplete's (D11 of `replace-browser-window`):

  ```objc
  typedef NS_ENUM(NSInteger, ClairHistoryDirection) { Back, Forward };
  @protocol ClairHistoryItem <NSObject>
  @property(readonly) NSInteger itemID;          // stable while the session lives
  @property(readonly, copy) NSString *title;     // the title, or the URL
  @property(readonly, copy, nullable) NSURL *url;
  @property(readonly, nullable) NSImage *icon;
  @end
  @protocol ClairHistoryMenuDelegate <NSObject>
  - (void)historyMenu:(id<ClairHistoryMenu>)menu itemsDidChange:(NSArray<id<ClairHistoryItem>> *)items;
  @end
  @protocol ClairHistoryMenu <NSObject>
  @property(readonly, copy) NSArray<id<ClairHistoryItem>> *items;
  - (void)openItem:(NSInteger)itemID disposition:(ClairOpenDisposition)disposition;
  - (void)close;
  @end
  // ClairBrowser:
  - (nullable id<ClairHistoryMenu>)startHistoryMenuWithDirection:(ClairHistoryDirection)direction
                                                        delegate:(id<ClairHistoryMenuDelegate>)delegate;
  ```

  `startHistoryMenu` returns nil when the active tab can't go that way. Asking at the moment the menu opens is a query in response to the user, as autocomplete is, not polling; later favicons are pushed to the delegate.
- **Overlay.** `ClairHistoryMenuSession`, in `clair_browser_bridge.mm` (a new overlay file would need a line in the hook patch's `chrome/browser/ui/BUILD.gn` hunk, and `BackForwardMenuModel` is already in that target), owns a `BackForwardMenuModel` for the window's browser and direction and is its `ui::MenuModelDelegate`. `items` lists the model's history entries in order, then "Show Full History" (`ClairHistoryItemKindShowFullHistory`), skipping chapter stops and the back-to-opener entry, which Arc doesn't show. The engine was built with "Show Full History" in the contract before the owner dropped it; `ClairUI` leaves it out, and the contract keeps it rather than costing an engine build. `itemID` is the model index. `OnIconChanged` re-reads the items and calls the delegate. `openItem` calls `ActivatedAt(index, flags)` with the flags for the disposition (none, or Cmd for a new background tab), so Chromium's own navigation and new-tab code runs; a new tab then lands at the top of the list through the existing tab-strip hook. Activating or `close` ends the session, as does the tab changing.
- **`ClairUI`.** An AppKit `NSMenu`, popped up under the button with `popUp(positioning:at:in:)`, since SwiftUI's `contextMenu` can't open on a long press or update an open item's image. Arc draws a custom popover instead (task 1.1); the owner chose the native menu, with each page's favicon and title. It lists the history entries only, up to Chromium's 12 (Arc shows 10). An `NSView` over each back and forward `SidebarButton` (full and compact rows) catches right clicks and Control-clicks only, and lets every other click through to the button. There's no press-and-hold (owner's decision, 2026-11-07): Arc showed none that could be measured. While the menu is open, the delegate's updates set the matching items' images in place. Cmd-choosing maps to `NewBackgroundTab`. A `HistoryMenuBuilder` turns items into menu entries and choices into calls; it's unit-tested against `FakeBrowser`.
- Alternative: build entries from `NavigationController` directly. Rejected: it reimplements Chromium's labels, favicon fetching, cap and new-tab handling, which `BackForwardMenuModel` already tests.

- **Owner's decisions (2026-11-07):** a native `NSMenu` with favicons, not Arc's popover, listing the tab's pages only, opened by right-click with no press-and-hold; Chromium's cap of 12 entries, not Arc's 10. Cmd-choosing an entry opens it in a new background tab at the top of the tab list, as Clair places new tabs, where Arc puts it below the current tab.

### D4. The loading indicator: Arc's timed capsule

- **Contract.** `ClairTab` gains `@property(readonly) double loadProgress`, `GetLoadProgress()` in [0, 1], meaningful while `isLoading`. Task 1.1 found that Arc's indicator ignores progress, and the owner chose to copy it exactly (2026-11-07), so nothing in `ClairUI` reads it. It stays in the contract, which the engine was built with, for a later use.
- **Overlay.** The bridge already watches each tab for infobars; it also observes each tab's `WebContents` for `LoadProgressChanged` and marks that tab changed, so progress rides the existing per-tab coalesced push (at most once per run-loop turn, on top of content's own throttling).
- **`ClairUI`.** `LoadingIndicatorView`, an AppKit layer-backed view in `BrowserRootView`, in the 10 pt inset above the card, centred on the card (which follows the sidebar as it hides or reveals), above the card in z-order but below overlays (command bar, find, revealed sidebar). It takes no mouse events (`hitTest` returns nil), so the page-top drag strip keeps working. It hides in page full screen.
- **`LoadingIndicatorModel`**, free of AppKit and unit-tested, turns the active tab's `isLoading` and the time since that load started into what to draw, following the Measurements section:
  - **Pulse** from the start of a visible load: a 44 pt capsule fades in linearly to white at about 76 % while growing to 48 pt, and back, over 1.4 s, then stays hidden 0.2 s.
  - **Sweep** after two pulses (3.2 s) while still loading: the capsule widens to 128 pt over 0.35 s into a track (white at about 24 %) with a fill (white at about 80 %) that grows from the left over 0.33 s, retracts to the right over 0.33 s and stays empty 0.4 s, looping.
  - **Finish** when the load ends, finished or stopped: the capsule flashes to a full fill, then shrinks towards its centre and fades out over 0.3 s. A load that ends before the capsule has shown anything draws nothing.
  - **Tab switch:** the new tab's state shows at once, without the finish animation: a tab that's still loading starts its pulse from the switch, since the snapshot doesn't say when its load began.
- **Look.** 4 pt tall, fully rounded, 3 pt below the window's top edge. In Dark Mode, white at the opacities above; in Light Mode, black at about the same opacities, as measured. Drawn with Core Animation, not a shader. We take Arc's behavior, not its code or assets.

### D5. New Incognito Window in the Dock menu

- **The problem:** with no windows open, Clair's Dock menu offers New Window but not New Incognito Window. Chromium's `-[AppController applicationDockMenu:]` adds the incognito item only when `lastProfileIfLoaded` returns a profile, so that it can check whether policy disables or replaces incognito, and Chromium unloads the profile once its last window closes. The bare engine behaves the same, so it's Chromium's behaviour, not the native window's (found 2026-11-07).
- **The patch:** `patches/clair/dock-incognito.patch` adds the item even when no profile is loaded. Choosing it goes through `commandFromDock:`, which already loads the last profile before running a command, as it does for New Window. With a profile loaded, Chromium's checks run as before. Clair sets no incognito policy, so the unloaded case can assume incognito is available.
- Alternative: keep a profile alive while no windows are open. Rejected: it changes Chromium's profile lifetime for one menu item.

### D6. One engine build

The header additions (D3, D4), the overlay changes (D1, D3, D4) and the Dock menu patch (D5) land together; task group 2 settles the header against `FakeBrowser` first, as `replace-browser-window` did, so the engine builds once. `ClairUI` work on the menu and indicator proceeds against the fake meanwhile.

## Risks / Trade-offs

- **[Risk] A page that never leaves `LOADING_UI_REQUESTED`** (a main-frame load that hangs) shows stop and the indicator indefinitely. → That's Chromium's toolbar behavior too, and stop ends it.
- **[Risk] `BackForwardMenuModel` changes between Chromium versions** (in 156 it builds its items from sections: history, chapter stops, back-to-opener, "Show Full History"). → The overlay reads only history items and "Show Full History" through `BackForwardMenuModel`'s section queries and the navigation controller, so a rebase breaks the build, not behavior, and the patch check catches it.
- **[Risk] Updating an open `NSMenu`'s item images** may not redraw on every macOS version. → Fallback: the session waits briefly (up to about 100 ms) for missing favicons before `ClairUI` opens the menu, and otherwise shows a globe.
- **[Risk] The capsule in the top inset** could catch clicks meant for the window-drag area. → It takes no mouse events (`hitTest` returns nil).

## Measurements

Task 1.1, 2026-11-07: Arc 1.x on macOS 27.2, driven with the XCUITest probe, a dark Space theme, a 960 × 1050 pt window with the sidebar 230 pt wide. Test pages came from a local server reached as `lvh.me` (Arc shows its developer toolbar and no stop button for `127.0.0.1`).

**History menu**

- **Opening:** right-click on back or forward, with or without Option. Press-and-hold couldn't be measured: XCUITest's `press(forDuration:)` doesn't register with Arc's buttons at all (even 0.05 s neither navigates nor opens anything), and Arc ignores synthetic mouse events. A ≥ 1 s hold showed the button's pressed state and no menu.
- **Look:** not an `NSMenu` but a popover. A dark rounded panel (radius about 12 pt, in the Space's theme colour), 220 pt wide, with an arrow at the top whose tip sits about 10 pt below the button, centred on it; the panel's top is about 16 pt below the button. Rows are 204 × 40 pt, from 8 pt inside the panel and stacked with no gap, with 8 pt of padding below the last. Each row has the favicon at 16 pt, 8 pt in, then the title 5 pt after it in white, about 13 pt semibold, one line. The hovered row gets a rounded (about 8 pt) pill of a lighter tint of the theme colour. No separators, no "Show Full History", no chapter stops, no icons for missing favicons seen.
- **Entries:** nearest first; the forward popover centres on the forward button. At most 10 rows, in a scroll view exactly 10 rows tall, with only 10 rows in the accessibility tree (Chromium's model lists 12).
- **Choosing:** a click goes there and closes the popover; Esc closes it. Cmd-click opens the page in a new background tab, which Arc places directly below the current tab, and closes the popover. Option-click behaves like a plain click, and holding Option changes nothing in the rows, so no `isAlternate` item showed. A middle click couldn't be sent (XCUITest has none on macOS).

**Reload and stop**

- While a page loads, the button shows ✕ (its accessibility label stays "Reload this page"). When the load ends with the pointer on it, it turns back into reload at once: Arc has no hold.

**Loading indicator**

- **Where:** not along the card's edge, but a capsule in the 10 pt inset above the card, 4 pt tall, 3 pt below the window's top edge, centred on the card (with the sidebar shown and hidden).
- **Not tied to progress:** it runs on time alone. From navigation start, a 44 pt capsule pulses: it fades in from nothing to white at about 78 % opacity while growing to 48 pt, and back, in nearly straight ramps over about 1.4 s, then stays hidden about 0.2 s (a 1.6 s cycle). After two pulses (about 3 s), if the load is still running, it widens to 128 pt over about 0.35 s and becomes a track (white at about 24 %) with a fill (white at about 80 %) that sweeps: it grows from the left edge to the full width in about 0.33 s, its left edge follows to the right in about 0.33 s, then the track stays empty about 0.4 s (a 1.07 s cycle), until the load ends.
- **End:** when the load finishes or is stopped, the capsule flashes to the full fill, then shrinks towards its centre and fades out in about 0.25–0.4 s.
- **Light Mode:** the same shapes and timing, mirrored: over the light inset (about rgb(238, 233, 247)), the pulse peaks at black about 70 %, the track is black about 22 % and the fill black about 78 %.
- **Not shown:** for a fast load (under about 0.1 s), a load failing at once (connection refused), and same-document navigations (`history.pushState` every 0.5 s). Background tabs weren't measured.
