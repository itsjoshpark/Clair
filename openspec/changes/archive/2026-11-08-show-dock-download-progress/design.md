# Design

## Context

`ClairDownloads` (one per window) observes its own profile's download manager and sends the window a snapshot of this session's downloads; `BrowserWindowModel.downloadProgress` summed their bytes. The Dock's progress comes from Chromium's `DownloadStatusUpdater`, which `g_browser_process->download_status_updater()` exposes. Its `GetProgress()` walks every profile's download manager (each registers in `DownloadCoreServiceImpl`), counts every in-progress item, paused ones included, adds up received and total bytes for those with a known size, and reports the result as uncertain when any size is unknown. The Dock then shows a badge and no ring. It has no observer of its own.

## Decisions

### D1. Chromium's number, through the contract

`ClairDownloads::Progress()` calls `GetProgress()` and fills a `ClairDownloadProgress` (`count`, `isIndeterminate`, `fraction`). The model shows a ring only while `count > 0` and the progress is certain, clamped to 0–1, as the Dock does. No Chromium patch: the updater and its header are public to the `ui` target that builds the overlay.

### D2. One app-wide watcher, no polling

A singleton `ProgressWatcher` holds an `AllDownloadItemNotifier` for every loaded profile's download manager: the profiles loaded when it starts, later ones from `ProfileManagerObserver::OnProfileAdded`, off-the-record ones from `ProfileObserver::OnOffTheRecordProfileCreated`, and each window's own profile (guest and incognito don't reach `OnProfileAdded`). On any download created, updated or removed it posts one flush per run-loop turn; the flush reads `Progress()` and, only when it differs from the last value sent, calls every window's `downloadProgressDidChange(_:)`. A profile's notifier goes with `OnProfileWillBeDestroyed`.

- Alternative (built first): every window re-flushed its whole snapshot every 200 ms while any download ran. Rejected after review: it never stopped while a download was paused, rebuilt every window's list five times a second, and missed downloads that started in a profile with no window.

### D3. The model skips unchanged values

`BrowserWindowModel.setDownloadProgress(_:)` assigns only when a field changed, so an unchanged value doesn't redraw the sidebar. Snapshots (`downloadsDidChange(_:progress:)`) still carry the current progress, so a new window starts right.

### D4. Drawing

`arrow.down.circle` responds to a variable value only in Variable Draw mode (`symbolVariableValueMode(.draw)`), which needs macOS 26: there the symbol draws its own ring in palette colours, grey arrow and accent ring. On macOS 15 the symbol has no variable layers, so an accent `Circle().trim` is drawn over its ring.

## Risks / Trade-offs

- **The ring is app-wide**, so an incognito download shows in regular windows and the reverse, as on the Dock, while the downloads list shows only the window's own profile's session.
- **A download that starts in a profile no window or loaded-profile list has reached** wouldn't be seen; every way Chromium loads a profile goes through `OnProfileAdded` or a window.
