# Proposal

## Why

The downloads button's progress ring added up only its own window's profile's running downloads, so it disagreed with the Dock icon: a paused download, an incognito download, or one in another profile showed on the Dock but not in the sidebar, or the other way round. One number in both places is what people expect. Recorded after the fact: the work shipped in PR #111.

## What Changes

- **The ring shows the Dock's progress:** Chromium's `DownloadStatusUpdater::GetProgress()`, the value the Dock icon draws, in every window.

| | Before | Now (as the Dock) |
|---|---|---|
| Downloads counted | the window's profile | every profile, incognito and guest included |
| Paused downloads | left out | counted |
| Any download of unknown size | ignored | no ring |

- **Every window hears every profile's downloads,** including a profile with no window, and only when the progress changes: no polling.
- **The ring is drawn by the symbol** where macOS allows it (Variable Draw, macOS 26 and later), with an accent ring over the symbol on macOS 15.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `sidebar`: adds "Download progress".

## Impact

- **Engine:** `overlay/chrome/browser/clair/window/clair_downloads.{h,mm}` gains an app-wide watcher of every loaded profile's download manager. `native/ClairHost.h` gains `ClairDownloadProgress`, the browser's `downloadProgress`, `downloadsDidChange(_:progress:)` and `downloadProgressDidChange(_:)`. The engine key changes (`dffbe49fb9acf762`); no Chromium patch.
- **Native layer:** `BrowserWindowModel` keeps the app-wide progress and ignores unchanged values; `DownloadsButton` draws it.
- **Tests:** unit tests for the ring's rules and for skipping unchanged progress; the runtime `DownloadsTests` cover the button's progress.
