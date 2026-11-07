# Proposal

## Why

The native window's traffic lights belong to AppKit's title bar, but `ClairUI` moves them by setting their frames from outside. AppKit puts them back whenever it lays the title bar out again, as a new window title does, so PR #92 re-places them after every window update. That masks the problem rather than fixing it: they can show for a frame at AppKit's spot, the check runs after every event, and any layout path the hook misses brings the bug back. Chromium positions its own windows' traffic lights the supported way, through AppKit's title bar layout, and Clair should do the same.

## What Changes

- `ClairNativeWindow` gets its own title bar frame class, as Chromium's `BrowserNativeWidgetWindow` does: AppKit's layout places the close, minimise and zoom buttons where Clair asks, so nothing moves them back.
- `ClairHost.h` gains a small contract for the window controls' place and visibility, which `ClairUI` sets as the sidebar moves (shown, hiding, revealed over the page, page full screen).
- `ClairUI` drops `TrafficLights`' frame setting and its observers of button frame changes and window updates.
- The visible behavior stays as it is today: the buttons sit at Arc's x+12/35/58, y+16, slide with the sidebar during Cmd+S and the hover reveal, and hide with the sidebar and in page full screen. What changes is that they no longer jump after a title change, a key change or a resize, even for a frame.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `browser-window`: adds a requirement that the window controls keep their place in the sidebar through title, activation and size changes, and follow the sidebar as it moves. The capability is introduced by `replace-browser-window`, which isn't archived yet, so this delta adds a requirement rather than modifying one; `replace-browser-window` archives first.

## Impact

- **Engine:** `overlay/chrome/browser/clair/window/clair_native_window.{h,mm}` and `native/ClairHost.h` change, so the engine key changes and `engine.yml` builds a new engine (incremental on the owner's Mac). The PR's patch check runs until that engine is published.
- **Native layer:** `native/ClairUI/BrowserRootView.swift` (`TrafficLights`) and its tests; `FakeBrowser` in `ClairUITests` gains the new contract.
- **Private API:** `+[NSWindow frameViewClassForStyleMask:]`, `NSThemeFrame`, `-_titlebarHeight` and `-_minXTitlebarWidgetInset`. Chromium already ships all four, so the risk is the one Chromium carries; a future macOS without them falls back to AppKit's default positions, as Chromium's windows do.
- **Runtime suite:** a test that the buttons stay at their place after the page title changes.
