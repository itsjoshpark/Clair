# Design

## Context

See proposal.md for why, and `specs/browser-window/spec.md` for the required behavior.

**What Arc does**, measured on 2026-11-07 in the owner's Arc (toggle on, macOS 27.2), with CGEvent drags (XCUITest's press-and-drag reached neither Arc's page nor its sidebar that day) and test pages that logged mouse events:

| Press 20–40 pt below the page top, then drag | Cursor | Window | Page |
|---|---|---|---|
| Empty space | arrow | moves | `mousedown`, one `mousemove`, then `mouseup` and `click` at the release |
| `user-select: none` text, `<button>`, `<img>`, `draggable` div, range input | arrow | moves | as for empty space: the button gets a `click`, the range moves one step, no `dragstart` |
| Element that cancels `mousedown` | arrow | moves | as for empty space |
| Selectable text | I-beam | stays | selects the text |
| Link | pointing hand | stays | `dragstart`: the link is dragged |
| Element with `cursor: text`, `pointer` or `grab` | as set | stays | gets every `mousemove` |
| Element with `cursor: crosshair` that cancels `mousedown` and `mousemove` | crosshair | stays | gets every `mousemove` |

- An earlier run had recorded "a cancelled `mousedown` keeps the drag"; that element held selectable text, so its I-beam, not the cancel, kept the window still. The rows above with explicit cursors settle it.
- The strip is 0–58 pt below the page view's top edge (58 moves, 59 doesn't), measured with the sidebar shown and hidden, on a page with a 60 px header and on a plain page with no header: it doesn't depend on the page's content. In both sidebar states Arc's page started 10 pt below the window's top; Clair measures from the page.
- A double-click in the strip goes to the page (`dblclick`) and doesn't zoom the window, although the system's title bar double-click action is Fill.
- In an inactive window, a drag from the strip brings Arc forward and moves the window.
- A drag that started below the strip and moved up into it also moved Arc's window. Clair doesn't copy that.
- The setting is "Allow window dragging from the top of webpages" in Settings › Advanced. Arc stores no value for it in the owner's profile, so on is taken as its default.

**What Clair does today** (0.1.2, same day): a key window's page gets every press, so the top of the page can't move it. Once, in an inactive window, a drag from the page's top 30 pt moved it, which matches AppKit's title bar (40 pt tall since `place-traffic-lights-with-appkit`) handling the press, since stock Chromium's `RenderWidgetHostViewCocoa` answers `mouseDownCanMoveWindow` with YES. The window's content view is `ClairUI`'s `BrowserRootView`, and the page view sits in `PageCardView`'s container, so a `ClairUI` view above the page view is in the path of Chromium's hit test.

**Constraints:** Clair leaves Chromium alone where it can. A small patch is acceptable, with the owner's approval, where it makes the behavior solid; here it does (D3).

## Goals / Non-Goals

**Goals:**
- Arc's outcomes for every row in the table, by Arc's rule: the cursor decides.
- The behavior in `ClairUI`, with the rule in AppKit-free code that unit tests cover; the engine only gets a one-line patch (D3).

**Non-Goals:**
- The Settings window. The preference's key and default are fixed here so that window only has to bind a toggle to it.
- Keeping drags for pages that cancel the press under the arrow cursor (some canvas apps and maps). Arc doesn't; doing better needs a signal from the renderer (D1's alternative).
- Copying Arc's stale-state quirk of starting a window drag when a drag from below enters the strip.
- Dragging Chromium's own windows (pop-ups, apps, undocked DevTools) from their pages.

## Decisions

### D1. A strip view over the page, decided by the cursor

`PageTopDragStrip`, an `NSView` with no drawing, sits in `PageCardView`'s container directly above the page view, so infobars, the crashed-page view and everything in `BrowserRootView` over the card (command bar, find, toasts, the revealed sidebar) stay above it and take their presses first. Its `hitTest(_:)` always returns nil, so it never takes a press, and feeds `PageTopWindowDrag`, a plain state machine with no AppKit in it:

1. **Press.** When `hitTest` runs with `NSApp.currentEvent` a `leftMouseDown` inside the strip, the press is armed if the preference is on (D5), neither the window nor the page is in full screen, `clickCount` is 1, no modifier key is held, and `NSCursor.current` is `NSCursor.arrow`. The machine records the press's `eventNumber`. AppKit's own hit test and Chromium's may both run for one press; arming is idempotent per event number. Any other press, including one that misses the strip, disarms.
2. **First drag.** When `hitTest` runs with a `leftMouseDragged` from the armed press (same event number) and the cursor is still the arrow, `ClairUI` calls `window.performDrag(with:)` with that event and disarms. If the cursor changed (the page set the I-beam or another cursor on the first movement), it disarms and the drag stays with the page. A drag from any other press does nothing, which avoids Arc's quirk.
3. **Safety net.** After the hand-off, a local monitor for `leftMouseDragged` and `leftMouseUp` swallows drag events that still reach the app, and swallows the release if they added up to more than 1 pt, so a drag that didn't start can't select text or click. It's removed at the release.
4. **Release.** Otherwise the release reaches the page as usual, as in Arc, so the page isn't left pressed; it can complete a click on a button the drag started on, as in Arc.

