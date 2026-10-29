# Tasks

Tasks marked **(owner)** need the repository owner to act, because they involve Apple account credentials, secrets or a key backup.

All Chromium fetching, patching and building runs on GitHub Actions (`build.yml`, triggered by pull requests), not on the development machine. Wherever a verification below needs a build, it means the CI build of the pull request, its logs, or the unsigned app artifact it uploads.

## 1. Repository scaffolding and engine pin

- [x] 1.1 Add `ungoogled-chromium` as a git submodule pinned to tag `156.0.8078.47-1`, or to the newest tag at implementation time. Verify that `git submodule status` shows the tag and that `ungoogled-chromium/chromium_version.txt` matches it.
- [x] 1.2 Copy into the repo, keeping their headers, the following from `ungoogled-chromium-macos`: its macOS patches (as `patches/ungoogled-chromium-macos/`), `entitlements/`, `retrieve_and_unpack_resource.py`, `downloads.ini` (arm64 entries only) and `flags.macos.gn` (arm64 only); also add `LICENSE.ungoogled_chromium`. Create `patches/series`. Verify that every `patches/series` entry resolves to a file.
- [ ] 1.3 Port `build.sh` for arm64 only. It applies ungoogled's series, then `patches/series`, then domain substitution, and writes `args.gn`. Add a patch-only mode (`./build.sh fetch prepare`). Verify that the CI fetch job finishes the patch-only mode on clean source, and that a throwaway commit changing one line of context in one patch makes the job fail and name that patch.
- [ ] 1.4 Add `build/` and the other generated paths to `.gitignore`, and add `CREDITS.md` listing ungoogled-chromium and ungoogled-chromium-macos with their licenses. Verify that `git status` stays clean after a build.
- [ ] 1.5 Do a full CI build with no Clair patches yet, through `build.yml` and its chained `build-phase.yml` jobs on a pull request. Verify that a phase reports `finished`, that the headless smoke test renders a page, that the build leaves the work tree clean, and that the unsigned app artifact is uploaded. This is the baseline.
- [ ] 1.6 Write `docs/building.md`: Xcode, Metal toolchain, brew dependencies, about 150 GB of disk, build commands, and the quilt workflow for editing patches. Verify that the CI build follows the documented stages exactly, and that a contributor with a capable Mac can follow it on a fresh clone.

## 2. App identity

- [ ] 2.1 Add `patches/clair/branding.patch` (`BRANDING` file: product names, `MAC_BUNDLE_ID=dev.joshuapark.Clair`, team ID, company and copyright) and extend ungoogled's `tweak_info_plist.py` change for the new ID. Verify that the built bundle is `Clair.app` with `CFBundleIdentifier` `dev.joshuapark.Clair`, and that every helper app's ID starts with `dev.joshuapark.Clair.`.
- [ ] 2.2 Port Helium's `utils/name_substitution.py` (GPLv3, credited in `CREDITS.md`) and run it from `build.sh`. Verify that the application menu reads "About Clair", "Hide Clair" and "Quit Clair", and that a new window, the About page and `chrome://settings` show no "Chromium" product name.
- [ ] 2.3 Adapt Helium's `change-product-dir-name` and `change-keychain-name` patches for Clair. Verify on first launch that `~/Library/Application Support/Clair` and `~/Library/Caches/Clair` are created, and that a "Clair Safe Storage" keychain item appears with no "Chromium Safe Storage" item created or read. Verify that Clair and an ungoogled-chromium build run at the same time with separate profiles.
- [ ] 2.4 Add a placeholder app icon and asset catalog in `resources/`, plus the resource-replacement step. Verify that the Dock and Finder show the Clair icon.
- [ ] 2.5 Set `LSMinimumSystemVersion` to 15.6. Verify with `PlistBuddy`, and verify with `lipo -archs` that every Mach-O in the bundle is arm64 only.
- [ ] 2.6 Check default-browser registration. Verify that System Settings lists "Clair" as a default browser choice, and that with Clair selected, a link opened from another app opens in Clair.
- [ ] 2.7 Create `scripts/verify-app.sh` with the static identity checks: bundle and helper IDs, minimum OS, arm64 only, no "Chromium" in `CFBundleName`. Verify that it passes on the local build and fails on an untouched ungoogled-chromium build.

## 3. Versioning

