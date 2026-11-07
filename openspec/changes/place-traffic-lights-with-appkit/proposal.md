# Proposal

## Why

The native window's traffic lights belong to AppKit's title bar, but `ClairUI` moves them by setting their frames from outside. AppKit puts them back whenever it lays the title bar out again, as a new window title does, so PR #92 re-places them after every window update. That masks the problem rather than fixing it: they can show for a frame at AppKit's spot, the check runs after every event, and any layout path the hook misses brings the bug back. Chromium positions its own windows' traffic lights the supported way, through AppKit's title bar layout, and Clair should do the same.

## What Changes

- `ClairNativeWindow` gets its own title bar frame class, as Chromium's `BrowserNativeWidgetWindow` does: AppKit's layout places the close, minimise and zoom buttons where Clair asks, so nothing moves them back.
- `ClairHost.h` gains a small contract for the window controls' place and visibility, which `ClairUI` sets as the sidebar moves (shown, hiding, revealed over the page, page full screen).
- `ClairUI` drops `TrafficLights`' frame setting and its observers of button frame changes and window updates.
- The sidebar's top row is laid out from where the buttons actually land: centred on them vertically and starting after the zoom button, so the two line up on any supported macOS. Lining up matters more than matching Arc's exact place on versions other than macOS 27.
- Where the buttons can't follow the sidebar's motion, they hide while it moves and come back once it stops, and Clair logs that once per launch.
- On macOS 27 the visible behavior stays as it is today: the close button sits at Arc's x+12, y+16 with the other two at the system's spacing (35 and 58), they slide with the sidebar during Cmd+S and the hover reveal, and they hide with the sidebar and in page full screen. The one deliberate change is a 7 pt gap before the hide-sidebar button, where Arc has 3. What else changes is that the buttons no longer jump after a title change, a key change or a resize, even for a frame.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `browser-window`: adds requirements that the window controls keep their place in the sidebar through title, activation and size changes, that the top row is laid out from them, and that they follow the sidebar as it moves, or hide during the motion where they can't. The capability is introduced by `replace-browser-window`, which isn't archived yet, so this delta adds a requirement rather than modifying one; `replace-browser-window` archives first.

## Impact

- **Engine:** `overlay/chrome/browser/clair/window/clair_native_window.{h,mm}` and `native/ClairHost.h` change, so the engine key changes and `engine.yml` builds a new engine (incremental on the owner's Mac). The PR's patch check runs until that engine is published.
- **Native layer:** `native/ClairUI/BrowserRootView.swift` (`TrafficLights`), the top row in `SidebarView.swift` and the sidebar's width limits; `FakeBrowser` in `ClairUITests` gains the new contract.
- **Private API:** `+[NSWindow frameViewClassForStyleMask:]`, `NSThemeFrame`, `-_titlebarHeight` and `-_minXTitlebarWidgetInset`, which Chromium already ships, so the risk is the one Chromium carries; a future macOS without them falls back to AppKit's default positions, as Chromium's windows do. Moving the buttons as the sidebar slides also needs `-_updateTitlebarContainerViewFrameIfNecessary` and `-_updateButtonPositions`, which Chromium doesn't use; both are called only if present.
- **Runtime suite:** one test that the close button keeps its place and the top row lines up with it, before and after the page title changes. CI runs only macOS 27, so macOS 15 and 26 are best effort.
