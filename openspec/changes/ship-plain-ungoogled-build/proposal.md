# Proposal

## Why

Clair is going to be a browser in the style of Arc, built on Chromium. Before any custom UI work, it needs a working build and release pipeline: a Clair-branded, signed, notarized, auto-updating build of unmodified ungoogled-chromium. Shipping that first proves the hardest operational risks (multi-hour Chromium builds on CI, signing and notarization, Sparkle updates) on a known-good codebase. It also fixes the identifiers that can never change once users have installed the app.

## What Changes

- Set up the Clair repository layout. `ungoogled-chromium` (core patch series, pruning, domain substitution) is pinned as a git submodule. Clair owns its macOS layer and does not depend on `ungoogled-chromium-macos` releases.
- Bring in macOS build patches adapted from `ungoogled-chromium-macos` (BSD-3).
- Add branding patches:
  - product name "Clair" and app icon (placeholder allowed)
  - bundle ID `dev.joshuapark.Clair`
  - data directory `~/Library/Application Support/Clair`
  - Clair-specific keychain item name
  - minimum macOS Sequoia 15.6
  - Apple Silicon (arm64) only
- Add Clair's own versioning:
  - starts at `0.1.0` and becomes `1.0.0` at the MVP
  - the Chromium version stays the internal engine version (user agent, extension compatibility) and is shown separately in the About window
- Integrate Sparkle 2 auto-updates, adapted from Helium's `sparkle2-integration` patches (GPLv3, with attribution kept). Updates use an EdDSA-signed appcast and delta updates.
- Publish updates the same way as Front Row (`itsjoshpark/FrontRow`):
  - The appcast is committed at `.sparkle/appcast.xml`, and `SUFeedURL` points to `https://github.com/itsjoshpark/Clair/raw/main/.sparkle/appcast.xml`.
  - DMGs are hosted on GitHub Releases.
  - A manually triggered release workflow takes a patch/minor/major choice. The build number is the commit count.
  - Release notes are written in `.sparkle/notes/next.md`.
  - The release commit is tagged first and pushed to `main` only after the release and its DMG exist.
- Extend that pattern where Clair differs:
  - Delta updates against the last few releases (the DMG is about 110 MB, and deltas are about 40 MB). CI downloads the previous releases' apps, runs `BinaryDelta`, and writes `<sparkle:deltas>` entries.
  - Signing, appcast and tag steps run in the final job of the chained build.
  - `sign_update` and `BinaryDelta` come from the Sparkle release tarball, not from Swift Package Manager (SPM) / DerivedData.
  - `sparkle:minimumSystemVersion` is 15.6.
  - Releasing automatically when ungoogled-chromium publishes a security update is deferred; releases start manually.
- Add a release pipeline on GitHub Actions (public repo). Pull request builds run on free GitHub-hosted arm64 runners with lighter build settings. Release builds run on the owner's self-hosted Mac (M1 Pro, 32 GB, building on an external SSD), because the hosted runners' 7 GB RAM is below Chromium's 8 GB minimum:
  - chained build jobs that stay under the 6-hour job limit
  - Developer ID signing, notarization, DMG creation
  - publishing to GitHub Releases
