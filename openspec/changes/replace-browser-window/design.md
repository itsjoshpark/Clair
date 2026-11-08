# Design

## Context

See `proposal.md` for why, and `specs/` for the required behavior. This section covers what shapes the approach.

- **Today:** Chromium starts `ClairUI` once the main menu exists (`clair::StartNativeLayer`, change 1's D1), before any `Browser` is created. `ClairUI` holds one `id<ClairHost>` and adds the update item and the About window. Every browser window is Chromium's Views `BrowserView`.
- **The engine is Chromium 156.0.8078.79** (ungoogled-chromium 156.0.8078.79-1). Every engine change costs an owner-started build on the owner's Mac, so hooks and the contract should settle early, and most iteration should happen in `ClairUI`, which builds in minutes.
- **Chromium's source is available read-only** in the runner's persistent workspace on the owner's Mac, `~/Developer/clair-actions-runner/_work/Clair/Clair/build/src`, patched as of the last engine build. Implementation checks hook sites and APIs there, and never writes to it or builds in it. The hook sites below were checked there.
- **Two references:**
  - **Crest** (`pauljoda/Crest`, MPL-2.0) ships this architecture on Chromium 156. Its `CrestBrowserWindow` (adapted from Mori, MIT) implements Chromium's `BrowserWindow` behind its SwiftUI window, with a no-op `LocationBar` and `FindBar`, an `ExclusiveAccessContext` and a `WebContentsModalDialogHost`. Its `native-host.patch` touches about 95 files, but most of that serves Crest's WebKit engine, its C# core and its own privacy policy. The window itself needs the factory, bubble anchors, toasts, downloads, DevTools and the crashed page.
  - **Chromium's own `WebUIBrowserWindow`** (`chrome/browser/ui/webui_browser/`, behind the `WebUIBrowser` feature) is Chromium's in-tree `BrowserWindow` without a `BrowserView`. It shows which pieces such a window must supply (`WebUIStubLocationBar`, `WebUIBrowserExclusiveAccessContext`, `WebUIBrowserModalDialogHost`, `FindBarOwnerWebUIBrowser`, `WebUIToolbarExtensionsContainer`), and Chromium already skips the Views-only features (`SadTabHelper`, toasts, `BrowserElementsViewsImpl`) for it in a handful of places. Clair's code is BSD-compatible with it and copies its structure where it fits.
- **Constraints:** `CLAUDE.md`'s rule that patches are hooks only; `ClairHost.h` is an engine input; the development machine never fetches or builds Chromium; the runtime suite deletes the current user's Clair data, so it runs on hosted runners by default.

## Goals / Non-Goals

**Goals:**
- `Browser`, `TabStripModel`, session restore, commands, profiles and extensions stay Chromium's. Clair replaces only what draws the window.
- One mode: packaged Clair always uses the native window, so there is no second window to keep working.
- Settle the engine side (hooks, overlay, `ClairHost.h`) in as few engine builds as possible, and do the visual iteration in `ClairUI`.
- Test the fundamentals automatically, and leave less-used features to manual checks and fixes when they're found broken.
- Answer the spike's questions: how native it feels against Arc, the edit-to-run time, and which Chromium features needed native replacements.

**Non-Goals:**
- Clair's own sidebar organization (Spaces, pinned tabs, favorites, folders). The MVP layers it over Chromium's tabs, keeping each tab's place in Chromium's per-tab session data (`SessionService::AddTabExtraData`). This change's flat list mirrors `TabStripModel`.
- Native replacements for Chromium bubbles that work when anchored (permission prompt, page info, extension install). They stay Chromium's.
- Side panels and tab groups UI.
- Changing what Chromium's menus contain beyond D10.
- Empty windows, as Arc has them. A new Arc window shows no tab until one is chosen from the command bar, and Clair's always opens on a New Tab page tab. Arc probably also keeps the window open when its last tab closes, but that hasn't been checked. Matching it is a known limitation, deferred:
  - A truly empty window means a `Browser` with no tabs. Chromium closes a window when its last tab goes, and much of its code (commands, the location bar, find, DevTools) assumes an active `WebContents`, so this would take deep changes to existing Chromium files, against Clair's rule of leaving them alone.
  - The likely approach is a hidden placeholder tab. While the only tab is an untouched New Tab page, `ClairUI` leaves it out of the sidebar, shows a blank card and opens the command bar. A choice from the command bar then loads in that tab instead of a new one.
  - The engine's part would be hooks to keep the window open with a placeholder when the last real tab closes, to close the placeholder when a link from another app opens a tab, and to leave placeholders out of session restore.
  - The risk is keyboard tab switching (Cmd+1–9, Ctrl+Tab), which follows `TabStripModel` order while the sidebar wouldn't show the placeholder. That only applies while the placeholder is the window's only tab.
  - Estimated at 2–3 days, including one engine build. Before specifying it, check with the XCUITest probe what Arc does when its last tab closes.

## Decisions

### D1. Chromium keeps the browser; `ClairBrowserWindow` hands its window to `ClairUI`

`overlay/chrome/browser/clair/window/clair_browser_window.{h,mm}` implements Chromium's `BrowserWindow` (76 virtual methods in 156) for `TYPE_NORMAL` browsers. It owns an Objective-C bridge that implements the contract's `ClairBrowser` protocol (D3), and it keeps the `id<ClairWindow>` that `ClairUI` returns. Alongside it, as `WebUIBrowserWindow` has them:

- `ClairLocationBar`: a stub `LocationBar` (Chromium dereferences it on every tab switch). `FocusLocation` opens the command bar. It has no chip controller, so permission requests use the bubble rather than the chip.
- `ClairFindBar` and its owner: the find UI is native (D8). They drive `FindTabHelper` and report results to `ClairUI`.
- `ClairExclusiveAccessContext`: page full screen (D6).
- `ClairModalDialogHost`: a `WebContentsModalDialogHost` whose host view is the card, so tab-modal dialogs centre on the page.
- `ClairExtensionsContainer`: Chromium's `ExtensionsContainer` for the sidebar's actions (D7).
- `ClairStatusBubble`: forwards link-hover URLs to the status capsule.
- `ClairDevToolsHost`: docked DevTools in the card (D5).

Each `BrowserWindow` method falls into one of four groups, listed in the class's header: forwarded to `ClairUI`; answered from the `NSWindow` (bounds, state, activation); handled in the overlay (the helpers above); or one of D9's unavailable features, which does nothing and logs once.

**Alternatives considered:**
- **Dia's model** (`dia-architecture.md`): the Swift app owns the process and embeds Chromium as a framework with its own Objective-C++ API. Rejected: Clair would need its own start-up, app delegate, session restore and menus, plus a 200-header API, before showing a window.
- **A Views shell with native content**, as `WebUIBrowserWindow` hosts a WebUI page: a `views::Widget` whose content is `ClairUI`'s `NSView`. Chromium's bubbles would anchor without changes, but the window, its title bar, traffic lights, full screen and event handling would stay Chromium's `BrowserFrameMac`, which is what the Arc layout has to replace. Rejected.

### D2. Which windows are native, and what happens without `ClairUI`

- `patches/clair/native-window-hook.patch` makes `BrowserWindow::CreateBrowserWindow` call `clair::CreateNativeBrowserWindow(browser)` first for `TYPE_NORMAL` browsers. Pop-ups, app windows, Picture-in-Picture and undocked DevTools keep Chromium's windows: their chrome is minimal, and Arc doesn't restyle them either.
- **With `ClairUI` running, every normal window is native.** `ClairUIEntryPoint` gains `+windowForBrowser:` (D3), which always returns a window. There is no user default or other switch back to Chromium's window. If it ever returns nil, that's a bug: the overlay logs it and stops Clair with a `CHECK`, so it can't go unnoticed, rather than quietly showing Chromium's window.
- **Without `ClairUI`:**
  - **Framework absent:** the bare engine, which only CI's smoke test runs. The native layer isn't running, `clair::CreateNativeBrowserWindow` returns null, and Chromium builds its own `BrowserView` as before.
  - **Framework present but failing to load:** the loader in the overlay (`clair::StartNativeLayer`) logs the `NSBundle` error, shows an `NSAlert` saying Clair couldn't start its interface, and quits before any browser window opens.
- Rolling back a broken native window means shipping a fixed release. This trades a safety net for not keeping two kinds of window working (Risks).

### D3. The contract: `ClairHost.h` becomes the window contract

The header stays plain Objective-C, main-thread only, `NS_SWIFT_UI_ACTOR`. New protocols:

| Protocol | Implemented by | Holds |
|---|---|---|
| `ClairBrowser` | Chromium, one per native window | profile kind (regular, incognito, guest); the tab list and the active tab; each tab's page view; the active tab's docked DevTools view and layout (D5); tab commands (activate, close, move, duplicate, mute, close below); navigation (back, forward, reload, stop); open a URL or a suggestion; find; page info; extension actions; downloads; infobar buttons; `requestClose` |
| `ClairTab` | Chromium, value snapshots | a stable ID (Chromium's tab handle), title, URL, display text, favicon, loading, can-go-back/forward, audible, muted, crashed, and active capture and blocked-permission indicators |
| `ClairWindow` | `ClairUI`, one per native window | the `NSWindow`; callbacks for tab list, tab, active-tab and DevTools changes; showing the command bar; find results; status URL; toasts; infobars; page full screen; anchors for Chromium's bubbles (D7); extension and download changes; `browserDidClose` |
| `ClairAutocomplete` | Chromium, one per command bar session | start a query, results callback, accept keyword, open a suggestion with a disposition, stop |
| `ClairUIEntryPoint` | `ClairUI` | `+startWithHost:` as before, plus `+windowForBrowser:` returning a non-null `id<ClairWindow>` |

Rules:
- **Push, coalesced.** Chromium observes `TabStripModel`, each tab's `WebContents`, its favicon driver and the capture indicator, and posts changes to `ClairWindow` at most once per run-loop turn per tab. `ClairUI` never polls.
- **Snapshots, not pointers.** Swift receives immutable value objects and IDs, never anything that wraps a C++ object. A command naming a tab that no longer exists does nothing. After `browserDidClose`, the `ClairBrowser` object ignores every call.
- **Closing.** The window's close button calls `requestClose`, which runs `chrome::CloseWindow` and with it Chromium's `beforeunload` flow. The `NSWindow` closes only when Chromium calls `BrowserWindow::Close`, which tells `ClairUI` through `browserDidClose`. This keeps "Leave site?" prompts and the session working.
- **Activation.** `ClairUI` never activates the app itself. Showing and activating go through `ClairBrowserWindow::Show` and `Activate`, which use `activateIgnoringOtherApps:`, so change 1's background-relaunch hook in `chrome_browser_application_mac.mm` still keeps an idle-install relaunch in the background.
- The header remains an engine input. Every addition costs an engine build, so task group 2 settles the whole contract against a fake host before the first engine build of this change.

### D4. The window and key handling

- **The `NSWindow` comes from Chromium.** `ClairBrowser` hands `ClairUI` an `NSWindow` subclass from the overlay, `ClairNativeWindow`, which adopts Chromium's `CommandDispatchingWindow` with a `CommandDispatcher`, as Chromium's own windows do. `ClairUI` styles it (borderless title bar, full-size content view, traffic-light positions) and fills its content view. The window's delegate stays the overlay's, which reports activation, geometry, full screen and the close button to `ClairBrowserWindow`.
  - Chromium's `ChromeCommandDispatcherDelegate` and `BrowserWindowCommandHandler` reach the browser through Views' window bridge, which a native window doesn't have. The overlay has its own delegate and command handler with the same order and rules (reserved commands before the page, the rest after it), calling the browser directly, as `BrowserNativeWidgetMac` does.
  - Why: key equivalents, Chromium's reserved shortcuts (`PreHandleKeyboardEvent`), and the redispatch of keys a page didn't handle then work through Chromium's tested Mac code, and `chrome::FindBrowserWithWindow` finds the browser for menu commands.
  - Alternative: a Swift `NSWindow` with a forwarding hook for shortcuts, as Crest's `handleShortcutEvent:` does. Rejected, because it re-implements Chromium's dispatch order in Swift.
- **Layout**, from `arc-reference/look-and-behaviour.md`:
  - The sidebar is 228 pt wide by default.
  - The card is inset 10 pt at the top, trailing and bottom edges and 0 pt on the sidebar side, or 10 pt all round with the sidebar hidden, as in Arc, so hiding the sidebar moves only the card's leading edge (D18). Its corner radius is 8 pt, with a soft shadow.
  - The traffic lights sit at x+12/35/58, y+16 (Arc's accessibility frames), and move with the sidebar as it slides. AppKit's own title bar layout puts them there, through a title bar frame class on `ClairNativeWindow` (`place-traffic-lights-with-appkit`), so a new window title or any other title bar layout leaves them in place.
  - The top row's buttons are 32×32 at y+8: hide-sidebar at x+77, and back, forward and reload ending 6 pt from the sidebar's trailing edge, 2 pt apart, in Arc's grey. Below 214 pt the row is compact, as in Arc: 28×28 back, forward and a "More" menu (reload and Hide Sidebar) at y+10.
  - The URL field is 36 pt high at y+46, inset 8 pt, with a 10 pt corner radius. The host starts 12 pt in; a new tab page shows a magnifier and the placeholder. Under the pointer, 30 pt copy and site-controls buttons show at its trailing end; page info still attaches where the site-controls button shows.
  - The window background is one `NSVisualEffectView` (`.sidebar` material, behind-window blending).
  - There's no Space theme yet, so the accent colour is the system's.
- **Views:** AppKit for the window, the card container and the page view host, so a resize lays out the page directly. SwiftUI in `NSHostingView`s for the sidebar, command bar, find field, toasts, infobars and downloads list. Overlays (command bar, find, toasts, status capsule, revealed sidebar) are views above the card in the same window, so the window stays key and its first responder can move between the page and the field.

### D5. Hosting the page and docked DevTools

- The card holds the active tab's `WebContents::GetNativeView()`. On a tab change, `ClairBrowserWindow::OnActiveTabChanged` tells `ClairUI`, which swaps the view, and the overlay updates both pages' visibility, as `WebUIBrowserWindow` does, so the old page reports `hidden`.
- Rounded corners come from the card layer's `cornerRadius` with `masksToBounds`, and the shadow from a parent layer, since a masked layer can't cast one.
- Focus: the page takes focus on tab activation and when the command bar or find closes (`WebContents::Focus`, or `RestoreFocus` when returning).
- **Docked DevTools.** In 156, `DevToolsWindow::UpdateBrowserWindow` (`devtools_window_views.cc`) hands docking to the browser's `DevtoolsUIController`, which `BrowserWindowFeatures` creates only when a `BrowserView` exists. For a native window it's null, so docked DevTools would never show.
  - The hook: in `UpdateBrowserWindow`, when there's no controller, call `clair::UpdateDevTools(inspected_web_contents)`.
  - `ClairDevToolsHost` asks `DevToolsWindow::GetInTabWebContents(contents, &strategy)` for the tab's DevTools and its `DevToolsContentsResizingStrategy`, and pushes a change to `ClairWindow`. It does the same on every tab switch.
  - `ClairUI` lays out the card as Chromium's `DevtoolsUIController` does: the DevTools view fills the card, and the page view sits on top at the strategy's bounds. The card's corner mask clips both.
  - DevTools' own dock-side menu (right, bottom, left, undocked) keeps working, because it changes Chromium's state and calls the same update. Docked to the right is Chromium's default.
- **The crashed page** is native. The hook in `sad_tab_controller` (or `tab_features`, as Chromium skips `SadTabHelper` for the WebUI browser) reports the crash, the tab snapshot's `crashed` flag is set, and `ClairUI` shows its view in the card, with Reload calling the tab's reload.

### D6. Full screen

- Window full screen is macOS's. `ClairBrowserWindow` reports it through `IsFullscreen` and the bounds methods, and Chromium hears each transition, as Crest's `CrestExclusiveAccessContext` does.
- Page full screen: `ClairExclusiveAccessContext::EnterFullscreen` asks `ClairUI` to show the page alone (no sidebar, insets or corners) and puts the window into macOS full screen if it isn't already. `ExitFullscreen` reverses only what it changed, so a window that was already full screen stays so. Chromium's exclusive-access bubble ("Press Esc to exit full screen") is a Views bubble; for this change it is replaced by a native capsule at the top of the screen that disappears after Chromium's usual time.
- Esc: Chromium ends page full screen when Esc reaches the page (`BrowserWebContentsDelegate::PreHandleKeyboardEvent`). The native window also hands Esc to the `ExclusiveAccessManager` itself during page full screen, so it works whatever has the keyboard, as Chromium's `BrowserView` accelerator does. An Esc while the window is still animating into full screen, when AppKit ignores a request to leave, ends full screen once the window is in.

### D7. The toolbar in the sidebar, and where Chromium's bubbles attach

- **Anchors.** `ClairWindow` answers `anchorFor:` with a rect in window coordinates for each surface: site controls, each indicator, each extension action, the extensions button and downloads. While the sidebar is hidden, revealed as an overlay or in full screen, every surface answers the fallback: the card's top-leading corner, offset as Chromium's `kNoToolbarLeftOffset` does. A revealed overlay slides away when the pointer leaves, which would orphan a bubble, so it isn't used as an anchor.
- **Views bubbles** with no `BrowserView`: the hook in `bubble_anchor_util_views.cc` returns the `ClairWindow` anchor for a native window, as Crest's hunk returns its own corner rect. The bubble's widget is made a child window of the `NSWindow`, so it moves with it. This covers the permission prompt (with no chip controller it uses the bubble), page info (the site-controls button and indicators call `chrome::ShowPageInfoDialog`) and the extension install prompt.
- **Extension actions:**
  - `ClairExtensionsContainer` reads `ToolbarActionsModel` for pinned order, and each action's `ExtensionActionViewModel` for icon, badge, title and popup, and pushes snapshots.
  - A click runs the action through Chromium.
  - A popup's page view comes from the popup's `ExtensionViewHost`, and `ClairUI` shows it attached to the clicked button, following its auto-resize (25×25 to 800×600), as Crest hosts its extension popups. `ClairUI` presents it in a borderless child window rather than an `NSPopover`: Crest found that on macOS 27 a popover tints the page it hosts with its own material.
  - `chrome.action.openPopup()` reaches the same container through `ShowToolbarActionPopupForAPICall`.
- **Indicators** come from the capture indicator and the tab's content settings, in the tab snapshot.
- **Downloads:**
  - The overlay observes each profile's `DownloadManager` and pushes snapshots: name, state, progress, whether it needs the user's decision (a dangerous file type), and whether it's been seen.
  - The list's actions call `DownloadItem` (open, show in Finder, cancel, resume, keep or discard).
  - The hook in `download_ui_controller.cc` routes a new download to this indicator for a native window, so Chromium shows neither its bubble nor its shelf.

### D8. Find, status, infobars and toasts

- **Find:** `ClairFindBar` implements `FindBar` (as `FindBarOwnerWebUIBrowser` does) and reports `FindNotificationDetails` to `ClairUI`. The field calls `FindTabHelper::StartFinding` and `StopFinding`. Cmd+F, Cmd+G and Shift+Cmd+G stay Chromium's commands, which reach the find bar through `BrowserWindow`.
- **Status:** the `browser_web_contents_delegate.cc` hook hands the hovered link's URL to `ClairStatusBubble`, which forwards the URL text. `GetStatusBubbles` returns none, since Chromium treats every bubble it returns as a Views one.
- **Infobars:** the overlay observes each tab's `InfoBarManager` and sends `ConfirmInfoBarDelegate`s as message, link and button snapshots, with their actions coming back through `ClairBrowser`. Infobars of other kinds are logged and dismissed, and none is expected in this release's flows.
- **Toasts:** the hook in `toast_controller.cc` sends a toast's string to `ClairUI` for a native window. Without it, `ToastController` reaches `CHECK_IS_TEST()` when it finds no anchor view. Zoom changes use the same toast path through the zoom bubble's entry point.

### D9. Chromium surfaces in the native window

| Surface | In the native window |
|---|---|
| Tab strip, toolbar, omnibox, location bar | Native: sidebar and command bar |
| Find bar, status bubble, infobars, toasts, sad tab, download bubble or shelf | Native (D5, D7, D8) |
| Exclusive-access bubble | Native capsule (D6) |
| Docked DevTools | Native host in the card for Chromium's DevTools page (D5) |
| Permission prompt, page info, extension install prompt | Chromium's Views bubble, anchored (D7) |
| Extension popup | Native popover hosting Chromium's popup page (D7) |
| JavaScript dialogs, HTTP auth, print preview, other tab-modal dialogs | Chromium's, through `ClairModalDialogHost`, placed over the card as child windows by a hook (D13) |
| Context menus | Chromium's `NSMenu`, shown through a hook (D13), without the items of unavailable features: split view, reading mode, QR code, send tab to self, Lens and translate |
| File pickers, color picker, date pickers | Chromium's, unchanged (native panels, or owned by the page) |
| Undocked DevTools, pop-up, app and Picture-in-Picture windows, profile picker, task manager | Chromium's own windows |
| `chrome://` pages | Tabs, unchanged |
| Zoom bubble | Toast (D8) |
| Bookmark bubble, bookmark star, bookmarks bar, Bookmarks menu | Removed (D10): the `BrowserWindow` methods do nothing |
| Password and autofill bubbles and popups | Turned off at the source (D17); the `BrowserWindow` methods also do nothing |
| Side panels (reading list, reader mode, extension side panels), tab search, Chrome Labs, Lens, QR code, send tab to self, sharing hub, cast, app menu, profile menu, tab groups UI, split view, customize Chrome, PWA install and intent picker, EyeDropper, caret browsing dialog, translate | Unavailable: the `BrowserWindow` method does nothing (returns null where it creates something, so the EyeDropper API rejects), logs once, and D10 hides the menu item |

Task 3.4 checks each row against the engine. A row that fails (a crash or missing UI) is fixed with a hook into overlay code. Its handling may move between "anchored" and "native" without a spec change, since the specs describe what the user sees, not who draws it.

### D10. Menus and shortcuts

Chromium's main menu stays, with these changes, applied by the overlay once `ClairUI` has started:

- **Hidden** (by command tag), with their key equivalents:
  - The whole Bookmarks menu, which takes Cmd+D, Shift+Cmd+B and Opt+Cmd+B with it.
  - The items for D9's unavailable features: View > Always Show Bookmarks Bar, Always Show Toolbar in Full Screen, Always Show Full URLs, Customize Chrome, the tab search, tab group and split view items, Cast, and Chrome Labs.
  - View's omnibox settings (Always Show Image Search Shortcut, Always Show AI Mode, Show Search Shortcuts), with no omnibox to apply to.
  - Any password or autofill item.

  Cmd+D stays unassigned until the MVP gives it Pin/Unpin Tab.
- **Cmd+T, File > New Tab:** in a native window, the window's command handler opens the command bar for `IDC_NEW_TAB`, whether it comes from the menu or the key, so no `browser_commands.cc` patch is needed. With a Chromium window key (DevTools, a pop-up) it runs `IDC_NEW_TAB` as before.
- **Cmd+L:** stays `IDC_FOCUS_LOCATION`, which reaches `ClairBrowserWindow::SetFocusToLocationBar` and opens the command bar on the current URL. `ClairUI` renames its File menu item from "Open Location…" to "Open Location Bar" when it starts, since "location" alone is vague to most people.
- **Cmd+S and Shift+Cmd+S:** Cmd+S moves from File > Save Page As… to a new View > Hide Sidebar item, which reads Show Sidebar while the sidebar is hidden. Save Page As… gets Shift+Cmd+S, as in Arc (`menus-and-shortcuts.md`). Shift+Cmd+S is free in Chromium's Mac menus. The native window's command dispatcher treats Hide Sidebar as reserved, so a page that handles Cmd+S itself can't keep it.
- Hidden items also lose their key equivalents, since AppKit still fires a hidden item's shortcut, and the native window's command handler keeps them hidden and disabled whenever the menu is validated.

The rest of `arc-reference/clair-menus.md` is the MVP's.

### D11. Command bar on Chromium's autocomplete

- `overlay/chrome/browser/clair/window/clair_autocomplete.{h,mm}` owns an `AutocompleteController` with `ChromeAutocompleteProviderClient` for the window's profile, and implements `ClairAutocomplete`. It uses Chromium's default omnibox providers without `TYPE_BOOKMARK`, since the interface has no bookmarks.
- Queries use `AutocompleteInput` with `ChromeAutocompleteSchemeClassifier`, and inline autocomplete off, as Arc fills nothing in. The page classification is `OTHER` for Cmd+L and the new-tab-page classification for Cmd+T, so providers behave as they do for the omnibox in those places.
- A suggestion snapshot has:
  - its kind (search, URL, history, open tab);
  - its contents, description and destination;
  - an icon (the favicon or the kind's icon);
  - the open tab it matches (`has_tab_match`, from the client's `TabMatcher`);
  - its associated keyword.

  Up to five rows show, as in Arc.
- **Opening:** `Navigate` with the match's destination and transition. Cmd+T, Shift+Return and Cmd+Return use a new foreground tab, which D12's placement puts at the top of the sidebar. Cmd+L uses the current tab. A match with an open tab activates that tab and its window instead.
- **Empty query:** the window's tabs other than the active one, by last active time, then `TopSites` for the profile, built in the overlay rather than through zero-suggest, which ungoogled-chromium leaves without a remote source.
- **Keywords:** Tab on a match with an associated keyword re-runs the query in keyword mode, as `OmniboxEditModel::AcceptKeyword` does, and the bar shows the engine's icon and name.
- **Panel:** a SwiftUI view 764 pt wide (shrinking to fit the window), centred on the window, its top at 34% of the window's height, with a large soft shadow and no dimming. As measured in Arc: a 64 pt field row with an 18 pt magnifier 20 pt in and 19 pt text 50 pt in, a hairline inset 12 pt, then 50 pt rows whose 46 pt highlight is inset 10 pt, with a 16 pt icon and 15 pt text ("title — domain"). The selected row uses the accent colour.
- **Toggling:** the shortcut that opened the command bar closes it again, as in Arc; the other one swaps it for its own mode.

### D12. Sidebar behavior

- **Tab list:** a SwiftUI list over the tab snapshots, in `TabStripModel` order, which always matches the sidebar.
  - Keeping the two in step means Cmd+1–9, Ctrl+Tab, the choice of the next active tab after a close, and session restore all follow the sidebar with no extra code.
  - Drag to reorder calls `MoveTab`.
  - Rows are 40 pt high on a 41 pt pitch with an 18 pt favicon frame, as in Arc: a 36 pt pill from x+8 to 8 pt short of the trailing edge, the favicon at x+17 and the 14 pt title at x+43. The favicon itself is drawn at 16 pt in that frame, as Arc draws it (D18). The "New Tab" row has the same metrics. The list starts at y+90.
  - The active row is a translucent pill with a soft shadow that fades when the window isn't key.
  - Hover shows the close button, 26 pt square and 5 pt from the pill's trailing edge with a 10 pt glyph and its own hover background, as in Arc, and the speaker toggles mute.
  - The row's context menu is an `NSMenu` opened from AppKit rather than SwiftUI's `contextMenu`, which makes the list draw a selection ring around the right-clicked row (D18).
  - Incognito windows use a dark appearance and an "Incognito" header with the `eye.slash` symbol, which also replaces Chromium's goggles as the incognito new tab's icon.
- **New tabs at the top.** `TabStripModel::AddWebContents` places a tab with no forced index at the end, or next to its opener for a link (`DetermineInsertionIndex`).
  - The hook: for a native window's tab strip, when no index is forced, `clair::NewTabIndex` returns 0.
  - Covered: Cmd+T, links opened in new tabs (foreground or background) and `chrome.tabs.create` without an index.
  - Not affected: session restore and Reopen Closed Tab, which pass explicit indices and so return tabs to their old positions.
  - Opener tracking still records the opener, so closing a tab opened from a link still returns to its opener, as Chromium does.
- **Hide and show:** the sidebar slides and the card's frame grows or shrinks with a spring (SwiftUI's `Spring(response: 0.2, dampingRatio: 0.9)`, tuned against a 60 fps recording of Arc, which takes about 0.15 s). `NSAnimationContext` can't drive this: the frames are laid out in `layout()`, so a display link steps the spring and lays out each frame, and a second Cmd+S mid-flight turns around from the current velocity. The page resizes live during the animation. If that judders, the fallback is a snapshot of the page during the animation, resizing once at the end (Risks).
- **Hover reveal:** a 6 pt tracking strip at the leading edge, a 100 ms delay before revealing (Arc's is 100–117 ms), and a translucent rounded overlay inset 5 pt from the window edges, sliding in on a quicker spring with a slight overshoot (Arc's slides in within about 100 ms). Leaving the overlay hides it after a short delay.
  - Showing the sidebar while it's revealed docks it where it is: the floating sidebar becomes the docked one in place, and only the card moves to make room, as in Arc. The sidebar's position and the card's frame follow separate springs so the card can move alone (D18).
  - The tracking area is rebuilt whenever the window lays out, so a pending reveal isn't restarted by a new request, and only the current area's enter and exit events count: AppKit still reports the exit of the strip the overlay's area replaced, which otherwise conceals the overlay as soon as it shows.
- **Width:** draggable between 164 and 500 pt, Arc's limits. The width and the hidden state are stored in `ClairUI`'s user defaults and used for new windows. Restored windows use them too, since Chromium's session doesn't record them.

### D13. Engine hooks

`patches/clair/native-window-hook.patch`, one hunk per hook, each a call into `overlay/chrome/browser/clair/` that does nothing for Chromium's own windows, or a switch that turns a removed feature off:

| File | Hook |
|---|---|
| `chrome/browser/ui/views/frame/browser_window_factory.cc` | create `ClairBrowserWindow` (D2) |
| `chrome/browser/ui/tabs/tab_strip_model.cc` | new tabs at index 0 in a native window (D12) |
| `chrome/browser/devtools/devtools_window_views.cc` | docked DevTools to the overlay when there's no `DevtoolsUIController` (D5) |
| `chrome/browser/devtools/devtools_window.cc` | let a native window dock DevTools (Chromium only docks where a `DevtoolsUIController` exists), and hand the docked DevTools to the overlay when it first shows (D5) |
| `chrome/browser/ui/views/bubble_anchor_util_views.cc` | anchor rect for a browser without `BrowserView` (D7) |
| `chrome/browser/ui/toasts/toast_controller.cc` | toast to `ClairUI` (D8) |
| `chrome/browser/ui/webui/settings/settings_clear_browsing_data_handler.cc` | clearing history `CHECK`s for the `BrowserView`'s element to send a promo event; skip it when there's none, as Chromium's other users of that element do (D18) |
| `chrome/browser/ui/sad_tab_controller.cc` | skip the Views sad tab, which dereferences the `BrowserView`; the overlay's tab snapshot reports the crash (D5) |
| `chrome/browser/download/download_ui_controller.cc` | new download to the sidebar (D7) |
| `chrome/browser/ui/browser_web_contents_delegate/browser_web_contents_delegate.cc` | the hovered link's URL to the status capsule: Chromium casts every status bubble to its Views one, so a native window returns none and is told directly (D8; found on the first engine, where hovering a page crashed) |
| `chrome/browser/prefs/browser_prefs.cc` | Clair's password and autofill defaults (D17) |
| `chrome/browser/resources/settings/page_visibility.ts` | hide the "Autofill and passwords" section (D17) |
| `chrome/browser/ui/webui/new_tab_page/new_tab_page_handler.cc`, `chrome/browser/new_tab_page/feature_promo_helper/new_tab_page_feature_promo_helper.cc`, `chrome/browser/ui/extensions/extension_install_ui_desktop.cc` | skip the new tab page's footer and promo and the extension-installed toolbar hint, whose controllers only exist with a `BrowserView` (found by Crest on 156) |
| `chrome/browser/ui/read_anything/read_anything_side_panel_controller.cc` | closing the active tab otherwise reaches `CHECK_IS_TEST()` for a browser without a side panel |
| `components/constrained_window/constrained_window_views.cc` | place tab-modal dialogs (JavaScript dialogs, leave prompts, HTTP authentication, print preview) and browser-modal ones (the extension install prompt, which Chromium makes a sheet on a Views window) over the card. Chromium positions them only over a Views host, and otherwise leaves them in the middle of the screen (found in task 3.4). The placement lives in `overlay/components/constrained_window/clair_native_host_mac.mm` |
| `ui/views/widget/native_widget_mac.mm` | keep a Views widget whose parent view is in a native window (permission prompts, page info, extension and tab-modal dialogs) a child window of it. Otherwise it's a free top-level window, which the browser window covered, so the permission prompt couldn't be clicked (found in task 3.4's runtime tests). The attachment lives in `overlay/ui/views/cocoa/clair_native_parent.mm` |
| `chrome/browser/ui/cocoa/renderer_context_menu/render_view_context_menu_mac_cocoa.mm` | show a page's context menu without a Views widget, which Chromium otherwise requires, so no context menu opened (found in task 3.4); drop the items of unavailable features (adapted from Crest) |
| `chrome/browser/ui/BUILD.gn`, `components/constrained_window/BUILD.gn`, `ui/views/BUILD.gn` | the overlay's sources |

The first engine build already includes the hunks for call sites that Crest's `native-host.patch` and Chromium's own `IsWebUIBrowserEnabled()` checks show crash for a browser without a `BrowserView` on 156. Task 3.4 adds a hunk only when a surface in D9 fails without it, with the reason in the patch header, as Crest's patches state theirs. Behavior stays in the overlay, as the modified `chromium-engine` requirement needs.

### D14. Tests

The aim is the fundamentals, not every feature. A less-used feature that breaks is fixed when it's noticed.

- **Unit tests** (`native/ClairUITests/`, merge gate): logic only, against a `FakeBrowser` implementing `ClairBrowser`.
  - What they cover: tab order, insertion at the top and Close Tabs Below; the URL field's display rules; the command bar's keyboard handling and modes; bubble anchors and their fallback.
  - `ClairHostObjCxxTests.mm` keeps checking that the header compiles as Objective-C++.
- **Runtime suite** (`tests/runtime/`, quality checks): one test or more for each item in the build-pipeline delta's "Native window coverage" list.
  - XCUITest finds native views by accessibility identifier (`clair.sidebar`, `clair.tabRow`, `clair.urlField`, `clair.commandBar`, `clair.downloads`, `clair.toast`, `clair.devtools`, …), and DevTools Protocol checks page state.
  - New test pages:
    - a notifications permission page (Chromium's prompt shows before macOS's, so it works on a hosted runner without a camera or location);
    - a download served by `server.py` with `Content-Disposition`;
    - a page with an image for Copy Image's toast;
    - a full-screen page.
  - A test extension with a popup and a badge is loaded with `--load-extension`.
  - Existing tests that count windows or open tabs over DevTools keep working, since `Browser` and its targets are unchanged.
- **Checked by hand** through D15's loop, not by the suite: find, link status, infobars, the crashed page, tab-modal dialogs, the unavailable features and bookmarks removal, passwords and autofill off, the alert when `ClairUI` fails to load, and the command bar's history, search, keyword and incognito behavior.
- **Running the suite locally** is allowed (D15), knowing that it deletes the current user's Clair data.

### D15. Local edit-to-run loop

The spike measures edit-to-run time for a `ClairUI` change. Through CI it is a push plus a `quality.yml` run, which gives back results but not an app to use.

`scripts/run-local.sh` makes a local loop:
1. It downloads `chromium-engine-<key>` for the checkout once, caches it, and checks it against its SHA-256.
2. It builds `ClairUI` and packages ad hoc with `package.sh`.
3. It launches the app with a throwaway `--user-data-dir` under the scratch area and `--use-mock-keychain`, so the owner's own Clair data and keychain are never touched, as the engine smoke test already does. The app's user defaults (the sidebar's width and state, Sparkle's state) share the bundle ID's domain with an installed Clair, so the script saves that domain before the launch and puts it back afterwards.

It never fetches or builds Chromium, and it needs only `curl`, `gh`, Xcode and the repository's scripts, with no new packages. Its `*.test.sh` covers the cache, a key with no published engine, and the throwaway profile.

`CLAUDE.md` changes with it:
- Its "Local work is limited to…" sentence goes. It dates from development in a resource-constrained VM.
- "Never fetch Chromium or build it by hand on the development machine" stays, since the engine workspace lives on the same Mac.
- The runtime suite may run locally, with a note that it deletes the current user's Clair data. Hosted runners remain the default.
- The owner prefers few external packages on the development machine. Ask before adding one.

### D16. Measurements

Recorded in this file's Measurements section before the change is archived:

- **Feel against Arc**, side by side on the owner's Mac while Arc still runs: sidebar hide and reveal, tab switch, command bar opening and typing latency, window resize, scrolling a long tab list, and the inactive window. Each gets "matches", "close" or "worse" and a note.
- **Edit-to-run:** a one-line `ClairUI` change through D15's loop, and through a push and `quality.yml`.
- **Native replacements needed:** D9's table as it ends up, with each row that moved between groups and why.

### D17. Passwords and autofill turned off

Users are expected to keep passwords in a dedicated password manager, so Clair doesn't save or fill them.

- **Defaults:** the `browser_prefs.cc` hook calls `clair::RegisterProfilePrefOverrides`, which sets the default of each pref to false: `credentials_enable_service` (password saving and filling), `credentials_enable_autosignin`, `autofill.profile_enabled` (addresses, and Chromium's single-field autocomplete) and `autofill.credit_card_enabled`.
- **Existing profiles:** when the first native window for a profile is created, the overlay clears any user-set value for those prefs, so a 0.1.x profile that had them on follows the new defaults. There's no UI to turn them back on.
- **Settings:** the `page_visibility.ts` hook hides the section for regular profiles with the switches Chromium already uses for guest profiles. In 156 the section's menu item and page are gated by `yourSavedInfo` (with `autofill` beside it), and the menu hides any item a visibility object leaves out, so the hook lists every other section as visible. `chrome://password-manager` still opens when typed, so passwords saved earlier can be exported.
- **Bubbles:** with saving off, Chromium never asks for the password bubbles, and the `BrowserWindow` methods for them do nothing anyway (D9).
- An extension can still set these prefs through `chrome.privacy.services`. That's left alone. It's rare, and blocking it would mean patching the extension API.

### D18. Polish from the owner's pass

The owner's side-by-side pass against Arc, before the first release with the native window, found details that differ from Arc or that jar. Arc's figures come from the XCUITest probe (accessibility frames, window captures and 60 fps recordings) on 2026-11-07. Everything here is in `ClairUI`; the fixes that need the engine (the reload/stop flicker, the back/forward history menu and the loading indicator) are in `arc-navigation-feedback`.

- **Sidebar motion:** the reveal delay, quicker reveal spring, unchanged hidden inset and docking in place are in D4 and D12. The docked sidebar is transparent over the window's material, so while the card is under it, as when a revealed sidebar docks, a second copy of the material sits between the two.
- **Moving the window from the sidebar:** as in Arc, a drag that starts on the sidebar's empty areas moves the window. SwiftUI's `WindowDragGesture` covers the top row's background and the space around the URL field. The tab list is an `NSTableView` that would take every press, so it is only as tall as its rows and the drag area fills the rest of the sidebar below it. Controls, rows and tab reordering are unaffected.
- **Tooltips:** AppKit's tooltips (SwiftUI's `help`) never show in Chromium's window, so Clair draws its own, as Arc does, and uses no system tooltip anywhere. Measured from Arc: one shows about 470 ms after the pointer rests on a control and goes as soon as it leaves; it's a 28 pt capsule 10 pt below and after the pointer, with the label and the shortcut's keys as small, flat key caps. Arc tints it with the Space's colour; Clair uses the accent colour.
  - `TooltipCenter.shared` holds the app's one tooltip, and a `tooltip(_:shortcut:delay:)` modifier reports the pointer. Controls can nest, as a tab's close button in its row: the one entered last owns the tooltip, and leaving it hands it back.
  - The tooltip is drawn in a borderless panel of its own, a child of the window under the pointer, at whole-point coordinates and with the shadow on the capsule only, so the text stays sharp; it works the same over popovers and in full screen.
  - The wording is Arc's: "Hide sidebar ⌘S" ("Lock sidebar" while revealed), "Go back ⌘[", "Go forward ⌘]", "Reload this page ⌘R" ("Stop loading this page esc"), "Copy URL ⇧⌘C", "Site Control Center", "Close tab ⌘W" and "More options". A tab's row shows its full title after 3 s.
- **Fades:** the URL field's buttons fade in and out with the pointer, and the sidebar's hover backgrounds fade, over 0.15 s. The URL field's hover background is darker, as in Arc, where it's about 4% darker than the resting field.
- **No blocked-permission indicator:** the URL field no longer shows `hand.raised.slash` when a site had a permission blocked. Page info, from the site-controls button, still shows it.
- **Inactive window:** besides the fading pill and dimmed window controls, the top row's and URL field's glyphs dim and the active tab's pill is lighter while the window isn't key, as other macOS sidebars do.
- **Command bar:** the hosting view's height only changed on the next layout, so new results grew the content inside the old frame, which `NSHostingView` centres, and the field jumped up. The host now asks the window to lay out whenever its content's size changes, so the panel keeps its top and grows downwards.
- **Link status:** the capsule shows once the pointer has rested on links for about 0.5 s and hides about 0.5 s after it leaves them, fading both ways. While it shows, moving to another link updates it at once. The rules are a small state machine with its own tests; the controller only runs its timers.
- **New windows:** a window that first shows a single new tab page opens the command bar on it, as Arc's new windows do, so typing goes straight in. Esc leaves the new tab page. If the page navigates without it, as a link from another app, the command bar closes.
- **Colours, from Arc:** the URL field is a flat fill with no border: about 4.5% black in Light Mode and 18% white in Dark Mode (24% and 9% under the pointer). The active tab is 24% white in Dark Mode (16% while the window isn't key), against the near-invisible system control colour before. The top row's and the URL field's glyphs are medium weight.
- **Incognito badge:** Arc shows a barely lighter 22 pt capsule, 14 pt in, in the 37 pt row where a normal window shows its Space: a near-white crossed-out eye and "Incognito" in dim grey (about 40% white), 11 pt medium; the eye is 15 pt wide. Clair draws the same.
- **Dark sidebar:** in Dark Mode, including incognito windows, Arc's sidebar is near-black, about (16, 19, 25), where the system's sidebar material is grey. An opaque fill above the window's material (and the docking backdrop's, and over the revealed sidebar's) gives Arc's colour; it's clear in Light Mode. Any translucency let the desktop lighten it, and the window draws colours slightly lighter than given, so the fill's value is set to measure as Arc's.
- **The URL field:** its copy and site-controls buttons show while the pointer is anywhere over the key window's sidebar, not just the field. The host loses a leading `www.`, as in Arc. Its context menu offers Copy URL.
- **Copy URL:** Edit > Copy URL, after Copy, on Shift+Cmd+C, runs Chromium's `IDC_COPY_URL`. Chromium's own shortcut table, where Shift+Cmd+C inspects an element, comes before the menu's shortcuts, so `patches/clair/copy-url-shortcut.patch` removes that one entry. Opt+Cmd+C still inspects. A key monitor in `ClairUI` would also work, but the owner chose the one-line patch.
- **Hidden sidebar:** the whole 10 pt leading inset reveals it, and the revealed sidebar has a translucent window-background fill over its material, so it's less see-through.
- **Full screen:** the window controls live in the title bar's own window there, so their frames aren't read; the top row keeps Arc's place (y+8) and hide-sidebar starts 13 pt in, as in Arc.
- **"Copied Current URL":** Arc's popup, measured: 196 × 46 pt with a 12 pt radius, 8 pt inside the card's top-trailing corner, 14 pt semibold text 13 pt in, and a 31 pt key-cap share button 8 pt from the end whose glyph sits 1 pt above centre. It springs in from its top centre in about 0.2 s with a slight overshoot, stays about 5 s and shrinks back in about 0.17 s. Arc tints it with the Space's colour; Clair uses the accent colour. Edit > Copy URL (Shift+Cmd+C), the URL field's copy button and its context menu all show it; Edit > Copy URL now reaches the window's root view through the responder chain, rather than running Chromium's `IDC_COPY_URL` with its "Link copied" toast. The share button opens the system share menu for the page. Page full screen's notice uses the same popup and reads "To exit full screen, press [Esc]": Chromium's `|Esc|`, or a bare "Esc", is drawn as a key cap labelled "Esc" and isn't repeated in the text.
- **Tooltips, second pass:** the key caps have their depth back; the capsule has a softer, wider shadow; the sides are 10 pt, keys or not. A tab's title shows after 2 s. Any click, including the right click that opens a context menu, puts the tooltips under the pointer away until it leaves them.
- **The tab's speaker:** as in Arc, between the favicon and the title: the outline `speaker.wave.3`, or `speaker.slash` while muted, changing with SF Symbols' replace effect at 1.5× speed, at Arc's size (35 × 24 px drawn) and grey, in medium weight, on a 26 pt button with a hover background. It grows and fades in when a tab starts playing and out when it stops, the title sliding to make room. The tab list's rows ignore implicit animations, so the row keeps the speaker collapsed rather than removing it, and animates its own copy of the state; the button only ever shows the muted state Chromium reports, so it can't fall out of step with the tab. A runtime test reads the row's accessibility frames and checks these gaps and D12's favicon metrics, so a layout change that moves them fails. Its tooltip reads "Mute this tab" or "Unmute this tab". Rather than copy Arc's uneven spacing, the glyph sits 10 pt from the favicon and from the title, the same as the favicon and title of a row without it.
- **Command bar border:** in Light Mode Arc's is a hairline of solid mid-grey (it measures 180 on white); in Dark Mode, including incognito, a full point of grey whose inner half is lighter (77, then 94, around a (30, 32, 32) fill). Clair draws the same at whole-point coordinates, so each line stays one crisp pixel, with the greys set to measure as Arc's.
- **Clearing history:** `ClearBrowsingDataHandler` `CHECK`ed for the `BrowserView`'s element after clearing history, which crashed a native window; a D13 hook skips the event without one.
- **Sidebar colour in full screen (open):** the owner saw the sidebar change colour for about 2 s whenever the pointer moved over the tabs in full screen. On 2026-11-07 it didn't show in Light Mode, on the new tab page or on a loaded page, coming from the page or from the menu bar: frame by frame, only the hovered row and the cursor changed.

## Risks / Trade-offs

- **[Risk] Chromium code dereferences `BrowserView` for a browser that has none,** crashing on a path the suite doesn't reach.
  → D9's audit, `WebUIBrowserWindow` as Chromium's own list of what such a window needs, Crest's patch as a list of what broke for it on 156, and searches of the runner's source tree for `BrowserView` callers. A crash found later is fixed in a release.
- **[Risk] No fallback window.** A `ClairUI` bug that breaks every window makes Clair unusable until a fixed release, and the updater lives in `ClairUI` too.
  → The runtime suite's fundamentals run on `main` before any release, and the release checklist includes a pass through the window. The fix ships as a new DMG. Today the owner is the only user.
- **[Risk] Views bubbles parented to a non-Views `NSWindow`** may not position, move or close correctly.
  → Child-window attachment (D7), checked by the permission tests with the sidebar shown and hidden. Fallback: native replacements for those bubbles through `ClairHost.h`, as Crest does for permission prompts.
- **[Risk] Docked DevTools layout** reimplements what `DevtoolsUIController` does for Views, so resizing or dock-side changes may misplace the page.
  → The runtime test opens DevTools docked and checks the page's viewport. Fallback for a release: open DevTools undocked until it's fixed.
- **[Risk] Live page resizing during the sidebar's spring animation** judders, since each frame asks the renderer for a new size.
  → Measured in D16. Fallback: animate a snapshot and resize once at the end.
- **[Risk] Overlays above the page's view** (command bar, find, toasts) misdraw or lose events over Chromium's remote layers.
  → Checked early in task group 4. Fallback: child `NSPanel`s attached to the window for those overlays.
- **[Risk] A contract that misses something** costs another engine build.
  → Task group 2 writes the whole header and the fake host first, and task 3.3 builds it once with everything. Engine rebuilds are incremental (change 1's D11), so a late addition costs minutes to an hour, not a full build.
- **[Risk] Removing features users relied on:** saved passwords, autofill, bookmarks, side panels.
  → The proposal and the Changie fragment list them. Saved passwords stay exportable at `chrome://password-manager`, and bookmarks at `chrome://bookmarks`.
- **[Risk] Chromium rebuilds or revalidates menu items** that D10 hides or retargets.
  → Checked by hand through D15's loop, and Cmd+S and Cmd+T by the runtime suite. Fallback: hooks in `main_menu_builder.mm`, as change 1's design already names for its own items.
- **[Trade-off] Less runtime coverage.** Find, infobars, the crashed page and other less-used features have no automated test, so a regression there can ship.
  → Accepted. The owner uses Clair daily and fixes what breaks.

## Migration Plan

- **Order of work:** contract and fake host, then one engine build with the hooks and overlay, then `ClairUI` iteration against that engine through the local loop and `quality.yml` on the branch. The engine-key PR follows `CLAUDE.md`: build the engine before pushing docs.
- **Users' data:** nothing migrates. Session restore reopens the same windows and tabs in the native window. Bookmarks and saved passwords stay in the profile, out of the interface. Password and autofill prefs are cleared as D17 says.
- **Release:** the first release with this change says what changed and what's gone in its Changie fragment. The manual release checklist gains a pass through the window on a real display in Light and Dark Mode.
- **Rollback:** a fixed release. There is no switch back to Chromium's window.

## Open Questions

- The spring parameters, hover-reveal delays and exact row metrics: tuned by hand against Arc during task group 5, within what the specs allow.
- Whether page resizing during the sidebar animation needs D12's snapshot fallback: measured in D16.

## Measurements

The owner closed task 8.1 on 2026-11-07 without the separate write-up D16 asked for. Three polish passes against Arc (task groups 9 to 11) compared the window with Arc side by side with the XCUITest probe instead, fixed everything the owner found worse, and recorded Arc's measured figures where each fix is described, in D4, D12 and D18. The edit-to-run timings and D9's final table weren't recorded.