- [ ] 3.1 Add `version.txt` set to `0.1.0`, and pass the version and build number (`git rev-list --count HEAD`) to GN. Adapt Helium's `add-helium-versioning.patch` so that `CFBundleShortVersionString` is the Clair version and `CFBundleVersion` is the build number. Verify both values in the built `Info.plist`.
- [ ] 3.2 Show the Clair version and build number, plus the Chromium version and ungoogled-chromium revision labelled as the engine, on the About page and in `chrome://version`. Verify by opening About Clair.
- [ ] 3.3 Verify that the engine version reaches the web unchanged. `navigator.userAgent` and client hints should match an ungoogled-chromium build of the same tag and not contain `0.1.0`. A test extension with `minimum_chrome_version` set to `150` should install.
- [ ] 3.4 Extend `scripts/verify-app.sh` to check the version: the short version matches `version.txt`, and the build number is an integer. Verify that it passes on the local build.

## 4. Sparkle updater

- [ ] 4.1 **(owner)** Generate the Sparkle EdDSA key pair with `generate_keys` from the pinned Sparkle release tarball. Store the private key in the GitHub secret `SPARKLE_ED_PRIVATE_KEY` and in an offline backup, and commit the public key as the GN default. Verify that `generate_keys -p` prints the committed public key.
- [ ] 4.2 Add Sparkle 2.10.0 source to `downloads.ini` with its sha512. Port ReBel's `sparkle-integration` and Helium's `fixup-sparkle-glue`, `sparkle2-integration` and `disable-default-updater` patches into `patches/helium/` (GPLv3 headers kept). Set GN args for the feed URL and public key. Verify that the built app has `Sparkle.framework` and that `Info.plist` contains `SUFeedURL` = `https://github.com/itsjoshpark/Clair/raw/main/.sparkle/appcast.xml`, `SUPublicEDKey` and `SUEnableAutomaticChecks` = YES.
- [ ] 4.3 Add a feed-URL override for testing that exists only in non-official builds. Verify that a release-configuration build ignores it.
- [ ] 4.4 Configure headless automatic checks every 24 hours or less, background download, and install on quit, with no settings UI. Use a local test appcast and a newer test build. Verify that the update downloads with no window shown, and that after quitting, the next launch runs the new version.
- [ ] 4.5 Add `patches/clair/update-menu.patch`. It adds "Check for Updates…", which shows `NSAlert`s for up to date, check failed, and ready with "Install and Relaunch" / "Later". It also adds "Install Update and Relaunch", shown only while an update is waiting. Verify every `software-updates` menu scenario against the test appcast.
- [ ] 4.6 Send update relaunches through Chromium's graceful relaunch, with session restore. Verify that three windows with tabs come back after "Install Update and Relaunch", that an active download asks for confirmation and can be postponed, and that open incognito windows produce a warning.
- [ ] 4.7 Remove the update status UI from `chrome://settings/help`. Verify that the About page shows only versions.
- [ ] 4.8 Run the negative update cases against test appcasts. Verify each one: a tampered DMG is rejected and the current version keeps running; a release with a higher minimum macOS is not offered; an equal or lower build is not offered; a delta that fails to apply falls back to the full DMG.
- [ ] 4.9 Write `docs/updates.md`: the update flow, key custody and backup, the test-appcast procedure, and why Sparkle can't downgrade (so rollback means shipping a newer build). Verify that the test-appcast procedure works as written.

## 5. Signing, notarization and packaging

- [ ] 5.1 Port `sign_and_package_app.sh` with Clair names. It signs each helper with its own ID, the hardened runtime and entitlements, and signs Sparkle's `Autoupdate` and `Updater.app` separately, without `--deep`. Verify that `codesign --verify --strict` passes for the app and every nested bundle.
- [ ] 5.2 Add notarization with `notarytool` (App Store Connect API key) and stapling for the app and the DMG. Verify that `stapler validate` passes for both, and that `spctl --assess --type execute` names Clair's Developer ID team.
- [ ] 5.3 Build the DMG with `Clair.app`, an `/Applications` link and a background. Verify that mounting it shows that layout. Verify that on a Mac or user account that has never run Clair, it opens after only the standard downloaded-from-the-internet prompt.
- [ ] 5.4 Extend `scripts/verify-app.sh` with the `codesign`, `spctl` and `stapler` checks and a check that the Sparkle keys are present. Verify that it passes on a notarized local package.

## 6. Release tooling scripts

