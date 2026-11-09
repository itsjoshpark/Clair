# Design

## Context

`BrowserRootView` reveals the hidden sidebar from a tracking area over the window's leading inset (6 pt), active in the key window: entering it started a 70 ms reveal, leaving it cancelled the reveal or hid a revealed sidebar after 300 ms. A tracking area hears nothing once the pointer is outside the window.

**Arc, measured** on 2026-11-08 by driving the owner's Arc with XCUITest (window moved right to leave room, sidebar hidden, pointer moves only, each case after resting on the page, with a control case and the screenshot checked):

| Pointer | Arc |
|---|---|
| Leaves through the leading edge, rests 40, 240 or 250 pt out, at any height level with the window | reveals, and stays revealed while the pointer rests there |
| Leaves through the leading edge, rests 260, 280, 300 or 380 pt out | doesn't reveal |
| Comes around the window without crossing it, rests 30 or 45 pt out | reveals |
| Comes around the window, rests 100 or 300 pt out | doesn't reveal |
| Beside the window but above or below it | doesn't reveal |

The same results held whether the pointer started near the edge or far from it, so the limit is a distance, not a speed. Arc's reveal starts 100–117 ms after the pointer arrives at the edge, and a pointer swept past without stopping doesn't reveal it.

## Decisions

### D1. Reveal on rest

The reveal waits for 80 ms without a mouse move (`revealRest`), restarted by every move in the strip (the tracking area reports moves) or in the area beside the window. That gives Arc's 100–117 ms once the slide starts, and a pointer passing through never rests. Layout, which rebuilds the tracking area, doesn't restart the wait. Hiding waits 100 ms after the pointer leaves (`concealDelay`), at the owner's request.

### D2. The area beside the window

Left of the key window and as tall as it, 50 pt wide (`overshootWidth`), widening to 250 pt (`wideOvershootWidth`) while the pointer was last in the window or in that area. Resting there reveals the sidebar; leaving it hides a revealed one. When the pointer leaves the strip or the revealed sidebar, the exit event's own position decides, not where the pointer is by the time the event is handled, so a slow exit on the edge counts as beside the window.

### D3. Following the pointer outside the window

A local `NSEvent` monitor for mouse moves, installed only while the sidebar is hidden and the window is key, and removed when the window resigns key, closes, or the view goes (`EventMonitors`). Measured on 2026-11-08 with a packaged build and a page counting events: the key window gets every move beside it (68 of 68), about 8 ms after the move (17 ms at worst), and the page received no `mousemove` while the pointer was outside (153 before, 153 after). A global monitor never fired, since the app is active whenever the window is key, so there is none.

- Alternative: setting `acceptsMouseMovedEvents`. Not needed: the window already gets those moves.
- Drags aren't followed, as the strip doesn't follow them, so a text selection dragged past the edge doesn't reveal the sidebar.

## Risks / Trade-offs

- **Clair on macOS 15.6** wasn't measured; the local monitor is the documented way to see an active app's events there too.
- **The 100 ms hide** is the owner's value, not a measurement; with event delivery it may feel slightly slower than Arc.

## Measurements

Clair, the same build and probe, pointer moves only, with the sidebar hidden as the owner set it up: the strip, 40 and 240 pt after crossing, and 30 pt from elsewhere revealed; 300 pt after crossing, 100 pt from elsewhere, and the page didn't.
