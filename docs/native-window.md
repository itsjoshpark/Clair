# The native window

Clair's browser windows are native AppKit and SwiftUI, built by `ClairUI`, while Chromium keeps the browser behind them: tabs, navigation, sessions, profiles, extensions and its own dialogs. This page describes how the two halves meet, where each piece lives, and how to add a hook when a Chromium surface misbehaves in the native window. The full reasoning is in the `replace-browser-window` change's `design.md` (D1–D17), archived under `openspec/changes/archive/` once it ships.

## Architecture

```
Chromium (engine)                                   ClairUI (Swift)
──────────────────────────────────────────          ─────────────────────────────
Browser ── BrowserWindow ─▶ ClairBrowserWindow       BrowserWindowController
                              │  owns                  │  ClairWindow
                              ▼                        │
                           ClairNativeWindow (NSWindow) ◀── styled and filled by ClairUI
                              │
                           ClairChromiumBrowser ──── ClairBrowser ────▶ (calls in)
                              (Objective-C bridge)  ◀── ClairWindow ──── (pushes out)
```

- **Chromium keeps the browser (D1).** `ClairBrowserWindow` implements Chromium's `BrowserWindow` for normal browsers. Each of its methods is forwarded to `ClairUI`, answered from the `NSWindow`, handled by a helper in the overlay (location bar stub, find, full screen, modal dialog host, extensions container, status, docked DevTools), or belongs to a feature the native window doesn't have, in which case it does nothing and logs once ("Clair: … isn't available in the native window").
- **Every normal window is native while `ClairUI` runs (D2).** `browser_window_factory.cc` asks `clair::CreateNativeBrowserWindow` first. Pop-ups, app windows, Picture-in-Picture, undocked DevTools, the profile picker and the task manager stay Chromium's. Without `ClairUI.framework` (the bare engine in CI's smoke test) Chromium builds its own window. With the framework present but failing to load, Clair shows an alert and quits.
- **The contract is `native/ClairHost.h` (D3).** `ClairBrowser` is Chromium's side (tabs, commands, autocomplete sessions, downloads, extension actions), `ClairWindow` is `ClairUI`'s (callbacks for changes, the command bar, find, toasts, anchors for Chromium's bubbles). Chromium pushes immutable snapshots, coalesced to one per run-loop turn per tab; Swift never holds a C++ pointer. The header is an engine input: changing it changes the engine key and needs an engine build.
- **Closing goes through Chromium.** The close button calls `requestClose`, which runs Chromium's `beforeunload` flow; the `NSWindow` closes only when Chromium calls `BrowserWindow::Close`.

## Where each piece lives

| Piece | File |
|---|---|
| `BrowserWindow` and its helpers | `overlay/chrome/browser/clair/window/clair_browser_window.{h,mm}` |
| The `NSWindow`, key equivalents, menu validation | `overlay/chrome/browser/clair/window/clair_native_window.{h,mm}` |
| The `ClairBrowser` bridge and tab snapshots | `overlay/chrome/browser/clair/window/clair_browser_bridge.{h,mm}` |
| Command bar suggestions (Chromium's autocomplete, no bookmarks) | `overlay/chrome/browser/clair/window/clair_autocomplete.{h,mm}` |
| Extension actions and popups | `overlay/chrome/browser/clair/window/clair_extensions.{h,mm}` |
| Downloads | `overlay/chrome/browser/clair/window/clair_downloads.{h,mm}` |
| The functions hooks call, menus, password and autofill prefs | `overlay/chrome/browser/clair/window/clair_window_hooks.{h,mm}` |
| Tab-modal dialog placement over the card | `overlay/components/constrained_window/clair_native_host_mac.{h,mm}` |
| Loading `ClairUI` and creating windows | `overlay/chrome/browser/clair/clair_native_layer.{h,mm}` |
| The hooks into Chromium's own files | `patches/clair/native-window-hook.patch` |
| Window, layout, card and overlays | `native/ClairUI/BrowserWindowController.swift`, `BrowserRootView.swift`, `PageCardView.swift`, `WindowLayout.swift`, `OverlayViews.swift` |
| Sidebar, tab list, URL field, extensions and downloads | `native/ClairUI/SidebarView.swift`, `TabListLogic.swift`, `URLDisplay.swift`, `AnchorResolver.swift` |
| Command bar | `native/ClairUI/CommandBarModel.swift`, `OverlayViews.swift` |
| Unit tests against a fake Chromium | `native/ClairUITests/` (`FakeBrowser.swift`) |
| Runtime tests on a packaged Clair | `tests/runtime/ClairRuntimeTests/NativeWindowTests.swift` |

## Working on it

- **`ClairUI` only:** `scripts/run-local.sh` packages the checkout's `ClairUI` with the published engine and opens it with a throwaway profile (see `docs/building.md`). Unit tests use `FakeBrowser`, so most window logic can be tested without an engine.
- **Overlay or patch changes:** they change the engine key, so they need an engine build (`gh workflow run engine.yml -f ref=<branch>`). Before pushing, read the Chromium code you're calling in the runner's workspace (read only), and keep the overlay compiling by checking it against that tree's headers.

## Adding a hook

Chromium code that assumes a Views `BrowserView` crashes or does nothing for a native window. When a surface fails:

1. Find the call site in Chromium's source and the smallest place to branch: usually where it looks up the `BrowserView`, a Views widget or a `BrowserWindowFeatures` controller that a native window doesn't create.
2. Put the behaviour in the overlay: a function in `clair_window_hooks.{h,mm}` (or a new overlay file), which does nothing for Chromium's own windows (`clair::IsNativeWindow(browser)` or `clair::IsInNativeWindow(view)`), so the bare engine behaves as Chromium.
3. Add a hunk to `patches/clair/native-window-hook.patch` that calls it, made against `build/base` in the runner's workspace (after ungoogled-chromium's patches, before Clair's), with any earlier Clair patch to the same file applied first. Clair's series applies with no fuzz.
4. Explain the hunk in the patch header, with what failed without it, and add a row to D13's table in the design.
5. Add any new overlay source to the `BUILD.gn` hunk for its directory, then build the engine and check the surface on the packaged app.
