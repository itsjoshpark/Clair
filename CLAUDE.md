# Clair

Clair is a macOS web browser in the style of Arc, built on ungoogled-chromium. It targets Apple Silicon only, with macOS 15.6 as the minimum. Its interface is native AppKit/SwiftUI in Crest's style (`pauljoda/Crest`): a Swift framework, `ClairUI`, that Chromium loads at start-up, with WebUI only for Chromium's internal pages. Change 1 uses it only for Sparkle 2 updates and the update menu. The UX spike (roadmap step 2 in the active change's `proposal.md`) replaces Chromium's window with a native one.

Leave ungoogled-chromium alone as much as possible. Patches to existing Chromium files are for build fixes, identity, versioning and hooks only. Put new behavior in `ClairUI` or in new files under `overlay/`.

## Planning: OpenSpec

The work is planned as OpenSpec changes in `openspec/changes/<name>/`, each with `proposal.md`, `design.md`, `specs/` and `tasks.md`. Product decisions, the roadmap and the MVP feature list are in the active change's `proposal.md`. Arc behavior references are in its `arc-reference/`. Arc stops working on 2026-12-22.

- Read the relevant change's proposal, design and specs before implementing anything.
- Mark a task `- [x]` only once its stated verification has passed. For anything that needs a build, that means the CI build passing.
- If implementation contradicts the specs or design, update those artifacts rather than drifting from them silently.

## Building: engine and app

Never fetch Chromium or build it on the development machine, which is resource-limited. The build is split in two (design D9–D12 of the active change):

- **Engine:** the patched Chromium. `scripts/engine-key.sh` hashes its inputs (ungoogled pin, `downloads.ini`, GN flags, `patches/`, `overlay/`, `utils/`, `native/ClairHost.h`, compiled-in branding, build scripts) into a key. `engine.yml` builds it only on the owner's self-hosted Mac (label `clair-release`, M1 Pro with 32 GB, external SSD), when the owner starts it, and publishes the prerelease `chromium-engine-<key>`. The Mac keeps its workspace, so a patch fix rebuilds incrementally. To rebuild after a fix: push the branch, then `gh workflow run engine.yml -f ref=<branch>`, and read the log.
- **App:** `ClairUI`, packaging, signing and Sparkle. It builds in minutes against the prebuilt engine for the current key.
- **Merge gate** (`ci.yml`, required, minutes): the `scripts/*.test.sh` tests, `shellcheck -S warning`, `actionlint`, and `ClairUI`'s build and unit tests. A PR that changes the engine key also runs the patch check (`./build.sh fetch prepare` on a hosted runner, about 40 minutes), and can't merge until its engine is published.
- **Quality checks** (`quality.yml`): run after every merge to `main`. They package the app from the engine and run the runtime suite in `tests/runtime/`. A failure opens a `quality-failure` issue; fix it from there. No release ships with quality checks failing or unfinished.
- **Until the first engine is published,** `build.yml` still runs PR #1's hosted chain: a fetch job, then up to 20 compile phases through `build-phase.yml`.
- The self-hosted Mac never runs pull request jobs, especially not fork PRs. Release secrets live in the `release` environment, and engine builds and quality checks never see them. Never run `.github/scripts/prepare-runner.sh` on the self-hosted runner: it deletes Xcode versions and simulators.
- Every macOS job and the self-hosted Mac use Xcode 27 (hosted runner label `xcode-27`).
- Read job logs with `gh run view --job <id> --log`, or with `gh api --allow-escape-sequences repos/itsjoshpark/Clair/actions/jobs/<id>/logs`. Fix what they show, then push.

Local work is limited to editing files, running the small script tests, and building `ClairUI` with Xcode against `native/ClairHost.h`.

## Git and PRs

- Use Conventional Commits (`feat:`, `fix:`, `build:`, `ci:`, `docs:`, `chore:`…) for commits and PR titles. The PR title becomes the squash commit message.
- Work on a branch and open a PR. Never push to `main`.
- **While PR #1's hosted chain is in use, every push to an open PR restarts its build** and cancels the one in progress, including docs-only pushes, because `paths-ignore` compares the whole PR diff. While a build is running, keep small follow-ups (task checkmarks, notes) as local commits or on a follow-up branch.
- Once a PR's checks pass (CI, plus Build when it ran), squash-merge it with `gh pr merge --squash --delete-branch`. Then switch to `main`, pull, and delete the local branch.

## Repository layout

- `ungoogled-chromium/`: a submodule pinned to an ungoogled-chromium tag. Bump the tag to update the engine.
- `patches/series`: Clair's patch series, applied after ungoogled's. Paths in it are relative to `patches/`:
  - `ungoogled-chromium-macos/`: copied from ungoogled-chromium-macos
  - `helium/`: adapted from Helium (GPLv3)
  - `clair/`: Clair's own patches

  Keep original patch headers, and credit sources in `CREDITS.md`.
- `overlay/`: new Chromium source files at their paths in the Chromium tree, copied in after the patches. Only new files; edits to existing files are patches.
- `native/`: `ClairHost.h` (the contract between Chromium and `ClairUI`), the `ClairUI` Xcode project (JSON format, `project.xcproj`, Xcode 27.2 or later) and the Swift sources and unit tests.
- `package.sh`: turns an engine into `Clair.app`: embeds `ClairUI` and Sparkle, writes the version and Sparkle keys into `Info.plist`, signs, and builds the DMG.
- `build.sh`: the staged engine build (`fetch`, `prepare`, `configure`, `compile`), used by `engine.yml` and the patch check. See `docs/building.md`.
- `.github/scripts/`: CI helpers (runner preparation, packing and unpacking the build directory, the smoke test).
- `scripts/`: release tooling (appcast entries with deltas, release notes rendering, version bump, release preflight), each with a `*.test.sh`.
- `.sparkle/`: `appcast.xml`, served from `main` as Sparkle's feed, and the `notes/` release-notes flow (`next.md`, `TEMPLATE.md`).

## Identifiers: never change these

- Bundle ID: `dev.joshuapark.Clair`
- Data folder: `~/Library/Application Support/Clair`
- Keychain item: "Clair Safe Storage"
- Sparkle feed: `https://github.com/itsjoshpark/Clair/raw/main/.sparkle/appcast.xml`
- Version scheme: `0.y.z` until the MVP, which becomes `1.0.0`. The build number is the commit count. The Chromium version stays what websites and extensions see.

## Scripts

Shell scripts target macOS: `/bin/bash` 3.2 and the BSD userland. Validate inputs that end up in XML or shell, and keep each script's test file up to date.