- [x] 6.1 Create `.sparkle/` with an empty-channel `appcast.xml`, and `notes/TEMPLATE.md`, `notes/README.md` and `notes/next.md`, adapted from Front Row. Verify that `xmllint --noout .sparkle/appcast.xml` passes.
- [x] 6.2 Port Front Row's `append-appcast-item.sh`, `render-notes.sh` and their tests, and extend them for `<sparkle:deltas>` (up to three) and `sparkle:minimumSystemVersion` 15.6. Verify that the extended test script passes, including a case with three deltas.
- [x] 6.3 Add the release validation script. It works out the version from the latest `v*` tag plus the bump, sets the build number to `rev-list --count HEAD` + 1, checks that this is greater than the newest appcast entry, and checks that `next.md` is present and edited and that `<version>.md` doesn't exist. Add tests. Verify that the tests cover `0.1.0` → `0.1.1` for a patch bump, `0.1.3` → `0.2.0` for a minor bump, and each refusal case.
- [ ] 6.4 Add the delta script. It downloads the DMGs of up to three previous releases, runs `BinaryDelta create`, and signs each asset with `sign_update`, using tools from the pinned Sparkle release tarball, checked against its sha512. Verify with two local builds that the delta applies (`BinaryDelta apply`), and that the result passes `codesign --verify`.
- [x] 6.5 Add `ci.yml`, which runs the script tests and shellcheck on pushes and pull requests. Verify that a run is green.

## 7. CI release workflow

- [ ] 7.1 **(owner)** Add the repository secrets: the Developer ID `.p12` (base64) and its password, a CI keychain password, and the App Store Connect API key ID, issuer and `.p8`; `SPARKLE_ED_PRIVATE_KEY` is from 4.1. Verify that a workflow step reports each secret as present without printing any value.
- [ ] 7.2 Add `release.yml`. It has inputs `bump` (patch, minor or major) and `dry_run`, `concurrency: release`, a `validate` job using the 6.3 script, and a `fetch` job that downloads, patches and packs resources. Verify that a run uploads the resource artifact, and that `validate` fails with an unedited `next.md`.
- [ ] 7.3 Use the chained build (`build.yml`: fetch plus phases 1–20 through `build-phase.yml`, which is also run by pull requests) from `release.yml`. Each one cleans disk (preinstalled SDKs, Spotlight off), restores the partial `out/`, runs ninja under `timeout` with about an hour of headroom, uploads the partial `out/` compressed with zstd using `overwrite`, and is skipped once a job reports `finished`. Verify that a dry run finishes the build. Record the measured free disk, artifact sizes and total build time in `docs/releasing.md`.
- [ ] 7.4 Add the `package` job: sign, notarize, staple, DMG, `verify-app.sh`, deltas and `sign_update`. In dry-run mode it uploads the DMG as a workflow artifact and stops. Verify that a dry run produces a notarized DMG and makes no tag, Release or appcast change.
- [ ] 7.5 Add the `publish` job. It makes the release commit (`version.txt`, archived notes, a new `next.md`, the appcast entry), checks that `main` hasn't moved since `validate`, tags `v<version>`, creates the GitHub Release (DMG, deltas, SHA-256 checksums, notes with the Clair version, build number and ungoogled-chromium tag), and pushes to `main` last. Verify with a rehearsal on a throwaway fork. The Release should exist before the appcast push, and when `main` moves mid-release, the run should abort with no Release created.
- [ ] 7.6 Check secret hygiene. Verify that searching the full logs and every published asset of a dry run and a rehearsal finds neither the Sparkle private key nor the certificate password.
- [ ] 7.7 Write `docs/releasing.md`: how to start a release, writing `next.md`, the manual runtime checklist (from 8.1), key backup and the rollback policy. Verify by following it for the first release.

## 8. First release and end-to-end verification

- [ ] 8.1 Run the manual runtime checklist on the dry-run DMG on a clean Mac or user account. Verify that every item passes:
  - user agent matches ungoogled
  - "Clair Safe Storage" keychain item
  - data isolation alongside Chromium
  - CRX install through the extension MIME flag
  - default ungoogled settings
  - no Google service hosts in a `--log-net-log` capture of an idle first launch
  - default-browser registration
- [ ] 8.2 Release `0.1.0` through the workflow. Verify that the GitHub Release has its assets and checksums, that `main` has the appcast entry with a link that resolves, and that the DMG installs and opens on a clean Mac.
- [ ] 8.3 Release `0.1.1`, either an ungoogled security bump or a notes-only release. Verify on a `0.1.0` install that the delta downloads in the background, that "Install Update and Relaunch" restores the session, and, separately, that quitting installs the update.

## Workflow follow-up

- Archive the change after `0.1.1` confirms the update path works end to end.
- After archiving, confirm that the four capability specs (`app-identity`, `chromium-engine`, `software-updates`, `release-distribution`) are present under `openspec/specs/`.
