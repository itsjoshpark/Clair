# Design

## Context

See proposal.md for why. Today:

- `ClairNativeWindow` (`overlay/chrome/browser/clair/window/clair_native_window.mm`) subclasses `NSWindow` directly and keeps AppKit's default title bar frame view.
- `ClairUI`'s `TrafficLights` (`native/ClairUI/BrowserRootView.swift`) calls `setFrameOrigin` on the standard window buttons from `BrowserRootView.layout()`. It puts them back after `NSView.frameDidChangeNotification` and `NSWindow.didUpdateNotification`, because AppKit's title bar layout resets them to its default spot (x+8, pitch 23, near the top) whenever it runs, such as after a title change.
- On macOS 27, AppKit's own pitch between the buttons is already 23 pt, which is Arc's (12, 35, 58). Only the leading inset and the vertical place differ from what Clair wants. Clair supports macOS 15.6 and later, where the buttons' size and spacing may differ; nothing here was measured on 15 or 26.
- Chromium positions its browser windows' buttons through AppKit's layout instead: `BrowserNativeWidgetWindow` returns `BrowserWindowFrame` from `+frameViewClassForStyleMask:`, and that `NSThemeFrame` subclass overrides `-_titlebarHeight` (the buttons are centred vertically in the title bar) and `-_minXTitlebarWidgetInset` (the leading button's x). `components/remote_cocoa/app_shim/native_widget_mac_nswindow.h` declares `NSThemeFrame` weakly imported.

## Goals / Non-Goals

**Goals:**
- AppKit's own title bar layout puts the buttons where Clair asks, so no AppKit layout pass can move them.
- `ClairUI` keeps deciding where the buttons go, since it owns the sidebar's motion, and sets that once per change rather than fighting AppKit.
- The window controls and the top row always line up, on any supported macOS. That matters more than matching Arc's exact place on versions other than macOS 27, which is best effort.

**Non-Goals:**
- The window's corner radius. Chromium also makes it concentric with the buttons on macOS 26 and later (`-_getCachedWindowCornerRadius`); that is a separate look question.
- Right-to-left layouts, which Clair doesn't support yet.
- Compacting the buttons in a narrow sidebar (Arc does; the owner ruled it out).
- Forcing Arc's 23 pt spacing between the buttons on other macOS versions: only AppKit can place the minimize and zoom buttons without the masking this change removes, so they keep the system's spacing.
- Measuring macOS 15 and 26 before shipping. If the place looks wrong there, the two constants in D1 get per-version values then.

## Decisions

### D1. A title bar frame class in the overlay

`ClairNativeWindow` overrides `+frameViewClassForStyleMask:` to return `ClairWindowFrame`, an `NSThemeFrame` subclass in the same file, when the style mask is titled and `NSThemeFrame` exists at run time; otherwise it returns `super`'s, so a macOS without the class gets AppKit's default positions.

`ClairWindowFrame` overrides:
- `-_minXTitlebarWidgetInset`: the controls' x from the window's leading edge.
- `-_titlebarHeight`: the requested top plus 23 pt. AppKit doesn't centre the buttons vertically: task 1.3 measured them anchored a fixed distance above the title bar's bottom edge on macOS 27, so the height sets their top. With `ClairUI`'s requested top of 17 that is a 40 pt title bar, and the buttons read 16 through accessibility.
- `-layout`: after `super`, applies the hidden state to the three buttons, so AppKit's layout can't show them again.

A first version measured where the close button landed after `super`'s layout and corrected itself. It was dropped: the title bar lays its buttons out after the frame's own `-layout` returns, so the measurement read their previous place and the corrections ran away. The runtime test (task 3.1) is what catches a macOS that measures differently.

Accessibility reports the buttons a point up and left of their frames (measured in PR #92 and again in task 1.3), so `ClairUI` requests (13, 17) from the sidebar's corner for them to read back as Arc's 12/35/58 and 16.

The 23 pt and the (13, 17) are measured on macOS 27 and are best effort elsewhere. A macOS that anchors the buttons differently puts them a few points off Arc's place, and D3's top row follows them there, so the window still looks coherent.

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

`ClairNativeWindow` stores both and, when either changes, has the theme frame re-tile its title bar at once (`-_updateTitlebarContainerViewFrameIfNecessary` and `-_updateButtonPositions`, each only if the frame responds), so a display-link step moves the buttons in the same frame as the sidebar. Task 1.3 found that marking the frame for layout isn't enough: AppKit reads the height and inset again only when it re-tiles, so without these calls the buttons stayed put during the slide and later stuck at a mid-slide place. Negative insets work, so the buttons slide off the window's edge with the sidebar.

- Why: the frame reads its own window, with nothing to look up, and `ClairUI` keeps owning the sidebar's motion. A protocol on the window keeps `ClairBrowser` about the browser.
- Alternative: a method on `ClairBrowser` that forwards to the window. Rejected: one more hop for a property of the window.
- Alternative: the overlay computes the place from the sidebar's state. Rejected: the sidebar's motion lives in `ClairUI`, and the overlay would have to duplicate the spring.

**Fallback where the buttons can't follow the sidebar.** If the theme frame doesn't respond to the two re-tiling methods, `ClairNativeWindow` can't move the buttons on each display-link step. It then hides them whenever `windowControlsOrigin` changes, and shows them again once the origin has stayed put for 150 ms, after asking AppKit to re-tile the title bar through a public path: re-setting the window's style mask to its current value. It logs this once per launch to the system log, under `ClairUI`'s subsystem `dev.joshuapark.Clair`, with `os_log`, not Chromium's `LOG`, which goes only to stderr: "The window controls can't follow the sidebar on this macOS; hiding them while it moves." Setting `CLAIR_WINDOW_CONTROLS_FALLBACK` in Clair's environment takes the fallback on any macOS, so it can be checked on macOS 27, where it isn't needed, without a scratch engine (task 1.4). On macOS 27 with the fallback forced (task 1.4), re-setting the style mask did re-tile the title bar: the buttons appeared at the revealed sidebar's place (17/40/63, y 21) and back at 12/35/58, y 16 with no private call, and the log line appeared once. On a macOS where it doesn't, the buttons appear at their place at AppKit's next own title bar layout, such as a title change, which is still never a wrong place.

### D3. `ClairUI` sets the place from the sidebar's frame

`BrowserRootView.layout()` already knows the sidebar's frame on every step of the hide, show and reveal springs. It sets `windowControlsOrigin` to the sidebar's top-leading corner plus (13, 17) (D1), and `windowControlsHidden` when the page is in full screen or the sidebar is wholly off the window, only when either value changes. `TrafficLights`' frame setting, its conversion between coordinate spaces and its observers go away.

### D3b. The top row is laid out from where the buttons landed

After setting the place, `BrowserRootView.layout()` reads the close and zoom buttons' accessibility frames (screen coordinates, converted to the sidebar's). The accessibility frames are what matched Arc's drawn buttons in PR #92, unlike the view frames. Re-tiling is synchronous, so they already show the new place; in the fallback, the read at rest catches up. `ClairUI` keeps two numbers, relative to the sidebar's top-leading corner, and updates the model only when one moves by half a point or more:

```
  centre line = close button's vertical centre            (24 on macOS 27)
  leading     = zoom button's trailing edge + 7           (81 on macOS 27)

  top row (32 pt buttons)      top padding    = centre line - 16
  compact row (28 pt buttons)  top padding    = centre line - 14
  hide-sidebar button x        = min(leading, width - 6 - 3 * 34 - 32)   (as today)
  compact below                width < leading + 137                     (218 on macOS 27)
  narrowest sidebar            max(164, zoom's trailing edge + 90)       (164 on macOS 27)
```

The gap after the zoom button is 7 pt, where Arc's is 3 (hide-sidebar at 77): the owner found Arc's too tight, so the hide-sidebar button and the compact row's threshold sit 4 pt further right than Arc's.

Just above the compact threshold the hide-sidebar button squeezes left, as Arc's does, by at most 3 pt, so it can meet the zoom button's edge but never overlap it. Before the window first shows, and if the buttons are hidden, the numbers keep macOS 27's values.

### D4. Verification

The positions are checked as PR #92 checked them: accessibility frames of the buttons (Arc reads 12/35/58, y 16) and 60 fps recordings of Cmd+S and the hover reveal, driven by XCUITest (CLAUDE.md, "Comparing with Arc and driving the UI"). The recordings also confirm that no frame shows the buttons at AppKit's default spot after a title change.

One automated test is enough: a glitch in the slide or the reveal shows the moment anyone uses the window. The runtime test covers what doesn't show at once: a macOS update moving the buttons, or the title-change drift coming back. On the hosted macOS 27 runner, it checks that the close button reads 12 and 16 from the sidebar's corner, that the top row is centred on it and starts after the zoom button, and that both hold after a page title change. The `ClairUI` unit tests for the placement maths are dropped, as they restate it.

Known gap: CI runs only macOS 27 (the `xcode-27` image), so a problem on macOS 15 or 26 shows only when someone uses Clair there.

## Risks / Trade-offs

- [Two of the private methods, `-_updateTitlebarContainerViewFrameIfNecessary` and `-_updateButtonPositions`, are ones Chromium doesn't use] → each is called only if the frame responds to it; without them the buttons still sit right after every title bar layout AppKit does on its own, and only the slide degrades.
- [The private methods change or disappear in a future macOS] → `+frameViewClassForStyleMask:` falls back to `super`'s when `NSThemeFrame` is missing, and the overrides only change numbers AppKit already asks for. Chromium's windows break the same way, so the fix will be visible upstream.
- [A 40 pt title bar takes clicks or drags meant for the sidebar's top row, or for the URL field, whose top is at y+46] → with a full-size content view and a transparent title bar, AppKit passes clicks in empty title bar areas to the content, as it does for Chromium's own taller title bar. Task 3.2 clicks the top-row buttons and the field's top edge to confirm it.
- [Laying out the title bar on every display-link step stutters] → it lays out three buttons, and task 1.3's recordings showed no stutter on macOS 27. If another macOS does stutter, D1's fallback can be turned on there.
- [macOS 15 or 26 draws the buttons at another place or spacing] → D3b's top row follows them, so they never overlap or misalign; adjusting the place to look like Arc there is a later per-version tweak of D1's constants.
- [Accessibility frames and drawn positions differ by a point, as they did in PR #92] → the inset is tuned against Arc's accessibility frames, measured the same way, and D3b reads the same frames, so both apps read 12/35/58 and 16 on macOS 27.

## Migration Plan

The change ships as one PR: the overlay, `ClairHost.h` and `ClairUI` together, since the contract changes on both sides. The engine key changes, so `engine.yml` builds the engine (incremental on the owner's Mac) before CI's engine check passes. Rollback is reverting the PR, which also needs that key's engine, already published from before.
