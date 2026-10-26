# Design

## Context

The motivation is in `proposal.md` (Why) and the required behaviour is in `specs/`. This section covers only what shapes the approach.

The repository holds only `LICENSE` (GPLv3), `.gitignore`, and OpenSpec files. There is no build code yet.

Two existing projects already solve most of this change, and Clair copies from them rather than depending on them:

- **ungoogled-chromium-macos** (BSD-3):
  - `build.sh`: download, then prune, patch and domain-substitute, then write `args.gn`, then build
  - `flags.macos.gn`
  - about 27 macOS build-fix patches, including `set-bundle-identifier.patch`
  - `sign_and_package_app.sh`: signs each helper with its own identifier and entitlements, then builds the DMG with `pkg-dmg`
  - a chained GitHub Actions build: one job fetches and packs resources, then up to 20 resume jobs. Each resume job runs `timeout … ninja` with about one hour of headroom under the 6-hour limit, then packs the partial `out/` as an artifact for the next job.
- **Helium / helium-macos** (GPLv3):
  - `change-chromium-branding.patch` (the `BRANDING` file)
  - `change-product-dir-name.patch` (`chrome_paths_mac.mm`)
  - `change-keychain-name.patch` (`keychain_password_mac.mm`)
  - `add-helium-versioning.patch`: a separate product version alongside the Chromium version (`version_info`, `tweak_info_plist.py`, the About and Version pages)
  - `utils/name_substitution.py`: replaces "Chromium" in user-facing strings
  - a Sparkle 2 integration:
    - `rebel/macos/sparkle-integration.patch`, plus Helium's `updater/{fixup-sparkle-glue,sparkle2-integration,disable-default-updater}.patch`
    - Sparkle **2.10.0 is built from source** in the GN build, at `third_party/sparkle`, through `build_sparkle_framework.py`
    - it uses a **headless user driver** (`SPUHeadlessUserDriver`)
    - `SUPublicEDKey` and `SUEnableAutomaticChecks` are written into `Info.plist` by `tweak_info_plist.py`
- **Front Row** (`itsjoshpark/FrontRow`) provides the release mechanics:
  - `.sparkle/appcast.xml` committed on `main`
  - `.sparkle/notes/next.md` and `TEMPLATE.md`
  - `scripts/append-appcast-item.sh`, which has a test
  - `release.yml`, triggered manually with patch/minor/major and a dry-run option. It validates the build number and the notes, and uses the commit count as the build number. The release commit is tagged first and pushed to `main` last.

Constraints:

- **Runner:** a standard `macos-latest` arm64 runner has 3 M1 cores, 7 GB RAM and 14 GB of SSD listed. The job limit is 6 hours and the cache is 10 GB.
- **Engine:** ungoogled-chromium removes Web Store URLs (`disable-webstore-urls.patch`). Extensions are installed through the `extension-mime-request-handling` flag.

## Goals / Non-Goals

**Goals:**
- One repository that builds Clair from a pinned ungoogled-chromium tag, both locally and in CI, with the same scripts.
- Keep Clair's own code that touches Chromium to the minimum this change needs: branding, versioning and updater.
- A release process that is safe to run for every ungoogled-chromium security tag with a single changed line.

**Non-Goals:**
- A good Chrome Web Store install experience. ungoogled-chromium's behaviour stays as it is, and the MVP will revisit it.
- Automatically starting a release when ungoogled-chromium publishes a tag.
- Faster builds through `sccache`, remote build execution, or caching.
- Automated runtime UI tests. Runtime checks are a manual checklist in this change.

## Decisions

### D1. Repository layout: ungoogled-chromium submodule, plus a Clair-owned macOS layer

```
Clair/
  ungoogled-chromium/          git submodule, pinned to a tag
  patches/
    series                     Clair's macOS-layer series, in apply order
    ungoogled-chromium-macos/  copied from ungoogled-chromium-macos (BSD-3), credited
    helium/                    copied or adapted from Helium (GPLv3); original headers kept
    clair/                     Clair-only patches
  utils/                       name_substitution.py, version tools (from Helium, GPLv3)
  resources/                   icon sources (icon/, from design-app-icon), DMG background and layout
  entitlements/                app and helper entitlements (from ungoogled-macos)
  downloads.ini                Chromium source tarball and Sparkle source tarball, each with sha512
  flags.macos.gn               ungoogled-macos flags + Clair flags (Sparkle on, arm64)
  version.txt                  Clair version, e.g. 0.1.0 (changed only by release commits)
  build.sh                     local and CI build entry point (based on ungoogled-macos)
  sign_and_package_app.sh      sign, notarize, staple, DMG (based on ungoogled-macos)
  scripts/                     append-appcast-item.sh (+ test), render-notes.sh, verify-app.sh
  .sparkle/                    appcast.xml, notes/{TEMPLATE.md,next.md,README.md,<version>.md}
  .github/workflows/           release.yml (chained), ci.yml (lint and script tests)
  LICENSE, LICENSE.ungoogled_chromium, CREDITS.md
```