Double-clicks are never armed (`clickCount` 2), so they go to the page.

5. **A window that isn't key.** Chromium doesn't pass the first press in such a window to the page (no click-through: `acceptsFirstMouse:` is NO by default), so neither the page nor Chromium's hit test sees its drags. Left alone, AppKit's title bar would move the window from the window's top 40 pt whatever the preference. The strip takes that press itself instead: `hitTest` returns the strip, which accepts first mouse and answers NO to `mouseDownCanMoveWindow`, with the preference on or off, and the press activates the window as any other would. With the preference on, its first drag moves the window, whatever the cursor, which Chromium doesn't update in an inactive window, so text and links in the strip move it too. The page loses nothing, since it wouldn't have had the press.
   - Arc, measured: its page accepts the first click (click-through), so its strip applies there as in a key window, and with the setting off nothing moves it. Click-through in Clair would change every first click in an inactive window (a link would open instead of the window activating), so it wasn't taken.

- Why the cursor: it's available in `ClairUI` (Chromium sets it with `-[NSCursor set]` in the browser process), and it gives Arc's outcome for every measured row.
- Why `hitTest`: Chromium already hit-tests the content view for every mouse event, so the strip sees the first drag without an event monitor in front of the page or held events, and the page gets exactly what it gets in Arc.
- Why `performDrag(with:)`: it hands the move to the window server, so snapping, tiling and moving between displays and Spaces behave as for a title bar drag.
- Alternative (the previous plan): `ClairHost.h` gains a contract through which the overlay reports Chromium's input acknowledgements (`RenderWidgetHost::InputEventObserver`), and `ClairUI` holds drag events until the page's answer. It would keep drags for canvases that cancel the press under the arrow cursor, but costs an engine build and a riskier spike (the acknowledgements might not separate the cases), and diverges from Arc. Rejected; it remains the path if pages that need it come up.
- Alternative: a permanent draggable strip, as a title bar: AppKit moves the window on the press, and the page never sees it. Rejected: links, buttons and text at the top of pages would stop working, and Arc doesn't do it.
- Alternative: Chromium's draggable regions (`-webkit-app-region`). They exist for app windows, where the page declares its regions; ordinary pages declare none.

### D2. Where the strip is

