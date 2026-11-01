# Design

## Context

The motivation is in `proposal.md` (Why) and the required behaviour is in `specs/`. This section covers only what shapes the approach.

The first pull request (#1) adds the repository scaffolding, `build.sh`, the release scripts and a chained 20-phase Chromium build on hosted runners. This revision keeps the scaffolding and scripts, and replaces the hosted compile chain with prebuilt engines (see Migration Plan).

Four existing projects already solve most of this change, and Clair copies from them rather than depending on them:

- **ungoogled-chromium-macos** (BSD-3):
  - `build.sh`: download, then prune, patch and domain-substitute, then write `args.gn`, then build
  - `flags.macos.gn`
  - about 27 macOS build-fix patches, including `set-bundle-identifier.patch`
  - `sign_and_package_app.sh`: signs each helper with its own identifier and entitlements, then builds the DMG with `pkg-dmg`
- **Helium / helium-macos** (GPLv3):
  - `change-chromium-branding.patch` (the `BRANDING` file)
  - `change-product-dir-name.patch` (`chrome_paths_mac.mm`)
  - `change-keychain-name.patch` (`keychain_password_mac.mm`)
  - `add-helium-versioning.patch`: a separate product version alongside the Chromium version (`version_info`, `tweak_info_plist.py`, the About and Version pages)
  - `utils/name_substitution.py`: replaces "Chromium" in user-facing strings
  - a Sparkle 2 integration built into Chromium (ReBel's glue plus Helium's `updater/` patches). Clair does not take it: Sparkle lives in the native layer instead (D4). Helium's patches remain a reference for how Chromium's relaunch and version code interact with Sparkle.
- **Crest** (`pauljoda/Crest`, MPL-2.0), a SwiftUI browser built on ungoogled-chromium-macos:
  - a native host: `native-host.patch` swaps Chromium's browser window for a native one when a switch is present, and an overlay of new files under `chrome/browser/ui/crest/` connects Chromium to a Swift framework through one header, `CrestChromiumHost.h`
  - prebuilt engines: `chromium_engine.py` hashes every engine input into a key, the self-hosted Mac builds and publishes `chromium-engine-<key>` releases, and every other job downloads the engine for its key
  - pull request checks that build the Swift framework against the header, with no Chromium build
- **Front Row** (`itsjoshpark/FrontRow`) provides the release mechanics:
  - `.sparkle/appcast.xml` committed on `main`
  - `.sparkle/notes/next.md` and `TEMPLATE.md`
  - `scripts/append-appcast-item.sh`, which has a test
  - `release.yml`, triggered manually with patch/minor/major and a dry-run option. It validates the build number and the notes, and uses the commit count as the build number. The release commit is tagged first and pushed to `main` last.

Constraints:

- **Hosted runner:** Clair's macOS jobs use GitHub's `xcode-27` image (a public preview: macOS 27 with Xcode 27). A standard hosted Mac has 3 cores and 7 GB RAM, below Chromium's 8 GB minimum. Measured on PR #1's `macos-26` runs: about 147 GB free after cleanup, a 38-minute fetch and patch job, and a 17.4 GB patched source tree (6.0 GB with zstd). The job limit is 6 hours.
- **Owner's Mac:** an M1 Pro with 32 GB RAM, used as the `clair-release` self-hosted runner. The runner's work directory and the persistent engine workspace are on its internal disk, which it shares with macOS and the owner's files. The owner starts the runner by hand, so it is online only while the owner runs it.
- **Toolchain:** Xcode 27 everywhere: hosted jobs, the owner's Mac and the development machine. The native layer's project uses Xcode 27.2's JSON format (`project.xcproj`), which Xcode 26 can't open. Chromium may still need an older macOS SDK under Xcode 27: Crest builds with Xcode 27 and the macOS 26.5 SDK, because Chromium's pinned LLD can't read the Xcode 27 SDK's `libSystem.tbd`.
- **Engine:** ungoogled-chromium removes Web Store URLs (`disable-webstore-urls.patch`). Extensions are installed through the `extension-mime-request-handling` flag.

## Goals / Non-Goals

**Goals:**
- One repository that builds Clair from a pinned ungoogled-chromium tag, with the same scripts on every machine.
- Leave ungoogled-chromium alone as much as possible. Patches are limited to build fixes, identity, versioning and the one native-layer hook. Anything else Clair adds lives in the native layer or in overlay files.
- A pull request that doesn't change the engine is checked in minutes. A broken engine build can be fixed and rebuilt quickly.
- Automated runtime tests that catch regressions in the packaged app.
- A release process that is safe to run for every ungoogled-chromium security tag with a single changed line.

**Non-Goals:**
- A good Chrome Web Store install experience. ungoogled-chromium's behaviour stays as it is, and the MVP will revisit it.
- Automatically starting a release when ungoogled-chromium publishes a tag.
- Building Chromium on hosted runners, or with `sccache` or remote build execution.
- Replacing Chromium's browser window. That is the UX spike's job.

## Decisions

### D1. Repository layout: ungoogled-chromium submodule, plus a Clair-owned macOS layer

```
Clair/
  ungoogled-chromium/          git submodule, pinned to a tag
  patches/
    series                     Clair's macOS-layer series, in apply order
    ungoogled-chromium-macos/  copied from ungoogled-chromium-macos (BSD-3), credited
    helium/                    copied or adapted from Helium (GPLv3); original headers kept
    clair/                     Clair-only patches (identity, versioning, the native-layer hook)
  overlay/                     new Chromium source files, at their paths in the Chromium tree
  native/
    ClairHost.h                the contract between Chromium and the native layer
    module.modulemap           ClairHost.h as the Swift module ClairHost
    ClairUI.xcodeproj/         Xcode project in the JSON format (project.xcproj): ClairUI.framework and its tests
    ClairUI/                   Swift sources
    ClairUITests/              unit tests that run without Chromium
  utils/                       name_substitution.py, version tools (from Helium, GPLv3)
  resources/                   icon and logo sources (icon/, from design-app-icon), DMG background and layout
  entitlements/                app and helper entitlements (from ungoogled-macos)
  downloads.ini                Chromium source tarball, with sha512
  flags.macos.gn               ungoogled-macos flags + Clair flags (arm64)
  version.txt                  Clair version, e.g. 0.1.0 (changed only by release commits)
  build.sh                     engine build entry point (based on ungoogled-macos)
  package.sh                   app packaging: engine + ClairUI + Sparkle, plist, signing, DMG
  scripts/                     engine-key.sh, append-appcast-item.sh, render-notes.sh, verify-app.sh, … (each + test)
  tests/runtime/               the quality-check suite (D12)
  .sparkle/                    appcast.xml, notes/{TEMPLATE.md,next.md,README.md,<version>.md}
  .github/workflows/           ci.yml, engine.yml, quality.yml, release.yml
  LICENSE, LICENSE.ungoogled_chromium, CREDITS.md
```

Chromium starts the native layer through `ClairHost.h`: it loads `ClairUI.framework`, takes the bundle's principal class (`NSPrincipalClass`, `ClairUIMain`), checks that it conforms to `ClairUIEntryPoint`, and calls `+startWithHost:` with its `ClairHost` implementation. The host reports a silent relaunch's blockers as a set of reasons rather than a yes or no, so `ClairUI` can log why an idle install waited. The hook is one call in `ChromeBrowserMainPartsMac::PreCreateThreads`, right after `BuildMainMenu` (`patches/clair/native-layer-hook.patch`, which also lists the sources in `chrome/browser/BUILD.gn`). The loader and the host live in `overlay/chrome/browser/clair/clair_native_layer.{h,mm}`. `prepare` copies `ClairHost.h` next to them and writes the ungoogled-chromium version into `ungoogled_version.h` (`scripts/install-native-contract.sh`), since Chromium compiles no ungoogled version of its own. A missing or broken framework is logged, and the browser carries on without it.

`build.sh` applies ungoogled-chromium's own series first, then `patches/series`, using ungoogled's `utils/patches.py`, then copies `overlay/` into the source tree. `overlay/` holds only new files. A change to an existing Chromium file is a patch, so every edit to upstream code is visible in `patches/`.

**Alternatives considered:**
- Forking `ungoogled-chromium-macos`: rejected. Clair would inherit its release timing and x86_64 support, and every Clair change would conflict with theirs.
- Depending on Helium as a submodule: rejected. Clair should not depend on Helium's future.
- `git subtree`: rejected, because it makes the pinned engine tag harder to see and to bump.
- XcodeGen (Crest's choice) or a Swift package: rejected. Xcode 27.2's JSON project format is already diff-friendly and easy for agents to edit, without an extra tool.

### D2. Branding through Chromium's `BRANDING` file, plus name substitution

- `patches/clair/branding.patch` sets these in `chrome/app/theme/chromium/BRANDING`:
  - `PRODUCT_FULLNAME` / `PRODUCT_SHORTNAME` = Clair
  - `MAC_BUNDLE_ID` = `dev.joshuapark.Clair`
  - `MAC_TEAM_ID`
  - `COMPANY_*` and `COPYRIGHT`

  This produces `Clair.app`, `Clair Framework.framework` and `Clair Helper*.app`, with helper IDs derived from the bundle ID. The patch also extends ungoogled's `tweak_info_plist.py` change so the bundle ID is recognised.
- The Chromium-branded strings in `chromium_strings.grd` and related files are replaced at build time by Helium's `name_substitution.py`, rather than by hand-written string patches. Substitution keeps up with upstream string changes; patches would conflict on every Chromium version.
- The data directory and keychain service come from Helium's two small patches with "Clair" swapped in, giving `~/Library/Application Support/Clair` and "Clair Safe Storage".
- The app icon and the in-app logos come from the `design-app-icon` change. They are compiled into the engine like the rest of the branding. The icon is final, so this costs no extra engine builds.
- During `prepare`, `scripts/replace-icon-resources.sh` puts them into the Chromium tree. `scripts/compile-icon.sh` compiles `resources/icon/AppIcon.icon` with `actool` into `Assets.car` and `app.icns`, which replace Chromium's files in `chrome/app/theme/chromium/mac/`. Every entry in `resources/icon/product-logos.txt` is then copied over its Chromium file, as Helium's resource list does. Nothing compiled is committed.

### D3. Separate Clair version, written at packaging time

- The Clair version and build number are **not** engine inputs, for two reasons:
  - The build number is the commit count, so it changes on every commit. Compiled in, it would change the engine key on every commit, and no prebuilt engine would ever be reused.
  - The release commit, which bumps `version.txt`, is made by the release itself. A compiled-in version would mean the shipped engine is built after the quality checks, from a commit nothing tested.
- `package.sh` writes them into `Clair.app/Contents/Info.plist`:
  - `CFBundleShortVersionString` = `version.txt`
  - `CFBundleVersion` = build number
- An adapted `add-helium-versioning.patch` makes the About page and `chrome://version` read the Clair version and build number from the main bundle's `Info.plist` at run time, instead of from compile-time constants. They show them alongside the compiled-in Chromium version and ungoogled-chromium revision.
- Everything that websites or extensions see (user agent, client hints, `minimum_chrome_version`) still uses the Chromium version.
- **Build number** = `git rev-list --count` of the release commit, as in Front Row. It is never stored. A build from the release tag reproduces the same number. Builds that aren't releases use the count of `HEAD`.
- Chromium may read the outer bundle's `CFBundleShortVersionString` elsewhere, for example when it locates its versioned framework directory, for app shims, or in `UpgradeDetector`. The builder finds every such read, using Helium's versioning and Sparkle patches as a map, and either confirms it is safe or patches it to use the Chromium version.

**Alternatives considered:**
- Passing the version to GN, as Helium does: rejected, because it makes the version an engine input.
- Setting `CFBundleShortVersionString` to the Chromium version, as Chromium does: rejected, because the spec requires the Clair version scheme, and Sparkle's display version must be Clair's.

### D4. Sparkle 2 in the native layer, headless; updates appear in the Clair menu

- `Sparkle.framework` 2.10.0 comes from the Sparkle release tarball, checked against its sha512: the same tarball that supplies `sign_update`, `BinaryDelta` and `generate_keys`. `package.sh` embeds it in `Clair.app/Contents/Frameworks`. Sparkle is not part of the engine.
- `ClairUI` starts an `SPUUpdater` with its own `SPUUserDriver` implementation that never shows Sparkle's windows.
- `package.sh` writes into `Info.plist`:
  - `SUFeedURL` = `https://github.com/itsjoshpark/Clair/raw/main/.sparkle/appcast.xml`
  - `SUPublicEDKey`, committed in the repository
  - `SUEnableAutomaticChecks` = YES, with automatic download and install on quit, and no user-facing settings
- `ClairUI` adds one update item to the Clair application menu with AppKit, after Chromium has built the main menu, as Arc does. No Chromium patch is needed for the menu.
  - **Check for Updates…** while no update is waiting. It starts a user-initiated check and shows an `NSAlert`: up to date, check failed, or "Clair X.Y.Z is ready" with **Restart and Update** / **Later**.
  - **Update Available…** while a downloaded update is waiting, with an `NSMenuItemBadge` reading "1 update". It shows the same "Clair X.Y.Z is ready" alert.
- **Install while idle**, as Arc does. When Sparkle reports an update that will install on quit (`updater(_:willInstallUpdateOnQuit:immediateInstallationBlock:)`), `ClairUI` keeps the immediate-installation block and watches the system idle time (`CGEventSourceSecondsSinceLastEventType` for any input, combined session state). After 30 minutes without input, it asks `ClairHost` whether a silent relaunch is safe: no download in progress, no incognito window, and no tab that is audible or capturing the camera, microphone or screen. If it is, `ClairUI` runs the block, which relaunches through the path below. If it isn't, it waits for the next 30 minutes without input. The relaunch doesn't activate Clair when another app was active. Arc's thresholds are server flags that weren't recorded, so 30 minutes is Clair's own choice.
- **Relaunch** goes through Chromium's own graceful relaunch (`chrome::AttemptRelaunch`), reached through `ClairHost.h`. It brings back the previous session, and Chromium's quit flow already asks about active downloads and warns that incognito windows won't reopen. Sparkle's relaunch is postponed until Chromium's shutdown finishes, so the app restarts exactly once. Helium's `application_lifetime_desktop.cc` change shows the same hand-off.
- **About page:** `chrome://settings/help` shows versions only. Ungoogled-chromium already has no updater; the builder confirms nothing update-related shows, and patches only if something does.
- A non-official build reads a feed-URL override from the environment for testing. Release packaging leaves it out.
- **The sidebar update banners** belong to the MVP change and follow Arc's (`arc-reference/look-and-behaviour.md`, Software updates):
  - while an update waits, a "New Clair Version Available" pill at the bottom of the sidebar, which grows on hover into a card with a **Restart and Update** button. It has no "Automatic Updates" checkbox, because Clair has no update settings
  - after an update, an "Update Complete!" banner with **See What's New**, which opens the release's page, `https://github.com/itsjoshpark/Clair/releases/tag/v<version>`, the appcast's `fullReleaseNotesLink`
  - `ClairUI` keeps the "update ready" state and the version it last ran, where the banners can observe them later.

**Alternatives considered:**
- Helium's Sparkle patches inside Chromium: rejected. They add four patches to maintain on every Chromium update, make Sparkle an engine input, and would be removed again once the native window exists.
- Building Sparkle from source: rejected. The pinned, checksummed release tarball already supplies Sparkle's tools, and building the framework adds time without a benefit to Clair.
- Sparkle's standard UI with dialogs and release notes: rejected by product choice, which is Arc-style.
- A separate "Install Update and Relaunch" menu item next to "Check for Updates…": replaced by Arc's single item that changes to "Update Available…".
- Arc's "Automatic Updates" checkbox and settings toggle: rejected, because Clair has no update settings.

### D5. Release pipeline: ensure the engine, run the quality checks, package, publish

`release.yml` is triggered manually, with `bump` (patch, minor or major) and `dry_run` inputs, and uses `concurrency: release` so only one release runs at a time. Its jobs run on the owner's Mac.

```
validate ──> engine ──> quality ──> package ──> publish
   |            |           |           |           |
   v            v           v           v           v
version,    download     D12 suite   ClairUI +   (non-dry-run)
build no.,  chromium-engine-<key>, against    Sparkle,    release commit,
notes check or build it  the engine  plist, sign, tag, GitHub
            (D10)        (must pass) notarize,   Release, push
                                     DMG, deltas main last
```

- **validate:**
  - works out the new version from the latest `v*` tag and the `bump` input
  - sets build number = `rev-list --count HEAD` + 1, since the release commit will be the next commit
  - checks that the build number is greater than the newest appcast entry
  - checks that `.sparkle/notes/next.md` exists and differs from the template, and that `<version>.md` doesn't exist yet
  - writes the results as job outputs
- **engine:** works out the engine key and downloads `chromium-engine-<key>`. If it isn't published, it runs the engine build (D10) first.
- **quality:** runs the quality checks (D12) on the release commit, unless they have already passed for that commit. A failure stops the release.
- **package:**
  - embeds `ClairUI.framework` and `Sparkle.framework`, and writes the version, build number and Sparkle keys into `Info.plist`
  - signs every helper, `ClairUI`, and Sparkle's `Autoupdate`/`Updater.app` individually with the hardened runtime and their entitlements, never using `--deep`
  - notarizes with `notarytool` and staples the app
  - builds the DMG, then signs, notarizes and staples the DMG
  - runs `scripts/verify-app.sh`
  - downloads the DMGs of the last three releases and makes `BinaryDelta` files
  - signs every asset with `sign_update`
  - dry run: uploads the DMG as a workflow artifact and stops
- **publish:**
  - creates the release commit (version and archived notes) in the Front Row way: `version.txt`, `.sparkle/notes/<version>.md`, a new `next.md` from the template, and the appcast entry from `append-appcast-item.sh`, extended for `<sparkle:deltas>` and a minimum system version of 15.6
  - tags it `v<version>`
  - creates the GitHub Release with the DMG, deltas, SHA-256 checksums and notes (Clair version, build number, ungoogled-chromium tag, engine key)
  - pushes to `main` only after the Release exists
  - before pushing, checks that `main` hasn't moved since `validate`. If it has, it aborts before creating the Release, so the appcast never points at missing files.
- The release commit changes only `version.txt`, the notes and the appcast. None of these is an engine input, so the release commit has the same engine key as the commit the quality checks ran on.

**Alternatives considered:**
- Release builds on hosted runners: rejected after measuring. 7 GB RAM is too little for an official ThinLTO link. See D9.
- Depot (about $34 per release build) or GitHub's larger runners (Team plan organizations only): kept as fallbacks if the self-hosted Mac becomes impractical.
- Committing the version before the build: rejected. A failed build would leave a released-looking commit on `main`.

### D6. Signing, notarization and secrets

The following are secrets of a `release` environment that is limited to `main`:
- the Developer ID Application certificate as base64 `.p12`, and its password
- a CI keychain password
- notarization credentials: an App Store Connect API key (key ID, issuer, `.p8`)
- `SPARKLE_ED_PRIVATE_KEY`

Handling:
- The Sparkle key is generated once, locally, with `generate_keys`. Its public half is committed. The private half goes into the secret and into an offline backup.
- Scripts pass secrets only through stdin or temporary keychains, never as command-line arguments, and run with `set +x` around any step that uses them.
- Engine builds, the merge gate and the quality checks get no secrets. Quality checks sign ad hoc, and use a test-only EdDSA key pair committed under `tests/` for their own test appcasts. That test key is never trusted by a shipped build.

### D7. Verification

- **`scripts/verify-app.sh`** runs in `package` and in the quality checks. It fails on any static check from the specs:
  - bundle and helper IDs
  - `LSMinimumSystemVersion` is 15.6
  - every Mach-O is arm64 only (checked with `lipo`)
  - `CFBundleShortVersionString` matches `version.txt` and `CFBundleVersion` is an integer
  - `SUFeedURL` and `SUPublicEDKey` are present
  - no "Chromium" in `CFBundleName`
  - in `package` only: `codesign --verify --strict`, `spctl --assess` and `stapler validate` pass
- **Runtime behaviour** is covered by the quality checks (D12).
- **A manual release checklist** keeps only what the quality checks can't do on a hosted runner: a clean Mac's first open of the notarized DMG, default-browser registration, the real Developer ID update path (deltas, install on quit, Restart and Update, install while idle), and Sparkle's rejection of a release signed by a different team.

### D8. Attribution and licensing

- Each copied patch keeps its original header. Clair's changes to it are marked.
- `CREDITS.md` lists ungoogled-chromium, ungoogled-chromium-macos, Helium, Sparkle and Front Row's release scripts, with their licenses, and Crest for any file adapted from it.
- Files adapted from Crest keep MPL-2.0 for those files, which is compatible with GPLv3. Crest's own BrowserWindow code adapts Mori's (MIT), so that provenance is kept too if Clair adapts it.
- The combined work is GPLv3. Code from BSD-3, MIT and MPL-2.0 sources keeps its own license.

### D9. Where builds run

| Work | Runs on | Started by |
|---|---|---|
| Merge gate | hosted `xcode-27` and Ubuntu | every pull request and push |
| Patch check | hosted `xcode-27` | pull requests that change the engine key |
| Engine build | owner's Mac (`clair-release`) | the owner, by hand (`engine.yml`, any of the owner's branches), or a release |
| Quality checks | hosted `xcode-27` | every push to `main`, by hand on any branch, and releases |
| Release | owner's Mac (`clair-release`) | the owner, from `main` |

- **No Chromium compile runs on hosted runners.** Hosted runners only fetch and patch the source (the patch check) or run the packaged app (the quality checks).
- **Runner security, since the repository is public:**
  - The runner runs as the owner's own macOS user and is started by hand, not as a service. Workflow code therefore has the owner's file and keychain access. This is accepted because only the owner can start runs on it (below), and `engine.yml` builds only branches of this repository, never a pull request ref (`refs/pull/*`).
  - Only `workflow_dispatch` runs target `clair-release`, and starting one needs write access to the repository, which only the owner has. No `pull_request` workflow targets it.
  - Fork PR workflows need the owner's approval ("Require approval for all external contributors").
  - Engine builds run without the `release` environment, so they never see release secrets. They need only `contents: write` to publish the engine prerelease.
  - `prepare-runner.sh` (which deletes Xcode versions and simulators) runs only on hosted runners.
- **Secrets** reach only release jobs on the Mac, for the duration of the job. Because the runner shares the owner's user, the release job leaves the owner's keychains alone:
  - It creates `$RUNNER_TEMP/clair-signing.keychain-db`, locked with the CI keychain password, and imports the Developer ID certificate into it.
  - It adds that keychain to the user's keychain search list for the duration of the job, so it shows in Keychain Access while a release runs. It never changes the default keychain and never writes to the login keychain.
  - `notarytool` gets the App Store Connect key as a file and IDs (`--key`, `--key-id`, `--issuer`), not as a profile stored in the keychain.
  - When the job ends, including on failure or cancellation, it restores the previous search list and deletes the keychain, so the Mac keeps nothing between releases.
- The engine smoke test runs the bare engine with `--use-mock-keychain`, so engine builds add no keychain items either.

### D10. Engine key and prebuilt engines

- **`scripts/engine-key.sh`** prints the engine key: the first 16 hex characters of a SHA-256 over a sorted manifest of `<path> <sha256>` lines. The manifest covers:
  - the `ungoogled-chromium` submodule commit
  - `downloads.ini`, `flags.macos.gn` and any other GN flag files
  - everything under `patches/`, `overlay/` and `utils/`
  - `native/ClairHost.h`
  - the branding resources compiled into the engine
  - `build.sh`, `retrieve_and_unpack_resource.py`, and `scripts/engine-key.sh` itself

  It can also print the manifest, so a key change can be explained. Its test checks that changing any covered file changes the key, and that changing anything else (Swift sources, `version.txt`, notes, workflows, `package.sh`) does not.
- **The engine artifact** is the unsigned `Clair.app` that the Chromium build produces, with the branding, the hook and the Chromium version compiled in. There is no `ClairUI`, no Sparkle, and no Clair version in it. It is published as the GitHub prerelease `chromium-engine-<key>` with:
  - `Clair-Chromium-Engine-<key>-arm64.zip` (made with `ditto`, which keeps the bundle's symlinks) and its SHA-256
  - `engine.json`: the key, the manifest, the ungoogled-chromium tag, the Chromium version, the Xcode and SDK versions, and the build date

  The naming follows Crest's (`chromium-engine-<key>`, `Crest-Chromium-Engine-<key>-arm64.zip`). The release is created as a draft prerelease and published with `--latest=false` only after every asset is uploaded, so a half-uploaded engine is never visible. Engine prereleases never become the repository's "latest" release, and the release tooling looks only at `v*` tags. They do appear on the Releases page and add a tag each; each one's notes say it's an internal build artifact, not for users.
- **`engine.yml`** (`workflow_dispatch`, input: the ref to build) runs on the owner's Mac:
  1. works out the key and stops early if `chromium-engine-<key>` already exists
  2. prepares the source in the persistent workspace on the Mac's internal disk (D11)
  3. builds with the full release settings, under `caffeinate -i -s` so the Mac doesn't sleep during the build. It stops the build if free space falls below 10 GB.
  4. runs the headless smoke test against the bare engine, in a throwaway home (`HOME` and `CFFIXED_USER_HOME`) with `--use-mock-keychain`, so the owner's own Clair data directory and keychain are never touched
  5. zips the app into the workspace, and a second job on the same Mac publishes `chromium-engine-<key>` with a token of its own: the build job's token stopped working (HTTP 401) by the end of a four-hour compile
- Because the key is computed from file contents, an engine built from a pull request branch is valid for the squash-merged commit on `main` as long as the engine inputs are the same.

### D11. Fast engine rebuilds on the owner's Mac

- The Mac keeps a persistent engine workspace on its internal disk: the unpacked Chromium source, the downloads cache and `out/Default`. It is never deleted between runs, and is excluded from Time Machine and Spotlight.
- **Rerun for the same key:** the workspace records the key of a configured tree (`build/prepared_key`) and of a finished compile (`build/engine_key`). A rerun after a failed compile resumes ninja in the same tree, and a rerun after a failed smoke test or upload doesn't compile at all.
- **Same ungoogled-chromium tag, changed Clair patches or overlay:** `build.sh` reverts the previously applied Clair series and overlay and applies the new ones in place. Only files they touch change, so ninja rebuilds only the affected targets. The workspace records which key it currently holds.
- **New ungoogled-chromium tag or changed ungoogled series:** a fresh source tree, which in practice means a full rebuild.
- If an in-place update fails or leaves the tree in an unknown state, `build.sh` falls back to a fresh tree. Correctness wins over speed.
- The revert uses a pristine copy. After ungoogled-chromium's patches and the toolchains, `build.sh -k prepare` clones the tree to `build/base` with APFS `clonefile`, which costs no disk space until files change. `build.sh update` applies Clair's whole layer (its patch series, name and domain substitution, the icon) to a new clone of the base, then copies into the workspace only the files whose contents changed: those the previous or the new layer touched. Unchanged files keep their modification times, so ninja sees only real changes. The base is valid while the ungoogled-chromium commit, `downloads*.ini` and `retrieve_and_unpack_resource.py` are the same.
- **Fixing a broken engine build from the development machine:** edit the patch, push the branch, start `engine.yml` with `gh workflow run`, and read its log with `gh run view --log`. A patch that no longer applies is caught earlier by the patch check (D12).

### D12. Checks: merge gate, patch check, quality checks

- **Merge gate** (`ci.yml`, every pull request and push, target under 10 minutes):
  - `scripts/*.test.sh`, `shellcheck -S warning`, `actionlint`
  - `xcodebuild build` and `xcodebuild test` for `ClairUI` and `ClairUITests`, unsigned. It compiles against `native/ClairHost.h`, with no Chromium.
  - an **engine check** job that works out the pull request's engine key and its base's key. If they differ:
    - it runs the patch check on `xcode-27`: fetch the pinned source, apply ungoogled's series, `patches/series`, the overlay and domain substitution, with no compile (`./build.sh fetch prepare`, about 40 minutes)
    - it reports whether `chromium-engine-<key>` is published, and fails until it is, so an engine change can't merge without an engine. After publishing, `engine.yml` re-runs the engine check on open pull requests whose head has that key, so nobody has to re-run it by hand.
  - All of these are required checks on `main`.
- **Quality checks** (`quality.yml`: push to `main`, `workflow_dispatch` on any ref, and called by `release.yml`):
  1. downloads `chromium-engine-<key>`. If it isn't published, the run fails with "no engine for <key>" and the command to build it.
  2. builds `ClairUI` and packages the app unsigned (ad-hoc signed), with the version of the commit
  3. runs `verify-app.sh` without the signing checks
  4. runs the runtime suite in `tests/runtime/` on the hosted runner's desktop session
- **The runtime suite** starts with these tests:
  - the app launches with a fresh data directory and renders a local test page
  - the application menu reads "About Clair", "Hide Clair" and "Quit Clair", and contains "Check for Updates…"
  - `~/Library/Application Support/Clair` and a "Clair Safe Storage" keychain item are created, and no "Chromium Safe Storage" item is read or created
  - `navigator.userAgent` reports the engine's Chromium version and doesn't contain the Clair version
  - the About page shows the Clair version and build number, and the Chromium version labelled as the engine
  - an idle first launch makes no requests to Google service hosts, checked with `--log-net-log`
  - "Check for Updates…" against local test appcasts, signed with the test key, reports "up to date" and "Clair X.Y.Z is ready" correctly, and the item then reads "Update Available…"
  - with an update waiting and a simulated idle period, Clair installs and relaunches, and doesn't while a download is in progress, an incognito window is open, or a tab is audible
  - relaunching through `ClairHost` restores the open windows and tabs

  The runtime suite runs the app through the macOS accessibility APIs (XCUITest, launching `Clair.app` by path) for native UI. It uses the Chrome DevTools Protocol (`--remote-debugging-port`, quality-check builds only) for page state.
- **On failure:** the quality run fails visibly on the `main` commit and opens or updates a GitHub issue labelled `quality-failure`. The issue names the commit, the failing tests and the run link, so an agent can be sent to fix it.
- **Releases** run the quality checks for their own commit (D5) and stop on a failure. They never wait on, or skip, a run that's still in progress.
- **Not covered:** visual appearance, layout and animation, which are checked by hand in the running app.

## Risks / Trade-offs

- **[Risk] The owner's Mac is offline** when an engine build or a release is needed.
  → Engine pull requests wait. Merges without engine changes and their quality checks continue, using the existing engines. Depot or larger hosted runners are the fallback (D5).
- **[Risk] An in-place engine update leaves a stale or mixed tree,** giving an engine that doesn't match its key.
  → The workspace records its key, `build.sh` falls back to a fresh tree on any doubt, and the patch check proves the same inputs apply to clean source on a hosted runner.
- **[Risk] Chromium reads the outer bundle's version** in places that break when packaging writes the Clair version (D3).
  → The builder audits these reads before task 3.1 is done, and patches each one that must keep the Chromium version.
- **[Risk] Chromium 156 doesn't build with Xcode 27's own SDK.**
  → Build the engine with Xcode 27 and a macOS 26.x SDK, as Crest does, and record the SDK in `engine.json`. PR #1's hosted chain keeps Xcode 26.6 until it is retired. Software Update replaces the Command Line Tools' SDKs (26.2 became 26.5 between two runs), so `engine.yml` uses the newest installed 26.x SDK, 26.2 or later, and `build.sh configure` deletes `out/Default` when the SDK has changed: `mac_sdk_path` is a symlink with a fixed name, so ninja doesn't see the change, and the first engine linked objects from both 26.2 and 26.5. The `clean` input forces the same from-scratch compile.
- **[Risk] Chromium's tools lag new Python releases.** The first engine build, with Python 3.15, failed in the fetch stage: `gsutil`, which `gclient sync` runs, supports only Python 3.9 to 3.14.
  → `engine.yml` builds with Homebrew's Python 3.13, the version the hosted jobs use, and checks it before building. `engine.json` records the version.
- **[Risk] The `xcode-27` hosted image is a preview,** so it may queue or break.
  → Accepted, since Crest relies on it too. Fallback: `macos-26` with Xcode 27 installed in the job.
- **[Risk] Main-menu changes:** Chromium may rebuild or reorder the main menu after `ClairUI` adds its items.
  → The quality suite checks the items. Fallback: a one-line hook in `main_menu_builder.mm` that calls into `ClairUI`.
- **[Risk] Sparkle and Chromium both want to relaunch.**
  → Sparkle's relaunch waits for Chromium's shutdown, as in Helium. The quality suite covers relaunch through `ClairHost`, and the release checklist covers the real update path.
- **[Risk] An idle install interrupts something the user left running,** such as a long download, a call, or music.
  → It runs only after 30 minutes without input, and `ClairHost` vetoes it while a download is in progress, an incognito window is open, or a tab is audible or capturing. The session is restored after the relaunch. The quality suite covers each veto.
- **[Risk] Hosted-runner GUI tests are flaky.**
  → Tests wait on conditions rather than fixed times, and a test failure is retried once before it counts.
- **[Risk] Disk on the owner's Mac:** a persistent workspace and its downloads cache take about 38 GB of the internal disk (measured on the first engine; 50 GB with a margin), which also holds macOS and the owner's files, so filling it affects the whole Mac.
  → Before building, `engine.yml` estimates how much the build will grow the workspace (a fresh tree: about 50 GB, less the workspace it replaces; an in-place update: much less) and refuses to start if that would leave less than 30 GB free. It reports the free space before and after the build.
- **[Risk] `main` moves during a long release.**
  → `concurrency: release`, plus the publish job's check that `main` hasn't moved before creating the Release. Avoid pushing to `main` while a release runs.
- **[Risk] Helium's versioning and identity patches stop applying** on a new Chromium version.
  → They live in Clair's tree, so Clair can fix them without waiting for Helium. Helium's upstream fixes are a reference.
- **[Risk] The Sparkle private key is lost or leaked.** Losing it strands every installed copy; leaking it lets someone else push updates.
  → Keep an offline backup. The key exists only in the secret store and the backup. If it's lost, the only recovery is asking users to reinstall by hand, so the backup is essential.
- **[Trade-off] Engine pull requests can't merge until the owner has built their engine.**
  → Accepted, so that `main` always has an engine and its quality checks always run.
- **[Trade-off] Extensions:** without Web Store URLs, extension installs work but feel clumsy in this release.
  → Accepted for change 1. The MVP decides on Web Store support.
- **[Trade-off] Rollback:** Sparkle never downgrades.
  → Roll back by shipping a newer build with the problem reverted.

## Migration Plan

- This is the first release, so there is no user data to migrate.
- **From PR #1's hosted build chain:**
  1. PR #1 and #2 finish their hosted builds and merge as they are. The builds prove that the patches and branding compile end to end before the owner's Mac is set up.
  2. The owner sets up the self-hosted runner (task 7.0).
  3. `engine.yml` publishes the first engine from `main`.
  4. The hosted compile phases (`build-phase.yml` and the compile part of `build.yml`) are removed. Their fetch and patch job becomes the patch check, and `pack-build.sh`/`unpack-build.sh` are kept only if the engine packing reuses them.
- Steps before the first release:
  1. generate the Sparkle keys and store them in secrets and the backup
  2. add the Apple secrets
  3. publish an engine and get the quality checks green on `main`
  4. run a dry run and fix signing and notarization
  5. do the manual release checklist on the dry-run DMG
  6. write `next.md` and release `0.1.0`
- The update path is first exercised by `0.1.1`, which tests deltas once earlier releases exist. Before that, test it with a dry run against a private test appcast.

## Open Questions

- Engine build times on the owner's Mac: a full build, and a typical in-place patch fix. Measured on the first engine builds.
- Whether hosted runners' desktop sessions allow the keychain and accessibility access the runtime suite needs without prompts. Checked in the first quality run.