`build.sh` applies ungoogled-chromium's own series first, then `patches/series`, using ungoogled's `utils/patches.py`.

**Alternatives considered:**
- Forking `ungoogled-chromium-macos`: rejected. Clair would inherit its release timing and x86_64 support, and every Clair change would conflict with theirs.
- Depending on Helium as a submodule: rejected. Clair should not depend on Helium's future.
- `git subtree`: rejected, because it makes the pinned engine tag harder to see and to bump.

### D2. Branding through Chromium's `BRANDING` file, plus name substitution

- `patches/clair/branding.patch` sets these in `chrome/app/theme/chromium/BRANDING`:
  - `PRODUCT_FULLNAME` / `PRODUCT_SHORTNAME` = Clair
  - `MAC_BUNDLE_ID` = `dev.joshuapark.Clair`
  - `MAC_TEAM_ID`
  - `COMPANY_*` and `COPYRIGHT`

  This produces `Clair.app`, `Clair Framework.framework` and `Clair Helper*.app`, with helper IDs derived from the bundle ID. The patch also extends ungoogled's `tweak_info_plist.py` change so the bundle ID is recognised.
- The Chromium-branded strings in `chromium_strings.grd` and related files are replaced at build time by Helium's `name_substitution.py`, rather than by hand-written string patches. Substitution keeps up with upstream string changes; patches would conflict on every Chromium version.
- The data directory and keychain service come from Helium's two small patches with "Clair" swapped in, giving `~/Library/Application Support/Clair` and "Clair Safe Storage".
- The icon and the in-app logos come from the `design-app-icon` change. During `prepare`, `scripts/replace-icon-resources.sh` does this step. `scripts/compile-icon.sh` compiles `resources/icon/AppIcon.icon` with `actool` into `Assets.car` and `app.icns`, which replace Chromium's files in `chrome/app/theme/chromium/mac/`. Every entry in `resources/icon/product-logos.txt` is then copied over its Chromium file, as Helium's resource list does. Nothing compiled is committed. If that change hasn't landed yet, the same step runs with whatever icon source is in `resources/icon/`.

### D3. Separate Clair version, with the Chromium version kept internally

- Adapted from Helium's `add-helium-versioning.patch`:
  - `CFBundleShortVersionString` = `version.txt`
  - `CFBundleVersion` = build number
  - `version_info` gains Clair's version and build number, for the About page and `chrome://version`
  - everything that websites or extensions see (user agent, client hints, `minimum_chrome_version`) still uses the Chromium version
- **Build number** = `git rev-list --count` of the release commit, as in Front Row. It is passed to GN as an argument and is never stored. A build from the release tag reproduces the same number. Local builds use the count of `HEAD`.
- Chromium's own `UpgradeDetector` and installed-version code compare bundle versions. Helium's Sparkle glue already moves these to Sparkle's view (`get_installed_version_mac.mm`). Clair keeps that behaviour.

**Alternative considered:** setting `CFBundleShortVersionString` to the Chromium version, as Chromium does. Rejected, because the spec requires the Clair version scheme, and Sparkle's display version must be Clair's.

### D4. Sparkle 2 built from source with a headless driver; updates appear in the Clair menu

- Clair takes Helium's Sparkle patch set: the ReBel glue, Sparkle 2 integration, and the default updater turned off. Sparkle is built from the pinned source tarball listed in `downloads.ini`, so no prebuilt binary is checked in.
- `SUFeedURL` = `https://github.com/itsjoshpark/Clair/raw/main/.sparkle/appcast.xml`.
- `SUPublicEDKey` comes from a GN argument.
- `SUEnableAutomaticChecks` = YES, with automatic download and install on quit turned on, and no user-facing settings.
- The headless driver means Sparkle never shows windows.
- A new `patches/clair/update-menu.patch` adds to the Clair menu (`main_menu_builder.mm` / `app_controller_mac.mm`):
  - **Check for Updates…**: always present. It starts a user-initiated check and shows an `NSAlert`: up to date, check failed, or "Clair X.Y.Z is ready" with **Install and Relaunch** / **Later**.
  - **Install Update and Relaunch**: present only while the Sparkle glue reports a downloaded update.
