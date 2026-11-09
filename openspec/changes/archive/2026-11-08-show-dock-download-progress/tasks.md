# Tasks

Recorded after the fact: the work shipped in PR #111. "By hand" means a check through `scripts/run-local.sh`; "quality.yml" means a run dispatched on the branch (`gh workflow run quality.yml --ref refactor/shared-icon-button`).

## 1. Contract and engine

- [x] 1.1 Add `ClairDownloadProgress`, the browser's `downloadProgress`, `downloadsDidChange(_:progress:)` and `downloadProgressDidChange(_:)` to `native/ClairHost.h`, and implement them in `FakeBrowser`. Verified: `ClairUI` builds and its unit tests pass.
- [x] 1.2 Add `ClairDownloads::Progress()` and the app-wide `ProgressWatcher` in `clair_downloads.mm`. Verified: engine runs 42538869855 and, after the incognito fix, 42544341171 built and published the engine.

## 2. Native layer

- [x] 2.1 Show the ring from the app-wide progress, as the Dock does, and skip unchanged values. Verified: unit tests `DownloadProgressTests` pass (no ring with none running or any size unknown, the fraction otherwise, no update for an unchanged value).
- [x] 2.2 Draw the ring with Variable Draw on macOS 26 and later, and over the symbol on macOS 15. Verified: rendered offline on macOS 27 in both modes; the ring sits on the symbol's circle.

## 3. Verification

- [x] 3.1 `DownloadsTests` pass in quality.yml against the new engine: an incognito window shows the regular window's download progress (another profile, as on the Dock), then the regular window's progress and unseen mark. Verified: quality.yml run 42546108466 passed. Its first run found a crash on opening any incognito window (the watcher recursed into the incognito profile's own list); fixed, and the engine rebuilt (run 42544341171).
- [x] 3.2 By hand: a download in one profile shows the same progress in another profile's window and on the Dock, and clears when it ends; a paused download leaves Clair idle. Verified: signed off by the owner (2026-11-08).
