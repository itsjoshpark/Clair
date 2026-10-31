# Proposal

## Why

Clair is going to be a browser in the style of Arc, built on Chromium. Before any custom UI work, it needs a working build and release pipeline: a Clair-branded, signed, notarized, auto-updating build of ungoogled-chromium. Shipping that first proves the hardest operational risks (multi-hour Chromium builds, signing and notarization, Sparkle updates) on a known-good codebase. It also fixes the identifiers that can never change once users have installed the app.

The pipeline has to keep work fast. A full Chromium build takes 25–30 hours on GitHub's hosted runners, so building Chromium for every pull request makes each change wait a day, and every push restarts that wait. Following Crest (`pauljoda/Crest`), Clair therefore splits the work in two:

- the **engine**: the patched Chromium, built only when its inputs change, on the owner's Mac, and published as a prebuilt artifact
- the **app**: Clair's native code, packaging, signing and updates, built in minutes on hosted runners against the prebuilt engine

This change also adds a minimal native layer: a Swift framework that Chromium loads at start-up. It runs Sparkle and the update menu, so the fast app build is used from the first release, and so the updater needs no Chromium patches.

## What Changes

- Set up the Clair repository layout. `ungoogled-chromium` (core patch series, pruning, domain substitution) is pinned as a git submodule. Clair owns its macOS layer and does not depend on `ungoogled-chromium-macos` releases.
- Bring in macOS build patches adapted from `ungoogled-chromium-macos` (BSD-3).
- Keep Clair's own changes to Chromium to hooks and identity. Behaviour Clair adds goes into the native layer or into new source files (an overlay), not into patches of Chromium's existing code, wherever that is possible.
- Add branding patches, all compiled into the engine:
  - product name "Clair" and the app icon and in-app logos (from the `design-app-icon` change)
  - bundle ID `dev.joshuapark.Clair`
  - data directory `~/Library/Application Support/Clair`
  - Clair-specific keychain item name
  - minimum macOS Sequoia 15.6
  - Apple Silicon (arm64) only
- Add Clair's own versioning:
  - starts at `0.1.0` and becomes `1.0.0` at the MVP
  - the Chromium version stays the internal engine version (user agent, extension compatibility) and is shown separately in the About window
  - the Clair version and build number are written at packaging time, so a release does not need a new engine
- Add the native layer:
  - `ClairUI.framework`, written in Swift and built with Xcode, embedded in `Clair.app` at packaging time
  - one Chromium hook that loads it at start-up, and a small Objective-C header (`ClairHost.h`) through which it calls back into Chromium
  - the window, tab strip, toolbar and menus stay Chromium's own in this change
- Integrate Sparkle 2 auto-updates in the native layer. `Sparkle.framework` comes from the pinned Sparkle release and is embedded at packaging time. The native layer adds one update item to the Clair menu with AppKit, "Check for Updates…", which reads "Update Available…" while a downloaded update is waiting, as in Arc. A waiting update installs on quit, or on its own once the user has been idle for 30 minutes. Updates use an EdDSA-signed appcast and delta updates.
- Build the engine as a prebuilt artifact:
  - an **engine key** is a hash over every engine input: the ungoogled-chromium pin, `downloads.ini`, the GN flags, `patches/`, the overlay, `ClairHost.h`, the compiled-in branding resources, and the scripts that prepare and build Chromium
  - the owner starts an engine build by hand, on any of the owner's branches. It runs on the owner's self-hosted Mac (M1 Pro, 32 GB, label `clair-release`), which keeps its build directory on its internal disk between runs so a patch fix rebuilds only what it touched
  - the result is published as a GitHub prerelease, `chromium-engine-<key>`, and is reused by every app build, quality check and release with the same key