- **Relaunch** goes through Chromium's own graceful relaunch (`chrome::AttemptRelaunch`), which brings back the previous session. Chromium's quit flow already asks for confirmation about active downloads and warns that incognito windows won't reopen. Sparkle is told to postpone its own relaunch until Chromium's shutdown finishes (Helium already does this in `application_lifetime_desktop.cc`).
- **About page:** the Sparkle status UI is removed or hidden in `chrome://settings/help` (`version_updater_mac.mm`), so it shows versions only.
- **The sidebar update banner** belongs to the MVP change. The glue exposes "update ready" state that the banner can observe later.

**Alternatives considered:**
- Sparkle's standard UI with dialogs and release notes: rejected by product choice, which is Arc-style.
- Chromium's three-dot-menu relaunch badge: it goes away when the toolbar is removed in the MVP, so it isn't the main place updates appear. It is harmless to keep for now.
- A prebuilt Sparkle framework: rejected, to keep the build reproducible from source and consistent with Helium.

### D5. Release pipeline: chained jobs, with the release commit made in the final job

The chained build lives in its own reusable workflow, `build.yml`: a fetch job, then phases 1–20, each a call to `build-phase.yml`, then a result check. It runs on every pull request that touches build inputs, which makes GitHub Actions the project's build machine; the development machine never builds Chromium. A pull request build ends with a headless smoke test and an unsigned app artifact. `release.yml` calls the same `build.yml`.

`release.yml` is triggered manually, with `bump` (patch, minor or major) and `dry_run` inputs, and uses `concurrency: release` so only one release runs at a time.

```
validate ──> fetch ──> build-01 ──> build-02 ── … ──> build-NN ──> package ──> publish
   |            |          |  (each job: restore out/, ninja with timeout,     |         |
   |            |          |   upload partial out/, report finished|running)    |         |
   v            v          v                                                    v         v
version,     source +   skipped once                                    sign, notarize,  (non-dry-run)
build no.,   patches    build has                                       staple, DMG,     release commit,
notes check  packed     finished                                        deltas,          tag, GitHub
                                                                        sign_update      Release, push
                                                                                         main last
```

- **validate:**
  - works out the new version from the latest `v*` tag and the `bump` input
  - sets build number = `rev-list --count HEAD` + 1, since the release commit will be the next commit
  - checks that the build number is greater than the newest appcast entry
  - checks that `.sparkle/notes/next.md` exists and differs from the template, and that `<version>.md` doesn't exist yet
  - writes the results as job outputs
- **fetch:**
  - downloads the Chromium tarball and Sparkle source
  - prunes, patches and domain-substitutes them
  - writes `args.gn`, with the version, build number and Sparkle key as GN args
  - packs everything as an artifact, following ungoogled-macos's `retrieve-resources` job
- **build-01…NN:**
  - each job runs `timeout` ninja, leaving about an hour for setup and upload
  - each job uploads the partial `out/` compressed with zstd
  - a job is skipped once an earlier one reports `finished`
  - NN starts at 20, as ungoogled-macos does, and is tuned after the first measured runs
- **package:**
  - signs every helper and the Sparkle framework's `Autoupdate`/`Updater.app` individually with the hardened runtime and their entitlements, never using `--deep`
  - notarizes with `notarytool` and staples the app
  - builds the DMG, then signs, notarizes and staples the DMG
  - runs `scripts/verify-app.sh`
  - downloads the DMGs of the last three releases and makes `BinaryDelta` files
  - signs every asset with `sign_update`
  - dry run: uploads the DMG as a workflow artifact and stops
- **publish:**
  - creates the release commit (version and archived notes) in the Front Row way: `version.txt`, `.sparkle/notes/<version>.md`, a new `next.md` from the template, and the appcast entry from `append-appcast-item.sh`, extended for `<sparkle:deltas>` and a minimum system version of 15.6
  - tags it `v<version>`
  - creates the GitHub Release with the DMG, deltas, SHA-256 checksums and notes (Clair version, build number, ungoogled-chromium tag)
  - pushes to `main` only after the Release exists
  - before pushing, checks that `main` hasn't moved since `validate`. If it has, it aborts before creating the Release, so the appcast never points at missing files.
- `sign_update`, `BinaryDelta` and `generate_keys` come from the Sparkle **release tarball** for the same pinned version, checked against its sha512.

**Alternatives considered:**
- One job on a larger or self-hosted runner: rejected. It needs a paid plan or hardware, and the spec requires standard hosted runners.
- `sccache` or remote build execution: deferred. It needs paid storage.
- Committing the version before the build: rejected. A failed build would leave a released-looking commit on `main`.

