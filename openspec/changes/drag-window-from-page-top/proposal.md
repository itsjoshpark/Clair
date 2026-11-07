# Proposal

## Why

Clair's native window has no title bar, so the only places to grab it are the sidebar's empty areas, and with the sidebar hidden there's almost nothing to grab. Arc solves this with "Allow window dragging from the top of webpages" (Settings › Advanced), which is on in the owner's Arc: a drag that starts near the top of the page moves the window, unless the pointer is over something the page uses the drag for. People moving from Arc expect it, and Arc stops working on 2026-12-22.

## What Changes

- A drag that starts in the **top 59 points of the page** moves the window, with the sidebar shown or hidden, as in Arc. The strip is fixed: it doesn't follow the page's own header, whatever its height. The page still gets the press, so clicks, double-clicks and links there work as before.
- **The page keeps the drag when it shows its own cursor.** Where the pointer shows anything other than the arrow, the drag stays with the page: the I-beam over selectable text, the pointing hand over links, and the custom cursors of canvas apps, maps and draggable widgets (crosshair, grab…). Where it shows the arrow (empty space, non-selectable text, buttons, images), the window moves once the pointer moves, even if the page cancels the press, as in Arc.
- It works in an inactive window too, which a press there brings forward, and never in full screen. There the page doesn't get the first click, so a drag anywhere in the strip moves the window, over text or links too.
- **A preference, on by default,** decides whether this happens. It's stored in `ClairUI`'s user defaults so the Settings window can show it later as a toggle labelled as Arc's. That window isn't part of this change. Until it exists, the preference changes only with `defaults write`, and open windows follow a change at once.
- With the preference off, the page gets every press, as today, and a press on the page never moves the window.
- The behavior lives in `ClairUI`: a strip view over the page decides from the cursor and hands the move to AppKit. Chromium gets a one-line patch, as Arc's does, so that AppKit's title bar can't move the window from a press on the page, which today makes a link drag at the very top of the page also move the window.

**Out of scope:** the Settings window and its toggle; `-webkit-app-region` drag regions for normal browser windows; dragging from other parts of the page; Chromium's own pop-up, app and DevTools windows.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `browser-window`: adds dragging the window from the top of the page and the preference that turns it off. The capability is introduced by `replace-browser-window`, which isn't archived yet, so this change adds requirements to it and is archived after it.

## Impact

- **Engine:** a new `patches/clair/page-cannot-move-window.patch` makes `RenderWidgetHostViewCocoa`'s `mouseDownCanMoveWindow` answer NO. It only served `-webkit-app-region` in app windows (PWAs, Chrome Apps), which Clair doesn't support. The engine key changes, so `engine.yml` builds a new engine. The feature also relies on stock Chromium behavior: the page view hit-tests the window's content view for every mouse event (`-[RenderWidgetHostViewCocoa shouldIgnoreMouseEvent:]`) and sets the cursor through `NSCursor`.
- **Native layer:** the strip view, the drag rule and the preference in `native/ClairUI/`, with a few unit tests of the core rule in `native/ClairUITests/`.
- **Tests:** deliberately light, at the owner's request: no runtime test. The cases are checked by hand against Arc, and regressions are fixed when they show up.
- **Users:** a new behavior, on by default, so a Changie fragment describes it and how to turn it off until the Settings window exists.