- Split the checks:
  - a **merge gate** on every pull request that finishes in minutes: script tests, shellcheck, actionlint, and the native layer's build and unit tests
  - a **patch check** on pull requests that change the engine key: fetch the Chromium source and apply every patch on a hosted runner (about 40 minutes), with no compile. These pull requests also need a published engine for their key before they merge
  - **quality checks** after merge: package the app against the prebuilt engine and run automated runtime tests. A failure is reported so an agent can be sent to fix it. No release ships unless the quality checks for its commit have passed
- Publish updates the same way as Front Row (`itsjoshpark/FrontRow`):
  - The appcast is committed at `.sparkle/appcast.xml`, and `SUFeedURL` points to `https://github.com/itsjoshpark/Clair/raw/main/.sparkle/appcast.xml`.
  - DMGs are hosted on GitHub Releases.
  - A manually triggered release workflow takes a patch/minor/major choice. The build number is the commit count.
  - Release notes are written in `.sparkle/notes/next.md`.
  - The release commit is tagged first and pushed to `main` only after the release and its DMG exist.
- Extend that pattern where Clair differs:
  - Delta updates against the last few releases (the DMG is about 110 MB, and deltas are about 40 MB). CI downloads the previous releases' apps, runs `BinaryDelta`, and writes `<sparkle:deltas>` entries.
  - A release builds its engine first if none is published for its key, then runs the quality checks, then packages and publishes.
  - `sign_update`, `BinaryDelta` and `Sparkle.framework` come from the Sparkle release tarball, not from Swift Package Manager (SPM) / DerivedData.
  - `sparkle:minimumSystemVersion` is 15.6.
  - Releasing automatically when ungoogled-chromium publishes a security update is deferred; releases start manually.
- Add a release pipeline on GitHub Actions (public repo). Releases run on the owner's self-hosted Mac:
  - Developer ID signing, notarization, DMG creation
  - publishing to GitHub Releases