### D6. Signing, notarization and secrets

The following are GitHub Actions secrets:
- the Developer ID Application certificate as base64 `.p12`, and its password
- a CI keychain password
- notarization credentials: an App Store Connect API key (key ID, issuer, `.p8`)
- `SPARKLE_ED_PRIVATE_KEY`

Handling:
- The Sparkle key is generated once, locally, with `generate_keys`. Its public half is committed as a GN default. The private half goes into the secret and into an offline backup.
- Scripts pass secrets only through stdin or temporary keychains, never as command-line arguments, and run with `set +x` around any step that uses them.

### D7. Verification

- **`scripts/verify-app.sh`** runs in `package`. It fails the release on any static check from the specs:
  - bundle and helper IDs
  - `LSMinimumSystemVersion` is 15.6
  - every Mach-O is arm64 only (checked with `lipo`)
  - `codesign --verify --strict`, `spctl --assess` and `stapler validate` pass
  - `SUFeedURL` and `SUPublicEDKey` are present
  - no "Chromium" in `CFBundleName`
- **Runtime checks**, as a manual release checklist in `.sparkle/notes/README.md` or `docs/release-checklist.md`:
  - user-agent version
  - the "Clair Safe Storage" keychain item
  - data directory isolation when running alongside Chromium
  - installing a CRX through the flag
  - no Google traffic, checked with `--log-net-log` and a host filter
  - the update flow, end to end, using a dry-run DMG and a test appcast

### D8. Attribution and licensing

- Each copied patch keeps its original header. Clair's changes to it are marked.
- `CREDITS.md` lists ungoogled-chromium, ungoogled-chromium-macos, Helium, ReBel, Sparkle and Front Row's release scripts, with their licenses.
- `third_party/sparkle/README.chromium`, from Helium's patch, makes Sparkle appear in `chrome://credits`.
- The combined work is GPLv3. Code from BSD-3 and MIT sources keeps its own license.

## Risks / Trade-offs

- **[Risk] Runner disk:** 14 GB is listed for the runner, while a Chromium checkout plus a partial `out/` is far larger, so the build may run out of disk.
  Measured on the first PR build (`macos-26`, 2026-10-26): the volume is 320 GB with 96 GB free at the start and 147 GB free after `prepare-runner.sh`. The fetched and patched build directory is 17.4 GB, which zstd compresses to a 6.0 GB artifact. The fetch job took 38 minutes.
  → Delete the preinstalled SDKs (Android, extra Xcodes, simulators) as ungoogled-macos does, and turn off Spotlight. Measure free space in the first dry run. Fallback: build `out/` on an external volume where it's available, or reduce `symbol_level`.
- **[Risk] Partial `out/` artifacts:** these may run into artifact size or storage limits; storage for public repos isn't documented.
  → Use zstd compression and keep only one partial artifact at a time (`overwrite: true`). Watch the first runs. Fallback: split the artifact.
- **[Risk] Build time:** about 8–12 hours on 3-core runners, so a security release reaches users about half a day after its tag.
  → Accepted for now. Remote build execution or caching is a later improvement.
- **[Risk] `main` moves during a long release.**
  → `concurrency: release`, plus the publish job's check that `main` hasn't moved before creating the Release. Avoid pushing to `main` while a release runs.
- **[Risk] Helium's Sparkle and versioning patches stop applying** on a new Chromium version.
  → They live in Clair's tree, so Clair can fix them without waiting for Helium. Helium's upstream fixes are a reference.
- **[Risk] The Sparkle private key is lost or leaked.** Losing it strands every installed copy; leaking it lets someone else push updates.
  → Keep an offline backup. The key exists only in the secret store and the backup. If it's lost, the only recovery is asking users to reinstall by hand, so the backup is essential.
- **[Trade-off] Extensions:** without Web Store URLs, extension installs work but feel clumsy in this release.
  → Accepted for change 1. The MVP decides on Web Store support.
- **[Trade-off] Rollback:** Sparkle never downgrades.
  → Roll back by shipping a newer build with the problem reverted.

## Migration Plan

- This is the first release, so there is nothing to migrate.
- Steps before the first release:
  1. generate the Sparkle keys and store them in secrets and the backup
  2. add the Apple secrets
  3. run a dry run and fix the build, disk and notarization
  4. do the manual runtime checklist on the dry-run DMG
  5. write `next.md` and release `0.1.0`
- The update path is first exercised by `0.1.1`, which tests deltas once earlier releases exist. Before that, test it with a dry run against a private test appcast.

## Open Questions

- The right number of chained build jobs (NN) and the real build time on `macos-latest`. Tuned after the first measured dry runs.
