# Design

## Context

See proposal.md, "Why". What shapes the approach:

- **Shift+click reaches the browser as `NEW_WINDOW`.** `ui::DispositionFromClick` maps Shift to `WindowOpenDisposition::NEW_WINDOW` on macOS. A plain link arrives at `BrowserWebContentsDelegate::OpenURLFromTab`; a `target="_blank"` link creates its contents first and arrives at `AddNewContents`. "Open Link in New Window" from the context menu also uses `NEW_WINDOW`, but isn't renderer-initiated.
- **Chromium has no Peek to reuse.** Its Link Preview (`PreviewTab`, a WebContents outside the tab strip) is gone from the tree; only a stale `friend class PreviewTab` in `tab_helpers.h` remains.
- **Chromium assumes a page is a tab.** 87 non-test files in `chrome/browser` call `tabs::TabInterface::GetFromContents`, which `CHECK`s. A page outside the tab strip hits the same class of crash as the tab-dialog crash #109 fixed.
- **Clair's overlay already owns the relevant paths:**
  - `ExecuteCommand` in `clair_native_window.mm` runs every command for a native window, from menus and key equivalents, including `IDC_SELECT_NEXT_TAB`.
  - `ClairBrowserWindow::PreHandleKeyboardEvent` and `HandleKeyboardEvent` see keys before the page and keys the page didn't use.
  - `ActiveTabChanged` sets page visibility.
  - `clair::NewTabIndex` puts tabs at the top unless `ADD_FORCE_INDEX` is set.
- **Preferences live in ClairUI's `UserDefaults`,** as `ClairDragWindowFromPageTop` does.

**Arc, as measured** with XCUITest, accessibility frames and 60 fps recordings in a 1920×1050 window:

| | Measured |
|---|---|
| Page card | 1723×1030 pt, at x 187 |
| Peek card | 1386×1026 pt (80.4% of the card's width), centred on the card, 2 pt inset at top and bottom |
| Peek shadow | tight and even on every side, no offset: about 15% darker at the card's edge, gone 7.5 pt out (a 4 pt blur at 30% opacity) |
| Parent page | inset 9 pt per side at any window size (measured at 738 and 1678 pt cards on a coloured page), washed out toward the window background (light grey in Light Mode, dark grey in Dark Mode) |
| Buttons | 34.5×33.5 pt circles, 13.5 pt right of the card, top at +7.5 pt, centres 43.5 pt apart: Close, Expand, Split; glyphs 12 pt (×) and 14 pt (expand) across. They ride the card's top-trailing corner as it grows |
| Opening | the parent shrinks and washes out over about 150 ms with an ease-out; the card grows from the link's rectangle, covering two thirds of the way in the first 50 ms and settling by about 170–190 ms (a fitted curve of cubic-bezier(0.3, 1, 0.75, 1) over 190 ms) |
| Closing | the card shrinks toward the link with the same ease-out and is gone in about 85 ms; the parent returns and the wash fades over about 150 ms |
| Confirm pill | red capsule "× Confirm", grows from the × in about 100 ms, holds about 1 s, fades back in about 100 ms |
| Esc | page `preventDefault()` → Confirm; focused text field → Confirm; native `<dialog>` open → Peek closed at once |

## Goals / Non-Goals

**Goals:**
- Keep every Chromium feature working in a Peek (dialogs, permissions, find, DevTools, extensions) by making it a real tab.
- Keep the Chromium patch to the two delegate hooks; everything else goes in `overlay/` and `ClairUI`.

**Non-Goals:**
- Growing the card from the link's own rectangle; the click point stands in for it.
- Session data for Peeks.

## Decisions

### D1. A Peek is a real tab directly after its parent

The Peek is an ordinary tab in the window's `TabStripModel`, inserted at its parent's index + 1 with `ADD_ACTIVE | ADD_FORCE_INDEX`. Clair links the two in a per-window table in the bridge (`parent ↔ peek`, by tab handle), cleared when either tab goes. Chromium sees two tabs; ClairUI shows one row and draws the Peek over its parent.

While the Peek shows, it is Chromium's active tab, so the URL field, navigation, find, DevTools, page info, extensions and Cmd+W follow it with no special cases (spec "The window acts on the Peek"). Copy Link and Duplicate on the parent's row use the parent's own snapshot.

*Alternatives:*
- **A WebContents outside the tab strip, like Chromium's removed `PreviewTab`.** Every `TabInterface::GetFromContents` caller would need a guard, and tab-modal dialogs would crash as in #109.
- **A hidden second `Browser`.** Its tabs belong to another window, so bubbles, dialogs and DevTools would attach to the wrong window.

### D2. The trigger: two delegate hooks

`patches/clair/native-window-hook.patch` adds one call to the start of `OpenURLFromTab` and one to `AddNewContents`: `clair::MaybeOpenPeek(browser, source, params…)`. It returns true when it handled the navigation. It opens a Peek only when all of these hold:
- The window is native.
- The disposition is `NEW_WINDOW`.
- The navigation is renderer-initiated with a user gesture. This excludes the context menu and `window.open` without a click.
- ClairUI's `opensPeekOnShiftClick` is true.

When the source is itself a Peek, `MaybeOpenPeek` changes the disposition to `NEW_FOREGROUND_TAB` with no index, so the link goes to the top of the list. When the source's tab already has a Peek, which can only happen from the keyboard, the existing Peek navigates to the URL instead of a second one opening; for `AddNewContents`, the contents the page created are dropped.

For `OpenURLFromTab`, the hook navigates with `NavigateParams` at the forced index. For `AddNewContents`, it inserts the already-created contents at that index. Either way the new tab goes in the background, the hook records the link, and only then activates it, so ClairUI never sees the Peek as a tab of its own. It returns the new contents.

*Alternative:* translating the disposition in `DispositionFromClick`. That's in `ui/`, below the browser, and can't tell which tab clicked.

### D3. The contract

`ClairHost.h` (**BREAKING**):
- `ClairTab`: `peekParentID` (the parent's ID, or `ClairTabIDNone` for a normal tab) and `peekID` (the tab's Peek, or none).
- `ClairBrowser`: `closePeekOfTab:` and `expandPeekOfTab:`.
- `ClairWindow`:
  - `opensPeekOnShiftClick` (read when the hook runs).
  - `peekDidKeepEscape:` (show Confirm for the given duration).

`tabs` still lists every tab in strip order, Peeks included, so the engine's tab list stays the truth. ClairUI filters it.

### D4. Activation, visibility and the card

- **Activation:** selecting the parent's row activates its Peek when it has one. The sidebar highlights the parent row while either the parent or its Peek is active. Closing a Peek activates its parent explicitly, rather than leaving the choice to Chromium's opener logic. Closing first marks the Peek as closing, and the parent then reports no Peek (its snapshot's `peekID`), so the card starts closing the Peek as soon as the parent becomes active, without waiting about 350 ms for Chromium to unload the Peek's page. A parent made active any other way (the tab next to it closing, the command bar, an extension, a notification) shows with its Peek: the card shows both at once, and the bridge activates the Peek once the tab strip is done, so keys and Esc go to it. The closing mark clears if the Peek becomes active again, as after its leave-page confirmation is declined.
- **Visibility:** `ActiveTabChanged` reports both the Peek and its parent as visible while the Peek is active, and both as hidden when another tab becomes active (spec "Page shown in the card").
- **Parent behind the card:** `PageCardView` shows the parent's page view. A layer transform scales it down by 9 pt per side, which avoids resizing the page and a reflow. A wash view and a click catcher cover it; a click there closes the Peek.
- **The Peek card:** the Peek's page view sits in a rounded, shadowed container at 80% of the card's width and the card's height less 2 pt at top and bottom. The page view gets its final frame at once; only the container's layer animates.
- **Tab-modal dialogs:** `pageContainerView` returns the Peek's container while a Peek shows, so the Peek's dialogs centre on the Peek.

### D5. Animation

ClairUI records where the last left mouse-down in the card happened, through a local event monitor; a Peek opened from the keyboard grows from the card's centre. When a Peek appears, the card starts at a tenth of its size at that point (about a link's size; Clair doesn't grow it from the link's own rectangle, as Arc does) and grows to identity over 190 ms on Arc's fitted ease-out, opaque within 50 ms, with the buttons riding its top-trailing corner. The parent's shrink, its shadow and the wash run over 160 ms on a gentler ease-out. Closing runs the reverse on a plain card in the Peek's place, shrinking over 150 ms on the same ease-out and fading out between a third and two thirds of the way: by the time ClairUI hears that the Peek closed, its page view has gone with its tab, and the page's GPU content can't be snapshotted without the screen-recording permission. With Reduce Motion on, both are 150 ms fades. Expand drops the wash and the parent's scale, and moves the Peek's view into the full card without a grow animation.

### D6. Esc and Confirm

In `ClairBrowserWindow`, when the active tab is a Peek:
- **`PreHandleKeyboardEvent`:** if Confirm is armed (a deadline the engine keeps), Esc closes the Peek and returns `HANDLED`, so the page never sees it.
- **`HandleKeyboardEvent`:** an Esc the page didn't use closes the Peek, unless a text field has focus (`WebContents::IsFocusedElementEditable()`): that Esc counts as kept, as Arc treats it, whether or not the field used it.
- **An observer on the Peek's main-frame widget** (`RenderWidgetHost::InputEventObserver::OnInputEventAck`): it sees a `RawKeyDown` Esc acked as consumed, which covers both `preventDefault()` and a text field taking the key. It arms Confirm for 1 s and calls `peekDidKeepEscape:` with that duration.

ClairUI only animates the pill; clicking it calls `closePeekOfTab:`. Arc closes at once on a native `<dialog>`. If Chromium acks that Esc as consumed, Clair shows Confirm there instead; either is acceptable.

*Alternative:* a ClairUI `keyDown` monitor. It can't tell whether the page used the key.

### D7. Tab commands

`ExecuteCommand` in `clair_native_window.mm` handles these for native windows itself:
- `IDC_SELECT_NEXT_TAB`, `IDC_SELECT_PREVIOUS_TAB`, `IDC_SELECT_TAB_0`…`7` and `IDC_SELECT_LAST_TAB`: computed over the tabs that aren't Peeks. Selecting a tab that has a Peek activates the Peek (spec "Tab shortcuts treat a tab and its Peek as one").
- `IDC_DUPLICATE_TAB` and `IDC_MOVE_TAB_TO_NEW_WINDOW` while a Peek shows: act on the parent. Moving marks the Peek as closing and activates the parent, which Chromium then moves; the Peek, left without its parent, closes once (D8), with its leave-page confirmation.
- `IDC_CLOSE_TAB` while a Peek shows: closes the Peek and activates its parent explicitly (D4), rather than leaving the next tab to Chromium.
- `IDC_OPEN_FILE` (Cmd+O) while a Peek shows: expands it, as Arc does. Without a Peek it opens a file, as in Chromium.

### D8. Keeping the pair together

A `TabStripModelObserver` in the bridge:
- **When a parent closes or leaves the window:** closes its Peek, once the tab strip has finished, since it can't be changed from inside its own notification, and never twice. Until then the Peek still reports a parent, so it never shows as a row. A leave-page confirmation still runs per page, through Chromium's close flow; a Peek whose confirmation keeps it open becomes a normal tab.
- **When a parent moves:** moves its Peek to the parent's index + 1.
- **When a Peek is detached or moved by anything else:** unlinks it, which makes it a normal tab, and hides its parent unless that is shown.
- **Linking:** only a new tab that landed right after its parent in the same window becomes its Peek; `Navigate` can put it elsewhere, as in another window.

Expand only unlinks, since the Peek already sits at its parent's index + 1 (spec "Expanding a Peek").

### D9. Peeks end with the session

Before Chromium starts closing a native window's tabs, the window closes its Peeks, but only when no leave-page confirmation can still cancel the close, which would otherwise lose them:
- **Closing a window:** in `Close`, when `UnloadController::GetBrowserClosingStatus()` permits the close. Otherwise the Peeks close with the window's other tabs once every page has agreed.
- **Quitting:** from the close-all callback, which runs before session data is written for the quit, when no window has a beforeunload handler left to run.

A runtime test checks that relaunching restores the parent alone.

*Alternative, if the session still records them:* tag Peeks with `SessionService::AddTabExtraData` and drop tagged tabs on restore. That needs a patch in session restore, so it's the fallback rather than the first choice. After a crash, a Peek comes back as a normal tab below its parent; that's accepted.

### D10. Preference and Settings

`ClairPeekOnShiftClick` in `UserDefaults` defaults to on. The new Links page in `SettingsWindow.swift`, between General and Advanced, shows the toggle with the same row style as Advanced's. `opensPeekOnShiftClick` reads the preference live, so a change applies to open windows at once.

### D12. Reload turns into stop only for a slow load

Arc doesn't show stop while a Peek opens on a page that loads quickly. Recorded at 60 fps against a local server that delays its response, a Peek's reload turned into stop about 770 ms after the Shift+click whatever the page's delay (400 ms to 3 s), never for a 200 ms page, and crossfaded each way in about 100 ms. Clair's `ReloadStopMode` keeps Chromium's rules (arc-navigation-feedback design D2) and adds one: reload turns into stop only once the active tab's load has run 750 ms. A tab switch to a loading tab counts from the switch, since the snapshot doesn't say when its load began, except that stop stays when it shows already. Stop turns back into reload when the load ends, as before. The button crossfades its glyphs over 100 ms.

### D11. Link status

The status capsule lays out against the Peek container's bottom-leading corner while a Peek shows, and against the card otherwise.

## Risks / Trade-offs

- **[Session restore records a Peek before D9 closes it]** → A runtime test quits with a Peek open; the fallback is D9's extra data.
- **[A close or quit that a page asks about]** → The Peeks stay open until it's certain, so declining keeps them; confirming may record them, and they come back as normal tabs from session restore or Reopen Closed Window. Rare, and nothing is lost.
- **[Chromium picks a different tab after the Peek closes]** → D4 activates the parent explicitly, and the runtime test checks it.
- **[Scaling the parent with a layer transform blurs it or misplaces hit testing]** → The click catcher covers the parent, so it takes no input. If the blur shows, inset the frame instead and accept one reflow.
- **[Extensions or pages enumerating tabs see the Peek as a tab]** → Accepted. `chrome.tabs` lists it as the tab it is, and that keeps extensions working inside a Peek.
- **[A Shift+click from a cross-origin iframe or with `noopener`]** → It still arrives through one of the two hooks. Runtime tests cover a plain link and a `target="_blank"` link.

## Migration Plan

None. The preference defaults to on. Rolling back means reverting the patch hunk and ClairUI, which returns Shift+click to a new window.

## Open Questions

- Arc's tooltips, read by hovering with the probe: "Close ⌘W" and "Expand ⌘O". Clair uses them; Arc places them right of the button, Clair's tooltips below and after the pointer, as everywhere else.
- Esc with focus in a cross-origin iframe: Arc neither closes the Peek nor shows Confirm. Clair closes it, or shows Confirm when a text field there has focus, as for the main frame; the owner chose to keep that.
- The wash colour and opacity in Light and Dark Mode: match Arc by sampling pixels side by side.