The strip view's frame is the top 59 pt of the page view's frame, set in `PageCardView`'s layout next to the page view's own frame (the card, or the page's part of it when DevTools is docked), and hidden whenever the page view is. Its height is one constant with Arc's measurement next to it. It doesn't depend on scrolling, the sidebar's state, the card's insets or the page's content.

### D3. Keeping AppKit's title bar out of the page: a patch

Stock Chromium's `RenderWidgetHostViewCocoa` answers `mouseDownCanMoveWindow` with YES, so AppKit's title bar (the window's top 40 pt) moves the window from a press on the page, even one the page uses: in task 1.1 a link drag in the page's top 30 pt both started a link drag and moved the window. Chromium needs YES for frameless app windows, where a page marks its drag areas with `-webkit-app-region` and Chromium covers the rest with views that answer NO; in its own browser windows the page never reaches the title bar. In Arc, a press on the page never moves the window through the title bar.

- `patches/clair/page-cannot-move-window.patch` makes the override answer NO. It returns NO explicitly rather than dropping the override, since AppKit's default answers YES for a view that isn't opaque.
- Clair doesn't support PWAs or Chrome Apps (owner, 2026-11-07), the only users of `-webkit-app-region`, so nothing loses by it.
- Moves from the page then happen only through D1. The sidebar's empty areas and the window's edges are untouched.
- Alternative: a hook that asks the window and keeps YES for Chromium's own windows. Rejected as unneeded once app windows were ruled out.
- Rejected, after trying them in task 1.1 (owner's decision, 2026-11-07):
  - Making the window unmovable while the pointer is over the strip, from a tracking area. It worked, but kept a window-wide flag right only as long as every enter and exit was seen.
  - Toggling `isMovable` when the press arrives: the window server already has the old state, so the window still moved.
  - Answering NO to `mouseDownCanMoveWindow` in the strip: AppKit goes by the page view under it, since the strip's hit test returns nil.

### D4. The preference

- Key `ClairDragWindowFromPageTop`, a Boolean in `ClairUI`'s standard user defaults (the `dev.joshuapark.Clair` domain), registered with a default of true, next to `SidebarPreferences`. It applies to every window and profile, incognito included, since it's how the app behaves rather than profile data.
- Read at each press, so a change made with `defaults write` or, later, the Settings window applies to open windows at once with no observer to keep.
- The Settings window will show it with Arc's wording, "Allow window dragging from the top of webpages".

## Risks / Trade-offs

- **[Trade-off] Pages that cancel the press under the arrow cursor lose the drag to the window** (some canvas apps, maps and sortable lists that don't set a cursor), as in Arc.
  → Matches Arc, which is the target. D1's alternative covers it if it matters later.
- **[Risk] The feature relies on Chromium hit-testing the content view for drag events.** It's stock behavior (`shouldIgnoreMouseEvent:`), but a Chromium update could change it, and the feature would silently stop.
  → No automated test guards it, by the owner's choice; checking the drag by hand after a Chromium update catches it, and it's fixed then.
- **[Risk] `hitTest(_:)` also runs outside mouse handling** (cursor and tracking updates, accessibility).
  → The machine acts only when `NSApp.currentEvent` is a left-mouse down or drag whose location is inside the strip, and never claims the hit.
- **[Trade-off] In an inactive window, any drag from the strip moves the window**, even over text or a link, where Arc applies its cursor rule (D1, step 5).
  → Accepted by the owner (2026-11-07): the page wouldn't get that press anyway, so nothing is lost.
- **[Risk] The patch conflicts with a Chromium update** to `render_widget_host_view_cocoa.mm`.
  → It changes one method at the end of the file; the patch check reports a conflict.

## Measurements

Task 1.1, 2026-11-07, Clair 0.1.2's engine with this branch's `ClairUI` through `run-local.sh`, macOS 27.2, CGEvent drags (event numbers stamped as hardware's are; CGEvent leaves them 0), with the strip logging every hit test:

- **The hit test runs for drags.** `hitTest(_:)` ran twice per press (AppKit's and Chromium's) and once per drag event, from Chromium's `shouldIgnoreMouseEvent:`, with `NSApp.currentEvent` set to that event.
- **Cursor.** `NSCursor.current` was the arrow over empty space, an element cancelling `mousedown` and empty space in a cross-site `example.com` iframe; the I-beam over `cursor: text`, the pointing hand over links and `cursor: pointer`, the crosshair and the open hand as set. It updates once the pointer moves, before the press.
- **Event numbers.** A press and its drags share `eventNumber`.
- **Outcomes, matching Arc's table:** empty space, the cancelled `mousedown` and the iframe's empty space moved the window, and the page got the press, one `mousemove` and the release; `cursor: text`, `pointer`, `crosshair`, `grab` and links stayed with the page (all movements, or `dragstart` for the link). The strip ended at 58/60 pt with the sidebar shown and hidden; in a 120 px header, 60 and 80 pt stayed with the page; a press at 100 pt dragged up into the strip stayed with the page. A `<button>`, an `<img>`, a `draggable` div and a range input moved the window, with the page getting the press, one `mousemove`, the release and a `click` (no `dragstart`; unlike Arc, the range didn't move a step); selectable text selected and the window stayed. A link click and a double-click in the strip reached the page (`click`, `dblclick`), and the window kept its size.
- **`performDrag(with:)`** starts from the first drag event, and the release reaches the page afterwards. With synthetic events the window sometimes moved less than the pointer (−6 of −40 pt once) when they came 16 ms apart; at a person's speed it followed.
- **Title bar.** A link drag in the page's top 30 pt moved the window as well as dragging the link, through AppKit's title bar. Setting `isMovable` from a press monitor only worked when it had already been false; answering NO to `mouseDownCanMoveWindow` in the strip didn't help; making the window unmovable while the pointer was over the strip fixed it, and the sidebar's top still moved the window. D3's patch replaces that; task 2.3 checks it on the built engine.
- **Inactive window.** Chromium didn't pass the first press to the page, and no drag reached the hit test. On the patched engine, AppKit's title bar still moved an inactive window from the page's top 30 pt, with the preference off too, since no view accepted the press. With D1's step 5, drags at 20 and 50 pt moved the window (over a link too), 70 pt didn't, and with the preference off nothing did. Arc, with its setting off, didn't move an inactive window from 20 or 45 pt, and its page got the click. Activation after switching to Finder with AppleScript was unreliable in this harness for any click, the sidebar included, so activation is checked by hand.
- **Preference off** (`defaults write`, no relaunch): drags from the strip stayed with the page in key and inactive windows, and the window didn't move; turned back on, the next drag moved it.

## Migration Plan

- The patch changes the engine key: `engine.yml` builds the engine for the branch first (with the owner's go-ahead), then the PR's checks run against it, then `quality.yml` on the branch. Per `CLAUDE.md`, build the engine before pushing docs-only changes.
- On by default for everyone after the update. The Changie fragment says how to turn it off until the Settings window exists: `defaults write dev.joshuapark.Clair ClairDragWindowFromPageTop -bool false`.
- Rollback: the preference, or a release with the default turned off.
