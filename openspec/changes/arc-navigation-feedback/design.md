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

**What Arc does**, from a static read of its binaries (strings and class names only, not measured yet; task 1.1 measures it):

- `ArcCore` exposes `ArcBackForwardList` and `ArcBackForwardListItem` (with an `isAlternate` flag, maybe an Option-key variant), and `ARCUI`'s `BackForwardList.BackForwardListMenuManager` builds a menu anchored to the button (`MenuAnchorProviding`). Arc's buttons include a `LongPressButton` with `longPressDuration`. There's no "Show Full History" string.
- The loading indicator is `GlowProgressLoadingIndicatorView`, drawn with a Metal shader (`ARC_GlowProgressLoadingIndicator.bundle/default.metallib`) beside a `GradientBorderGlowView`, and `ArcCore` reports `loadProgress`.
- Tooltips are Arc's own: an `ArcTooltip` module with its own `TooltipWindow`, a delay and presentation of its own, and keyboard-shortcut hints (`tooltipKeyboardShortcut`, `optionKeyTitle`).

**Constraints:** every engine change goes into one contract addition and one engine build (D3 of `replace-browser-window`); no patch to a Chromium file is needed. Tests stay on fundamentals: unit tests for logic, a runtime test only for core navigation, hand checks for the rest.

## Goals / Non-Goals

**Goals:**
- Reload, stop and the tab spinner driven by the same state as Chromium's toolbar and tab strip.
- Arc's back/forward history menu, with Chromium's entries, favicons and navigation.
- An Arc-like loading indicator driven by Chromium's load progress.
- One engine build for all of it.

**Non-Goals:**
- **Custom Arc-style tooltips.** Arc's tooltips are a design system of their own (window, delay, fade, shortcut hints) used by every control in the sidebar, URL field and tab list, not a navigation feature, and they need nothing from the engine. Bundling them would make this engine-bound change wait on design work, or the reverse. `replace-browser-window`'s polish group adds system tooltips now; a later change, `arc-tooltips`, replaces them, starting from the static findings above and a probe recording of Arc's delay and fade.
- A history page, history search or "Show Full History" (Clair has no history UI yet; Chromium's `chrome://history` stays reachable by URL).
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
- The full row's reload button and the compact row's menu item (which only reads the state) use it. Unit tests cover the hover hold, the timeout, the double-click case and a tab switch.

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
- **Overlay.** `ClairHistoryMenuSession`, in `clair_browser_bridge.mm` (a new overlay file would need a line in the hook patch's `chrome/browser/ui/BUILD.gn` hunk, and `BackForwardMenuModel` is already in that target), owns a `BackForwardMenuModel` for the window's browser and direction and is its `ui::MenuModelDelegate`. `items` lists the model's history entries only, in order, skipping separators, chapter stops, "Show Full History" and the back-to-opener entry unless task 1.1 finds Arc shows an equivalent. `itemID` is the model index. `OnIconChanged` re-reads the items and calls the delegate. `openItem` calls `ActivatedAt(index, flags)` with the flags for the disposition (none, or Cmd for a new background tab), so Chromium's own navigation and new-tab code runs; a new tab then lands at the top of the list through the existing tab-strip hook. Activating or `close` ends the session, as does the tab changing.
- **`ClairUI`.** An AppKit `NSMenu`, popped up under the button with `popUp(positioning:at:in:)`, since SwiftUI's `contextMenu` can't open on a long press or update an open item's image. An `NSView` behind each back and forward `SidebarButton` (full and compact rows) handles `rightMouseDown` and a press held for Arc's duration (task 1.1; Chromium uses about 0.5 s), and leaves a short click to the button. While the menu is open, the delegate's updates set the matching items' images in place. Cmd-choosing maps to `NewBackgroundTab`. A `HistoryMenuBuilder` turns items into menu entries and choices into calls; it's unit-tested against `FakeBrowser`.
- Alternative: build entries from `NavigationController` directly. Rejected: it reimplements Chromium's labels, favicon fetching, cap and new-tab handling, which `BackForwardMenuModel` already tests.

### D4. Load progress and the loading indicator

- **Contract.** `ClairTab` gains `@property(readonly) double loadProgress`, `GetLoadProgress()` in [0, 1], meaningful while `isLoading`.
- **Overlay.** The bridge already watches each tab for infobars; it also observes each tab's `WebContents` for `LoadProgressChanged` and marks that tab changed, so progress rides the existing per-tab coalesced push (at most once per run-loop turn, on top of content's own throttling).
- **`ClairUI`.** `LoadingIndicatorView`, an AppKit layer-backed view in `BrowserRootView` over the card's top edge, in the top inset, as wide as the card and above it in z-order but below overlays (command bar, find, revealed sidebar). A `LoadingIndicatorModel`, free of AppKit and unit-tested, turns the active tab's `isLoading` and `loadProgress` into what to show: fade in when a visible load starts, advance smoothly towards the reported progress (never backwards within a load), run to the end and fade out when it finishes, fade out at once when stopped or failed, and jump to the new tab's state on a tab switch without animating. It hides in page full screen and follows the card as the sidebar hides or reveals.
- **Look.** A thin glow in the accent colour along the card's top edge, drawn with Core Animation (a gradient layer and a blurred copy), not a shader. Height, colour, blur, how far it extends past the card, whether it's tied to progress or loops, and the fade timings come from a 60 fps recording of Arc (task 1.1), and the measured values are recorded in this design before group 3. We take Arc's behavior, not its code or assets.

### D5. One engine build

The header additions (D3, D4) and the overlay changes (D1, D3, D4) land together; task group 2 settles the header against `FakeBrowser` first, as `replace-browser-window` did, so the engine builds once. `ClairUI` work on the menu and indicator proceeds against the fake meanwhile.

## Risks / Trade-offs

- **[Risk] A page that never leaves `LOADING_UI_REQUESTED`** (a main-frame load that hangs) shows stop and the indicator indefinitely. → That's Chromium's toolbar behavior too, and stop ends it.
- **[Risk] `BackForwardMenuModel` changes between Chromium versions** (in 156 it builds its items from sections: history, chapter stops, back-to-opener, "Show Full History"). → The overlay reads only history items through the `ui::MenuModel` interface, so a rebase breaks the build, not behavior, and the patch check catches it.
- **[Risk] Updating an open `NSMenu`'s item images** may not redraw on every macOS version. → Fallback: the session waits briefly (up to about 100 ms) for missing favicons before `ClairUI` opens the menu, and otherwise shows a globe.
- **[Risk] The glow over the card's top edge** could hide the page-top window-drag strip's area or draw over the card's corner mask. → It sits in the inset above the card and takes no mouse events (`hitTest` returns nil).
- **[Trade-off] No tooltips here.** Users see system tooltips until `arc-tooltips` lands.

## Measurements

Filled in by task 1.1.
