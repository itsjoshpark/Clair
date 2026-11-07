# Design

## Context

See proposal.md for why. Today:

- `ClairNativeWindow` (`overlay/chrome/browser/clair/window/clair_native_window.mm`) subclasses `NSWindow` directly and keeps AppKit's default title bar frame view.
- `ClairUI`'s `TrafficLights` (`native/ClairUI/BrowserRootView.swift`) calls `setFrameOrigin` on the standard window buttons from `BrowserRootView.layout()`. It puts them back after `NSView.frameDidChangeNotification` and `NSWindow.didUpdateNotification`, because AppKit's title bar layout resets them to its default spot (x+8, pitch 23, near the top) whenever it runs, such as after a title change.
- AppKit's own pitch between the buttons is already 23 pt, which is Arc's (12, 35, 58). Only the leading inset and the vertical place differ from what Clair wants.
- Chromium positions its browser windows' buttons through AppKit's layout instead: `BrowserNativeWidgetWindow` returns `BrowserWindowFrame` from `+frameViewClassForStyleMask:`, and that `NSThemeFrame` subclass overrides `-_titlebarHeight` (the buttons are centred vertically in the title bar) and `-_minXTitlebarWidgetInset` (the leading button's x). `components/remote_cocoa/app_shim/native_widget_mac_nswindow.h` declares `NSThemeFrame` weakly imported.

## Goals / Non-Goals

**Goals:**
- AppKit's own title bar layout puts the buttons where Clair asks, so no AppKit layout pass can move them.
- `ClairUI` keeps deciding where the buttons go, since it owns the sidebar's motion, and sets that once per change rather than fighting AppKit.

**Non-Goals:**
- The window's corner radius. Chromium also makes it concentric with the buttons on macOS 26 and later (`-_getCachedWindowCornerRadius`); that is a separate look question.
- Right-to-left layouts, which Clair doesn't support yet.
- Compacting the buttons in a narrow sidebar (Arc does; the owner ruled it out).

## Decisions

### D1. A title bar frame class in the overlay

`ClairNativeWindow` overrides `+frameViewClassForStyleMask:` to return `ClairWindowFrame`, an `NSThemeFrame` subclass in the same file, when the style mask is titled and `NSThemeFrame` exists at run time; otherwise it returns `super`'s, so a macOS without the class gets AppKit's default positions.

`ClairWindowFrame` overrides:
- `-_minXTitlebarWidgetInset`: the controls' x from the window's leading edge.
- `-_titlebarHeight`: the requested top plus 26 pt. AppKit doesn't centre the buttons vertically: task 1.3 measured them anchored 10 pt above the title bar's bottom edge on macOS 27 (requested tops of 10, 16 and 24 with a centring height landed at 10, 22 and 38), so the button's 16 pt plus that gap below it sets the height.
- `-layout`: after `super`, applies the hidden state to the three buttons, so AppKit's layout can't show them again. It then measures where the close button landed and, if that's half a point or more from the requested place, adds the difference to the inset and the height and lays out once more. A macOS that anchors the buttons differently still lands them right, at the cost of one extra layout the first time.

Accessibility reports the buttons a point up and left of their frames (measured in PR #92 and again in task 1.3), so `ClairUI` requests (13, 17) from the sidebar's corner for them to read back as Arc's 12/35/58 and 16.

In window full screen all three return or do `super`'s, as Chromium's frame does, since AppKit shows the title bar in the reveal strip there.

- Why: it is the supported way to move the buttons through AppKit's layout, and Chromium ships the same overrides, so Clair takes on no private API that Chromium doesn't already carry.
- Alternative: subclass `NativeWidgetMacNSWindowTitledFrame` to inherit its RTL and drag handling. Rejected: its drag handling is for Views' windows, and Clair has no RTL support yet.
- Alternative: keep re-placing from `ClairUI` (PR #92). Rejected: see proposal.md.
- Alternative: a hidden `NSToolbar` to make the title bar taller. Rejected: it moves the buttons only vertically, adds a toolbar the window otherwise doesn't need, and changes full-screen behavior.

### D2. The contract: the window carries the controls' place

`ClairHost.h` gains a protocol that the window `ClairBrowser` hands over adopts:

```objc
NS_SWIFT_NAME(ClairWindowControls)
@protocol ClairWindowControls <NSObject>
// The close button's top-leading corner, from the window's top-leading
// corner, in points.
@property(nonatomic) CGPoint windowControlsOrigin;
@property(nonatomic) BOOL windowControlsHidden;
@end
```

`ClairNativeWindow` stores both and, when either changes, marks the theme frame for layout and lays it out at once, so a display-link step moves the buttons in the same frame as the sidebar.

- Why: the frame reads its own window, with nothing to look up, and `ClairUI` keeps owning the sidebar's motion. A protocol on the window keeps `ClairBrowser` about the browser.
- Alternative: a method on `ClairBrowser` that forwards to the window. Rejected: one more hop for a property of the window.
- Alternative: the overlay computes the place from the sidebar's state. Rejected: the sidebar's motion lives in `ClairUI`, and the overlay would have to duplicate the spring.

### D3. `ClairUI` sets the place from the sidebar's frame

`BrowserRootView.layout()` already knows the sidebar's frame on every step of the hide, show and reveal springs. It sets `windowControlsOrigin` to the sidebar's top-leading corner plus (13, 17) (D1), and `windowControlsHidden` when the page is in full screen or the sidebar is wholly off the window, only when either value changes. `TrafficLights`' frame setting, its conversion between coordinate spaces and its observers go away.

The fake browser's window in `ClairUITests` adopts `ClairWindowControls` and records what it's given, so unit tests cover the values for the shown, half-hidden, hidden, revealed and full-screen states.

### D4. Verification against Arc

The positions are checked as PR #92 checked them: accessibility frames of the buttons (Arc reads 12/35/58, y 16) and 60 fps recordings of Cmd+S and the hover reveal, driven by XCUITest (CLAUDE.md, "Comparing with Arc and driving the UI"). The recordings also confirm that no frame shows the buttons at AppKit's default spot after a title change.

## Risks / Trade-offs

- [The private methods change or disappear in a future macOS] → `+frameViewClassForStyleMask:` falls back to `super`'s when `NSThemeFrame` is missing, and the overrides only change numbers AppKit already asks for. Chromium's windows break the same way, so the fix will be visible upstream.
- [A 43 pt title bar takes clicks or drags meant for the sidebar's top row, or for the URL field, whose top is at y+46] → with a full-size content view and a transparent title bar, AppKit passes clicks in empty title bar areas to the content, as it does for Chromium's own taller title bar. Task 3.2 clicks the top-row buttons and the field's top edge to confirm it.
- [Laying out the title bar on every display-link step stutters] → it lays out three buttons. If recordings show stutter, hide the controls while the sidebar moves and show them at the end, which the spec allows as long as they never show at AppKit's spot.
- [Accessibility frames and drawn positions differ by a point, as they did in PR #92] → the inset is tuned against Arc's accessibility frames, measured the same way, so both apps read 12/35/58 and 16.

## Migration Plan

The change ships as one PR: the overlay, `ClairHost.h` and `ClairUI` together, since the contract changes on both sides. The engine key changes, so `engine.yml` builds the engine (incremental on the owner's Mac) before CI's engine check passes. Rollback is reverting the PR, which also needs that key's engine, already published from before.