- Capture an Arc behaviour reference in `arc-reference/`, because Arc stops working on 2026-12-22. It holds the menu and shortcut dump, a re-runnable script, filtered UI strings for the MVP features, a look-and-behaviour reference with screenshots (`look-and-behaviour.md`), how Dia (Arc's successor) is built on Chromium (`dia-architecture.md`), and Clair's decided menu bar and shortcuts (`clair-menus.md`). Change 1 itself ships Chromium's stock menus.

**Out of scope for this change:** any Clair UI or feature work; removing the password manager or autofill; Widevine/DRM; sync; Homebrew cask; crash reporting.

## Capabilities

### New Capabilities
- `app-identity`: Clair's product identity and the identifiers that must stay stable. Covers name, bundle ID, data directory, keychain naming, version scheme, the About window showing the Clair and Chromium versions, and the supported platform (arm64, macOS 15.6+).
- `chromium-engine`: The engine baseline. Clair runs ungoogled-chromium's privacy-preserving defaults and tracks upstream ungoogled-chromium releases, including security updates, without waiting on third-party macOS packaging.
- `software-updates`: In-app updates through Sparkle 2, in the style of Arc. Clair checks its appcast and downloads updates silently in the background, verifies EdDSA signatures, applies delta updates with a fallback to the full update, and installs on quit. Updates appear in the Clair menu ("Check for Updates…", "Install Update and Relaunch"). There are no Sparkle windows and no update settings.
- `release-distribution`: How Clair builds reach users. Covers CI builds, Developer ID signing, notarization, DMG packaging, and GitHub Releases publication with version and Chromium-version metadata.

### Modified Capabilities
- None (no existing specs).

## Impact

- **Repository:**
  - new top-level layout: `ungoogled-chromium/` submodule, `patches/` series (ungoogled-macos-derived, helium-derived, clair), build and packaging scripts, `.github/workflows/`
- **Dependencies:**
  - ungoogled-chromium (BSD-3)
  - patches derived from ungoogled-chromium-macos (BSD-3) and Helium (GPLv3)
  - Sparkle 2 (MIT)
  - Xcode and the Metal toolchain
- **Accounts and secrets:**
  - Apple Developer Program membership (Developer ID certificate, notarization credentials) stored as GitHub Actions secrets
  - a Sparkle EdDSA private key (GitHub secret `SPARKLE_ED_PRIVATE_KEY`) that must be backed up; losing it strands every installed copy. The feed URL can be moved later by shipping an update with a new `SUFeedURL`, as long as the old URL keeps working during the move.
- **Infrastructure:**
  - GitHub Actions: free for public repos, 6-hour job limit, 10 GB cache
  - Large partial-build artifacts are passed between chained jobs. The artifact storage behaviour for public repos is not confirmed in GitHub's docs and must be checked in the first CI run.
- **Local development:** an Apple Silicon Mac with about 150 GB free; a clean build takes several hours.
- **Irreversible once shipped:** the bundle ID, data directory, keychain name, Sparkle public key, and the version scheme's ordering. The appcast URL can be moved only through a migration update.

## Open Questions

- **Actual free disk on `macos-latest` runners.** The docs list 14 GB; ungoogled's CI frees space by deleting preinstalled SDKs. Measure it in the first run.

## Roadmap Context (decided during exploration; not part of this change)

1. This change: a plain ungoogled build ships.
2. UX spike: a vibrancy sidebar with spring open/close, a two-finger swipe between Spaces, and a Cmd+T command bar. It also covers moving Chromium's toolbar into the sidebar: the URL display, back/forward/reload, permission chips, extension actions, the download indicator, and where their popups attach when the sidebar is hidden. It tests whether Views plus Objective-C++/Core Animation can feel as good as Arc.
3. MVP features:
   - vertical sidebar with folders
   - pinned tabs, and favorites stored per profile
   - Spaces many-to-one with profiles (one window per profile; switching profile swaps windows in place)
   - command bar built on Chromium's `AutocompleteController`
   - reset pinned tab to its URL
   - split view (2 panes for the MVP)
   - Peek (opens for links to other sites from pinned tabs and favorites, and on Shift+click)
   - built-in password manager and autofill removed, using Helium's patches as reference
   - URL bar only in the sidebar, with no top toolbar and no option to show one
   - no archive concept: closing tabs simply closes them, and history is the only record
   - menus and shortcuts as decided in `arc-reference/clair-menus.md`; Arc's shortcuts win where they conflict with Chrome's
   - an update-ready banner at the bottom of the sidebar, like Arc's, with an "Install and Relaunch" button, alongside the Clair menu item from change 1

Architecture: C++ Views plus WebUI, with Objective-C++ only where native macOS behaviour is needed. No Swift. No sync in the MVP; CloudKit may come later. Widevine is deferred until after the MVP.
