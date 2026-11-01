# Tasks

Tasks marked **(owner)** need the repository owner to act, because they involve Apple account credentials, secrets, a key backup, the self-hosted Mac or repository settings.

The development machine never fetches or builds Chromium:

- Chromium is compiled only by `engine.yml` on the owner's Mac (D9, D10).
- The patch check and the quality checks run on hosted runners.
- Before section 10 lands, PR #1's hosted chained build is the only Chromium build.

Wherever a verification below needs a built app, it means the engine published by `engine.yml`, or the app packaged and tested by the quality checks, and their logs.

Suggested order: 1, 2 and 3 (engine content), 10 (engine pipeline), 9 (native layer), 4 (updater), 11 (checks), then 5, 7 and 8 (release).

## 1. Repository scaffolding and engine pin

- [x] 1.1 Add `ungoogled-chromium` as a git submodule pinned to tag `156.0.8078.47-1`, or to the newest tag at implementation time. Verify that `git submodule status` shows the tag and that `ungoogled-chromium/chromium_version.txt` matches it.
- [x] 1.2 Copy into the repo, keeping their headers, the following from `ungoogled-chromium-macos`: its macOS patches (as `patches/ungoogled-chromium-macos/`), `entitlements/`, `retrieve_and_unpack_resource.py`, `downloads.ini` (arm64 entries only) and `flags.macos.gn` (arm64 only); also add `LICENSE.ungoogled_chromium`. Create `patches/series`. Verify that every `patches/series` entry resolves to a file.
- [ ] 1.3 Port `build.sh` for arm64 only. It applies ungoogled's series, then `patches/series`, then domain substitution, and writes `args.gn`. Add a patch-only mode (`./build.sh fetch prepare`). Verify that the CI fetch job finishes the patch-only mode on clean source, and that a throwaway commit changing one line of context in one patch makes the job fail and name that patch.
- [x] 1.4 Add `build/` and the other generated paths to `.gitignore`, and add `CREDITS.md` listing ungoogled-chromium and ungoogled-chromium-macos with their licenses. Verify that `git status` stays clean after a build.
- [x] 1.5 Do a full CI build with no Clair patches yet, through `build.yml` and its chained `build-phase.yml` jobs on a pull request (PR #1). Verify that a phase reports `finished`, that the headless smoke test renders a page, that the build leaves the work tree clean, and that the unsigned app artifact is uploaded. This is the baseline.
- [ ] 1.6 Make `build.sh prepare` copy `overlay/` into the source tree after the patches, and refuse an overlay file whose path already exists in the Chromium tree. Verify with a test overlay file that it appears in the prepared tree, and that an overlay file shadowing an existing Chromium file fails the prepare step and names the file.
- [ ] 1.7 Write `docs/building.md`: how the engine and app builds are split, the engine key, starting `engine.yml` and reading its log from the development machine, building the native layer with Xcode, and the quilt workflow for editing patches. Verify that a contributor can follow it to rebuild an engine after changing one patch.

## 2. App identity

- [x] 2.1 Add `patches/clair/branding.patch` (`BRANDING` file: product names, `MAC_BUNDLE_ID=dev.joshuapark.Clair`, team ID, company and copyright) and extend ungoogled's `tweak_info_plist.py` change for the new ID. Verify that the built bundle is `Clair.app` with `CFBundleIdentifier` `dev.joshuapark.Clair`, and that every helper app's ID starts with `dev.joshuapark.Clair.`.
- [ ] 2.2 Port Helium's `utils/name_substitution.py` (GPLv3, credited in `CREDITS.md`) and run it from `build.sh`. Verify that the application menu reads "About Clair", "Hide Clair" and "Quit Clair", and that a new window, the About page and `chrome://settings` show no "Chromium" product name.
- [ ] 2.3 Adapt Helium's `change-product-dir-name` and `change-keychain-name` patches for Clair. Verify on first launch that `~/Library/Application Support/Clair` and `~/Library/Caches/Clair` are created, and that a "Clair Safe Storage" keychain item appears with no "Chromium Safe Storage" item created or read. Verify that Clair and an ungoogled-chromium build run at the same time with separate profiles.
- [ ] 2.4 Add the resource-replacement step to `build.sh prepare`: compile `resources/icon/AppIcon.icon` with `scripts/compile-icon.sh` into `chrome/app/theme/chromium/mac/`, and copy every entry in `resources/icon/product-logos.txt` to its Chromium path. The artwork and both files come from the `design-app-icon` change. They are engine inputs. Verify that the Dock and Finder show the Clair icon, and that `scripts/engine-key.sh` changes its key when an icon file changes.
- [x] 2.5 Set `LSMinimumSystemVersion` to 15.6. Verify with `PlistBuddy`, and verify with `lipo -archs` that every Mach-O in the bundle is arm64 only.
- [ ] 2.6 Check default-browser registration. Verify that System Settings lists "Clair" as a default browser choice, and that with Clair selected, a link opened from another app opens in Clair.
- [ ] 2.7 Create `scripts/verify-app.sh` with the static identity checks: bundle and helper IDs, minimum OS, arm64 only, no "Chromium" in `CFBundleName`. Add a flag that skips the signing checks for unsigned builds. Verify that it passes on a packaged app and fails on an untouched ungoogled-chromium build.

## 3. Versioning

- [ ] 3.1 Add `version.txt` set to `0.1.0`. Make `package.sh` write `CFBundleShortVersionString` from `version.txt` and `CFBundleVersion` from `git rev-list --count HEAD` (or the release's build number) into `Clair.app/Contents/Info.plist`. Before that, audit every place Chromium reads the outer bundle's version, using Helium's versioning and Sparkle patches as a map, and patch any read that must keep the Chromium version (D3). Verify both plist values in a packaged app, and that it launches and loads its framework.
- [ ] 3.2 Adapt Helium's `add-helium-versioning.patch` so the About page and `chrome://version` read the Clair version and build number from the main bundle's `Info.plist` at run time. They also show the Chromium version and ungoogled-chromium revision, labelled as the engine. Verify by opening About Clair in two packages of the same engine with different `version.txt` values.
- [ ] 3.3 Verify that the engine version reaches the web unchanged. `navigator.userAgent` and client hints should match an ungoogled-chromium build of the same tag and not contain `0.1.0`. A test extension with `minimum_chrome_version` set to `150` should install.
- [ ] 3.4 Extend `scripts/verify-app.sh` to check the version: the short version matches `version.txt`, and the build number is an integer. Verify that it passes on a packaged app.

## 4. Sparkle updater (in the native layer)

- [ ] 4.1 **(owner)** Generate the Sparkle EdDSA key pair with `generate_keys` from the pinned Sparkle release tarball. Store the private key in the `release` environment secret `SPARKLE_ED_PRIVATE_KEY` and in an offline backup, and commit the public key. Verify that `generate_keys -p` prints the committed public key.
- [ ] 4.2 Add a script that downloads the Sparkle 2.10.0 release tarball, checks its sha512, and provides `Sparkle.framework`, `sign_update`, `BinaryDelta` and `generate_keys`. Make `package.sh` embed `Sparkle.framework` and write `SUFeedURL`, `SUPublicEDKey` and `SUEnableAutomaticChecks` = YES into `Info.plist`. Verify these in a packaged app, and that a tampered tarball fails the checksum.
- [ ] 4.3 Start an `SPUUpdater` from `ClairUI` with a custom `SPUUserDriver` that never shows a window: automatic checks every 24 hours or less, background download, install on quit, and no settings UI. Use a local test appcast and a newer test package. Verify that the update downloads with no window shown, and that after quitting, the next launch runs the new version.
- [ ] 4.4 Add a feed-URL override that only non-official packages read, for testing. Verify that a release package ignores it.
- [ ] 4.5 Add the update item to the Clair menu from `ClairUI` with AppKit. It reads "Check for Updates…", and "Update Available…" with a "1 update" badge while an update is waiting. "Check for Updates…" shows `NSAlert`s for up to date, check failed, and ready with "Restart and Update" / "Later"; "Update Available…" shows the ready alert. Verify every `software-updates` menu scenario against the test appcast, and that the items survive opening new windows and switching profiles.
- [ ] 4.6 Send update relaunches through `ClairHost`'s graceful relaunch, and postpone Sparkle's own relaunch until Chromium's shutdown finishes, so the app restarts once. Verify that three windows with tabs come back after "Restart and Update", that an active download asks for confirmation and can be postponed, and that open incognito windows produce a warning.
- [ ] 4.7 Check that `chrome://settings/help` shows no update status, and patch it out only if something shows. Verify that the About page shows only versions.
- [ ] 4.8 Run the negative update cases against test appcasts. Verify each one: a tampered DMG is rejected and the current version keeps running; a release with a higher minimum macOS is not offered; an equal or lower build is not offered; a delta that fails to apply falls back to the full DMG.
- [ ] 4.9 Write `docs/updates.md`: the update flow, key custody and backup, the test-appcast procedure, the test-only key used by the quality checks, and why Sparkle can't downgrade (so rollback means shipping a newer build). Verify that the test-appcast procedure works as written.
- [ ] 4.10 Install a waiting update while the user is idle (D4): keep Sparkle's immediate-installation block, and after 30 minutes without input, run it if `ClairHost` reports a silent relaunch is safe, without activating Clair when another app was active. Make the idle threshold overridable in non-official packages for testing. Verify against the test appcast that an idle period installs and relaunches with the session restored, that a download in progress, an open incognito window, or an audible tab each prevents it until a later idle period, and that Clair stays in the background when another app was active.

## 5. Signing, notarization and packaging

- [ ] 5.1 Write `package.sh`, ported from ungoogled-macos's `sign_and_package_app.sh` with Clair names. It takes an engine artifact, embeds `ClairUI.framework` and `Sparkle.framework`, writes the plist values (3.1, 4.2), and signs each helper with its own ID, the hardened runtime and entitlements. It signs `ClairUI`, Sparkle's `Autoupdate` and `Updater.app` separately, without `--deep`. Without signing credentials, it signs ad hoc. Verify that `codesign --verify --strict` passes for the app and every nested bundle in both modes.
- [ ] 5.2 Add notarization with `notarytool` (App Store Connect API key) and stapling for the app and the DMG. Verify that `stapler validate` passes for both, and that `spctl --assess --type execute` names Clair's Developer ID team.
- [ ] 5.3 Build the DMG with `Clair.app`, an `/Applications` link and a background. Verify that mounting it shows that layout. Verify that on a Mac or user account that has never run Clair, it opens after only the standard downloaded-from-the-internet prompt.
- [ ] 5.4 Extend `scripts/verify-app.sh` with the `codesign`, `spctl` and `stapler` checks and a check that the Sparkle keys are present. Verify that it passes on a notarized package.

## 6. Release tooling scripts

- [x] 6.1 Create `.sparkle/` with an empty-channel `appcast.xml`, and `notes/TEMPLATE.md`, `notes/README.md` and `notes/next.md`, adapted from Front Row. Verify that `xmllint --noout .sparkle/appcast.xml` passes.
- [x] 6.2 Port Front Row's `append-appcast-item.sh`, `render-notes.sh` and their tests, and extend them for `<sparkle:deltas>` (up to three) and `sparkle:minimumSystemVersion` 15.6. Verify that the extended test script passes, including a case with three deltas.
- [x] 6.3 Add the release validation script. It works out the version from the latest `v*` tag plus the bump, sets the build number to `rev-list --count HEAD` + 1, checks that this is greater than the newest appcast entry, and checks that `next.md` is present and edited and that `<version>.md` doesn't exist. Add tests. Verify that the tests cover `0.1.0` → `0.1.1` for a patch bump, `0.1.3` → `0.2.0` for a minor bump, and each refusal case.
- [ ] 6.4 Add the delta script. It downloads the DMGs of up to three previous releases, runs `BinaryDelta create`, and signs each asset with `sign_update`, using tools from the pinned Sparkle release tarball, checked against its sha512. Verify with two local packages that the delta applies (`BinaryDelta apply`), and that the result passes `codesign --verify`.
- [x] 6.5 Add `ci.yml`, which runs the script tests and shellcheck on pushes and pull requests. Verify that a run is green.
- [ ] 6.6 Check that the release validation script ignores `chromium-engine-*` tags and prereleases. Verify with a test that has an `chromium-engine-0123456789abcdef` tag newer than the latest `v*` tag.

## 7. CI release workflow

- [x] 7.0 **(owner)** Set up the self-hosted runner on the owner's Mac, under the owner's own macOS user. It needs:
  - a work directory and the persistent engine workspace on the internal disk, excluded from Time Machine and Spotlight
  - label `clair-release`; the owner starts the runner by hand (`./run.sh`) when needed, not as a service
  - the CI toolchain: Xcode 27.2 with its Metal toolchain, the macOS SDK the engine needs (see design Risks), brew packages, and Homebrew's Python 3.13 with PySocks and httplib2 (see design Risks)
  - "Require approval for all external contributors" turned on for fork PR workflows

  Verify with a `workflow_dispatch` test job on `[self-hosted, clair-release]` that prints the toolchain versions and the internal disk's free space.
- [ ] 7.1 **(owner)** Add the secrets to a `release` environment limited to `main`: the Developer ID `.p12` (base64) and its password, a CI keychain password, and the App Store Connect API key ID, issuer and `.p8`; `SPARKLE_ED_PRIVATE_KEY` is from 4.1. Verify that a workflow step reports each secret as present without printing any value.
- [ ] 7.2 Add `release.yml`. It has inputs `bump` (patch, minor or major) and `dry_run`, and `concurrency: release`. Its jobs are:
  - `validate`, using the 6.3 script
  - `engine`, which downloads `chromium-engine-<key>`, or calls `engine.yml` and waits when it isn't published
  - `quality`, which calls `quality.yml` unless it has already passed for the commit

  Verify that `validate` fails with an unedited `next.md`. Verify that a commit whose quality checks failed stops the run before packaging. Verify that a commit with no engine builds one first.
- [ ] 7.3 Add the `package` job on the owner's Mac: `package.sh` with signing, notarization, stapling, the DMG, `verify-app.sh`, deltas and `sign_update`. Signing uses the temporary keychain from D9. In dry-run mode it uploads the DMG as a workflow artifact and stops. Verify that a dry run produces a notarized DMG and makes no tag, Release or appcast change, and that after a dry run, and after one cancelled mid-signing, the user's keychain search list is as it was and `clair-signing.keychain-db` is gone.
- [ ] 7.4 Add the `publish` job. It:
  - makes the release commit (`version.txt`, archived notes, a new `next.md`, the appcast entry)
  - checks that `main` hasn't moved since `validate`
  - tags `v<version>`
  - creates the GitHub Release: the DMG, deltas, SHA-256 checksums, and notes with the Clair version, build number, ungoogled-chromium tag and engine key
  - pushes to `main` last

  Verify with a rehearsal on a throwaway fork. The Release should exist before the appcast push, and when `main` moves mid-release, the run should abort with no Release created.
- [ ] 7.5 Check secret hygiene. Verify that searching the full logs and every published asset of a dry run and a rehearsal finds neither the Sparkle private key nor the certificate password. Verify that `engine.yml` and `quality.yml` runs have no access to the `release` environment.
- [ ] 7.6 Write `docs/releasing.md`: how to start a release, writing `next.md`, the manual release checklist (from 8.1), key backup and the rollback policy. Verify by following it for the first release.

## 8. First release and end-to-end verification

- [ ] 8.1 Run the manual release checklist on the dry-run DMG on a clean Mac or user account. Verify that every item passes:
  - the notarized DMG opens after only the standard prompt
  - CRX install through the extension MIME flag
  - default ungoogled settings
  - default-browser registration
  - the update path with Developer ID–signed builds
- [ ] 8.2 Release `0.1.0` through the workflow. Verify that the GitHub Release has its assets and checksums, that `main` has the appcast entry with a link that resolves, and that the DMG installs and opens on a clean Mac.
- [ ] 8.3 Release `0.1.1`, either an ungoogled security bump or a notes-only release. Verify on a `0.1.0` install that the delta downloads in the background, that "Restart and Update" restores the session, and, separately, that quitting installs the update and that 30 minutes without input installs it.

## 9. Native layer

- [ ] 9.1 Write `native/ClairHost.h`: the entry point Chromium calls once the main menu exists, and a host protocol with graceful relaunch, whether a silent relaunch is safe (no download in progress, no incognito window, no audible or capturing tab), and the Chromium and ungoogled-chromium versions. Verify that it compiles in an Objective-C++ unit and from Swift through a module map.
- [ ] 9.2 Add `patches/clair/native-layer-hook.patch` plus overlay files under `overlay/chrome/browser/clair/`. Together they load `ClairUI.framework` from `Contents/Frameworks` after the main menu is built, implement the host protocol, and log and carry on when the framework is missing. Keep the patch to the call sites; the logic goes in the overlay. Verify that a bare engine starts and logs the missing framework, and that a packaged app loads it.
- [ ] 9.3 Add `native/ClairUI.xcodeproj` in Xcode 27.2's JSON format (`project.xcproj`, no `project.pbxproj`) for `ClairUI.framework` (Swift, macOS 15.6, arm64) and `ClairUITests`, with `ClairHost.h` exposed to Swift. Verify that `xcodebuild build test` succeeds on the development machine with no Chromium checkout, and that the project has no `project.pbxproj`.
- [ ] 9.4 Make `package.sh` build `ClairUI` (or take a built copy) and embed it. Verify that a change to a Swift file alone produces a new package from the same `chromium-engine-<key>`.

## 10. Engine pipeline

- [x] 10.1 Write `scripts/engine-key.sh` and its test (D10). Verify that the test changes each covered input and sees a new key, changes Swift sources, `version.txt`, notes, workflows and `package.sh` and sees the same key, and that `--manifest` lists every covered file.
- [x] 10.2 Add `engine.yml` (`workflow_dispatch`, input: ref) on `[self-hosted, clair-release]`. It works out the key and stops if `chromium-engine-<key>` exists. Otherwise it builds with the release settings in the persistent workspace under `caffeinate -i -s`, runs the headless smoke test in a throwaway home (`HOME` and `CFFIXED_USER_HOME`), and publishes the `chromium-engine-<key>` prerelease with `Clair-Chromium-Engine-<key>-arm64.zip`, its SHA-256 and `engine.json`. It creates the release as a draft and publishes it with `--latest=false` only after every upload succeeds. It refuses refs under `refs/pull/`. Verify that a first run publishes an engine, that a second run for the same key stops in under a minute, and that a `refs/pull/<n>/head` ref is refused.
- [ ] 10.3 Make `build.sh` update the persistent workspace in place when the ungoogled-chromium pin is unchanged (D11), recording the key it holds, and fall back to a fresh tree otherwise. Verify that changing one Clair patch rebuilds only affected targets (ninja reports a small fraction of the full build), that the resulting engine matches a fresh-tree engine's smoke test, and that a deliberately corrupted workspace record triggers a fresh tree.
- [x] 10.4 Make `engine.yml` estimate how much the coming build will grow the workspace (fresh tree or in place) and refuse to start if that would leave less than 30 GB free on the workspace's volume. It reports the free space before and after the build. Verify by setting the reserve above the current free space.
- [x] 10.5 **(owner)** Publish the first engine from `main` after PR #1 and #2 merge. Record the measured full-build time and a patch-fix rebuild time in `docs/building.md`.
- [ ] 10.6 Remove the hosted compile phases (`build-phase.yml` and the compile part of `build.yml`) once 10.5 is done, keeping the fetch and patch job for the patch check. Verify that no hosted workflow runs ninja.

## 11. Checks

- [ ] 11.1 Extend `ci.yml` (the merge gate) with the native layer's `xcodebuild build` and `xcodebuild test`, unsigned, on `xcode-27`. Move `prepare-runner.sh` and the other hosted macOS jobs to the `xcode-27` image too, and update its Xcode cleanup for that image. Verify that a pull request changing only a Swift file finishes all checks within 10 minutes.
- [ ] 11.2 Add the engine check job to `ci.yml`. It compares the pull request's engine key with its base's. When they differ, it runs the patch check (`./build.sh fetch prepare` on `xcode-27`) and fails until `chromium-engine-<key>` is published. Make `engine.yml` re-run this check on open pull requests with the key it just published. Verify both cases: a Swift-only pull request skips it, and a pull request changing a patch runs it, and passes only after the engine is published.
- [ ] 11.3 **(owner)** Make the merge-gate jobs and the engine check required status checks on `main`. Verify that a pull request with a failing script test can't be merged.
- [ ] 11.4 Add `quality.yml` (push to `main`, `workflow_dispatch` on any ref, `workflow_call`). It downloads `chromium-engine-<key>`, or fails with "no engine for <key>" and the command to build it. It then packages the app ad-hoc signed and runs `verify-app.sh` without signing checks and the runtime suite. Verify that it passes on `main` after 10.5.
- [ ] 11.5 Write the runtime suite in `tests/runtime/` (D12): XCUITest for the native UI, the Chrome DevTools Protocol for page state, and a test-only Sparkle key with local test appcasts. Cover every test D12 lists, and retry a failed test once before it counts. Verify that each test fails when the behaviour it covers is broken on purpose.
- [ ] 11.6 Make a failed quality run on `main` open or update a GitHub issue labelled `quality-failure`, naming the commit, the failing tests and the run link, and close it when a later run on `main` passes. Verify with a dispatched run on a throwaway branch that has a deliberately failing test and issue reporting turned on by an input.

## Workflow follow-up

- Archive the change after `0.1.1` confirms the update path works end to end.
- After archiving, confirm that the six capability specs (`app-identity`, `chromium-engine`, `native-layer`, `software-updates`, `build-pipeline`, `release-distribution`) are present under `openspec/specs/`.