- Capture an Arc behaviour reference in `arc-reference/`, because Arc stops working on 2026-12-22. It holds the menu and shortcut dump, a re-runnable script, filtered UI strings for the MVP features, a look-and-behaviour reference with screenshots (`look-and-behaviour.md`), how Dia (Arc's successor) is built on Chromium (`dia-architecture.md`), and Clair's decided menu bar and shortcuts (`clair-menus.md`). Change 1 itself ships Chromium's stock menus.

**Out of scope for this change:** any Clair browser UI or feature work beyond the update menu; replacing Chromium's window; removing the password manager or autofill; Widevine/DRM; sync; Homebrew cask; crash reporting.

## Capabilities

### New Capabilities
- `app-identity`: Clair's product identity and the identifiers that must stay stable. Covers name, bundle ID, data directory, keychain naming, version scheme, the About window showing the Clair and Chromium versions, and the supported platform (arm64, macOS 15.6+).
- `chromium-engine`: The engine baseline. Clair runs ungoogled-chromium's privacy-preserving defaults and tracks upstream ungoogled-chromium releases, including security updates, without waiting on third-party macOS packaging.
- `native-layer`: Clair's Swift framework inside Chromium. Covers loading it at start-up, the `ClairHost.h` contract it uses to reach Chromium, and building it without a Chromium checkout.
- `software-updates`: In-app updates through Sparkle 2, in the style of Arc. Clair checks its appcast and downloads updates silently in the background, verifies EdDSA signatures, applies delta updates with a fallback to the full update, and installs on quit or while the user is idle. Updates appear in the Clair menu ("Check for Updates…", which becomes "Update Available…" with "Restart and Update"). There are no Sparkle windows and no update settings.
- `build-pipeline`: How Clair is built and checked. Covers the engine key and prebuilt engines, where builds run, the merge gate, the patch check, the quality checks, and the rule that releases need passing quality checks.
- `release-distribution`: How Clair builds reach users. Covers Developer ID signing, notarization, DMG packaging, and GitHub Releases publication with version and Chromium-version metadata.

### Modified Capabilities
- None (no existing specs).

## Impact

- **Repository:**
  - new top-level layout: `ungoogled-chromium/` submodule, `patches/` series (ungoogled-macos-derived, helium-derived, clair), `overlay/` (new Chromium source files), `native/` (the Swift framework and `ClairHost.h`), build and packaging scripts, `.github/workflows/`
- **Dependencies:**
  - ungoogled-chromium (BSD-3)
  - patches derived from ungoogled-chromium-macos (BSD-3) and Helium (GPLv3)
  - Sparkle 2 (MIT)
  - Xcode 27.2 and the Metal toolchain on every machine and runner, with the native layer in Xcode's JSON project format
- **Accounts and secrets:**
  - Apple Developer Program membership (Developer ID certificate, notarization credentials) stored as GitHub Actions secrets
  - a Sparkle EdDSA private key (GitHub secret `SPARKLE_ED_PRIVATE_KEY`) that must be backed up; losing it strands every installed copy. The feed URL can be moved later by shipping an update with a new `SUFeedURL`, as long as the old URL keeps working during the move.
- **Infrastructure:**
  - GitHub Actions: free for public repos, 6-hour job limit, 10 GB cache
  - the owner's self-hosted Mac runs engine builds and releases. It must be online for either (the owner starts the runner by hand), and holds a persistent engine workspace on its internal disk
  - engine artifacts are published as GitHub prereleases, one per engine key
- **Local development:** the development machine never fetches or builds Chromium. The native layer builds locally with Xcode against `ClairHost.h`, without a Chromium checkout.
- **Irreversible once shipped:** the bundle ID, data directory, keychain name, Sparkle public key, and the version scheme's ordering. The appcast URL can be moved only through a migration update.

## Open Questions

- **Engine build time on the owner's Mac**, for a full build and for a typical patch fix. Measured on the first engine builds.

## Roadmap Context (decided during exploration; not part of this change)

1. This change: an ungoogled build with Clair's identity and native update layer ships.
2. UX spike: a vibrancy sidebar with spring open/close, a two-finger swipe between Spaces, and a Cmd+T command bar, built in Crest's style: Chromium's browser window is replaced by a native AppKit/SwiftUI window that hosts the page views. The spike also covers moving Chromium's toolbar into the sidebar: the URL display, back/forward/reload, permission chips, extension actions, the download indicator, and where their popups attach when the sidebar is hidden. It measures how native it feels against Arc, the edit-to-run time, and which Chromium features need native replacements.
3. MVP features:
   - vertical sidebar with folders
   - pinned tabs, and favorites stored per profile
   - Spaces many-to-one with profiles (one window per profile; switching profile swaps windows in place)
   - command bar built on Chromium's `AutocompleteController`
   - reset pinned tab to its URL
   - split view (2 panes for the MVP)
   - Peek (opens for links to other sites from pinned tabs and favorites, and on Shift+click)
   - built-in password manager and autofill removed, through Chromium's own settings and policies where possible and Helium's patches as reference otherwise
   - URL bar only in the sidebar, with no top toolbar and no option to show one
   - no archive concept: closing tabs simply closes them, and history is the only record
   - menus and shortcuts as decided in `arc-reference/clair-menus.md`; Arc's shortcuts win where they conflict with Chrome's
   - update banners at the bottom of the sidebar, like Arc's, alongside the Clair menu item from change 1: a "New Clair Version Available" pill that grows on hover into a card with a "Restart and Update" button, and after an update, "Update Complete!" with "See What's New"

Architecture: a native AppKit/SwiftUI interface in Crest's style. Chromium's own browser window is replaced, and its other UI (permission prompts, extension popups, DevTools, file pickers, `chrome://` pages) stays until a native version replaces it. WebUI is used only for Chromium's internal pages. Chrome features that the native window doesn't host, such as autofill, EyeDropper, caret browsing and Chrome Labs, are not supported. Chrome profiles and incognito stay available underneath, through Spaces and Clair's own incognito window. No sync in the MVP; CloudKit may come later. Widevine is deferred until after the MVP.
