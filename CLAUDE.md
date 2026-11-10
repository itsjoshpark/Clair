# Clair

Clair is a macOS web browser in the style of Arc, built on ungoogled-chromium. It targets Apple Silicon only, with macOS 15.6 as the minimum. Its interface is native AppKit/SwiftUI in Crest's style (`pauljoda/Crest`): a Swift framework, `ClairUI`, that Chromium loads at start-up, with WebUI only for Chromium's internal pages. Change 1 uses it only for Sparkle 2 updates, the update menu and the About window. The UX spike (roadmap step 2 in change 1's `proposal.md`) replaces Chromium's window with a native one.

Leave ungoogled-chromium alone as much as possible. Patches to existing Chromium files are for build fixes, identity, versioning and hooks only. Put new behavior in `ClairUI` or in new files under `overlay/`.

## Planning: OpenSpec

The work is planned as OpenSpec changes in `openspec/changes/<name>/`, each with `proposal.md`, `design.md`, `specs/` and `tasks.md`. Change 1, `ship-plain-ungoogled-build`, is archived in `openspec/changes/archive/2026-11-05-ship-plain-ungoogled-build/`: its `proposal.md` holds the product decisions, the roadmap and the MVP feature list, and its `arc-reference/` the Arc behavior references. Its capability specs are in `openspec/specs/`. Arc stops working on 2026-12-22.

When work needs a change, following OpenSpec's own guidance:

- **A change is required for:** new features or behavior; breaking changes (the `ClairHost.h` contract, data formats, identifiers); architecture changes or new patterns; performance work that changes behavior; security changes; anything that takes several steps or touches several systems, such as `ClairUI` and the engine.
- **No change is needed for:** bug fixes that restore specified behavior; typos, formatting and comments; non-breaking dependency updates; configuration and environment changes; tests for existing behavior; documentation fixes. Such work may still correct a spec directly where it was wrong.

- Read the relevant change's proposal, design and specs before implementing anything.
- Mark a task `- [x]` only once its stated verification has passed. For anything that needs a build, that means the CI build passing.
- If implementation contradicts the specs or design, update those artifacts rather than drifting from them silently.

## Building: engine and app

Never fetch Chromium or build it by hand on the development machine; only `engine.yml` builds it. The build is split in two (design D9–D12 of change 1):

- **Engine:** the patched Chromium. `scripts/engine-key.sh` hashes its inputs (ungoogled pin, `downloads.ini`, GN flags, `patches/`, `overlay/`, `utils/`, `native/ClairHost.h`, compiled-in branding, build scripts) into a key. `engine.yml` builds it only on the owner's self-hosted Mac (label `clair-release`, M1 Pro with 32 GB, internal disk), when the owner starts it, and publishes the prerelease `chromium-engine-<key>`. The Mac keeps its workspace, so a patch fix rebuilds incrementally. To rebuild after a fix: push the branch, then `gh workflow run engine.yml -f ref=<branch>`, and read the log. That runs `main`'s `engine.yml` against the branch; when the branch changes `engine.yml` itself, add `--ref <branch>`.
- **App:** `ClairUI`, packaging, signing and Sparkle. It builds in minutes against the prebuilt engine for the current key.
- **Merge gate** (`ci.yml`, required, minutes): the `scripts/*.test.sh` tests, `shellcheck -S warning`, `actionlint`, `openspec validate --all --strict`, `ClairUI`'s build and unit tests, and the engine check. A PR that changes the engine key also runs the patch check (`./build.sh fetch prepare` on a hosted runner, about 20 minutes) unless its engine is already published, and its engine check fails until that engine is published; `engine.yml` then re-runs it.
- **Quality checks** (`quality.yml`): run after every merge to `main`. They package the app from the engine and run the runtime suite in `tests/runtime/`. A failure opens a `quality-failure` issue; fix it from there. No release ships with quality checks failing or unfinished.
- **Patch check** (the `Patch check` job in `ci.yml`): runs only when a PR changes the engine key and `chromium-engine-<key>` isn't published yet. No hosted workflow compiles Chromium.
- The self-hosted Mac never runs pull request jobs, especially not fork PRs. Release secrets live in the `release` environment, and engine builds and quality checks never see them. Never run `.github/scripts/prepare-runner.sh` on the self-hosted runner: it deletes Xcode versions and simulators.
- Every macOS job and the self-hosted Mac use Xcode 27 (hosted runner label `xcode-27`).
- Read job logs with `gh run view --job <id> --log`, or with `gh api --allow-escape-sequences repos/itsjoshpark/Clair/actions/jobs/<id>/logs`. Fix what they show, then push.

To run the current `ClairUI` against the published engine for the checkout, use `scripts/run-local.sh` (see `docs/building.md`). It launches Clair with a throwaway profile and the mock keychain. The runtime suite (`tests/runtime/run.sh`) may also run locally, but it deletes the current user's Clair data, keychain item and preferences; hosted runners remain the default. The owner prefers few external packages on the development machine: ask before adding one.

### Comparing with Arc and driving the UI

To compare Clair with Arc, or check a UI change by hand, drive both apps with XCUITest rather than synthetic mouse events, which Arc ignores:

- Write a throwaway UI-testing bundle in the scratchpad (a copy of `tests/runtime/ClairRuntimeTests.xcodeproj` with one test that reads steps from a file) and run it with `xcodebuild test-without-building`. `XCUIApplication(bundleIdentifier:)` attaches to a running app: Arc is `company.thebrowser.Browser`. Hover, click, drag and `typeKey` all work on Arc; a drag that misses its sidebar edge moves the window.
- XCUITest only finds Clair when Launch Services knows the running copy: launch the `run-local.sh --no-launch` package with `open -n <app> --args --user-data-dir=<profile> --use-mock-keychain --no-first-run --no-default-browser-check`, and unregister stale copies (`lsregister -dump` lists them; old DMG mounts, delta tests and the runner's build dir pile up), or it reports "does not have a process ID".
- The first XCUITest run and the first debugger attach each show a macOS permission prompt on the owner's screen. Ask the owner to approve it rather than waiting on a hung run, and never kill an attached `lldb`: that kills the app.
- Measure from accessibility frames (`AXPosition`/`AXSize` through a small Swift script) and from `screencapture -l <window id>`; an XCUITest window screenshot captures only the web content. Record animations with `screencapture -v -V <s> -R <rect>` and step through frames with `AVAssetImageGenerator`.
- Don't commit the screenshots or recordings.

## Git and PRs

- Use Conventional Commits (`feat:`, `fix:`, `build:`, `ci:`, `docs:`, `chore:`…) for commits and PR titles. The PR title becomes the squash commit message.
- Work on a branch and open a PR. Never push to `main`.
- A user-facing change adds a Changie fragment in the same PR (`changie new`). CI, refactors and docs don't.
- **Every push to a PR that changes the engine key cancels the patch check in progress** and, unless that key's engine is published by then, starts it again, including docs-only pushes, because the check compares the whole PR's key with its base's. To avoid the wait, build the engine first and push docs afterwards. A push never affects an `engine.yml` run, which checks out its branch when it starts.
- A PR that changes `ClairUI` views the runtime suite drives also runs the quality checks on its branch before merging (`gh workflow run quality.yml --ref <branch>`): a view hidden in #92 left the accessibility tree and broke `main`'s suite. Start them together with CI on the last push, with every note in that push, and don't push again while checks run, since every push re-runs CI.
- Once a PR's checks pass (CI, plus Build and quality when they ran), squash-merge it with `gh pr merge --squash --delete-branch`. Then switch to `main`, pull, and delete the local branch.
- After an OpenSpec change's implementation PR merges, one docs-only PR finishes it: it ticks the quality task (and any other task the implementation PR's last checks verified), syncs the change's delta specs and archives the change. Don't push to the implementation PR just to tick tasks.

## Repository layout

- `ungoogled-chromium/`: a submodule pinned to an ungoogled-chromium tag. Bump the tag to update the engine.
- `patches/series`: Clair's patch series, applied after ungoogled's. Paths in it are relative to `patches/`:
  - `ungoogled-chromium-macos/`: copied from ungoogled-chromium-macos
  - `helium/`: adapted from Helium (GPLv3)
  - `clair/`: Clair's own patches

  Keep original patch headers.
- `overlay/`: new Chromium source files at their paths in the Chromium tree, copied in after the patches. Only new files; edits to existing files are patches.
- `native/`: `ClairHost.h` (the contract between Chromium and `ClairUI`), the `ClairUI` Xcode project (JSON format, `project.xcproj`, Xcode 27.2 or later) and the Swift sources and unit tests.
- `package.sh`: turns an engine into `Clair.app`: embeds `ClairUI` and Sparkle, writes the version and Sparkle keys into `Info.plist`, signs, and builds the DMG.
- `build.sh`: the staged engine build (`fetch`, `prepare`, `configure`, `compile`), used by `engine.yml` and the patch check. See `docs/building.md`.
- `tests/runtime/`: the runtime suite (XCUITest and the Chrome DevTools Protocol) that `quality.yml` runs. It deletes Clair's data for the current user, so it runs on hosted runners by default, and locally only when losing that data is fine.
- `.github/scripts/`: CI helpers (runner preparation, packing and unpacking the build directory, the smoke test).
- `scripts/`: release tooling (appcast entries, deltas, release notes rendering, release preflight), each with a `*.test.sh`.
- `.sparkle/`: `appcast.xml`, served from `main` as Sparkle's feed.
- `.changes/`: release notes as [Changie](https://changie.dev) fragments, configured in `.changie.yaml`. Each release's notes end up in `.changes/<version>.md` and `CHANGELOG.md`. See `.changes/README.md`.

## Identifiers: never change these

- Bundle ID: `dev.joshuapark.Clair`
- Data folder: `~/Library/Application Support/Clair`
- Keychain item: "Clair Safe Storage"
- Sparkle feed: `https://github.com/itsjoshpark/Clair/raw/main/.sparkle/appcast.xml`
- Version scheme: `0.y.z` until the MVP, which becomes `1.0.0`. The build number is the commit count. The Chromium version stays what websites and extensions see.

## Scripts

Shell scripts target macOS: `/bin/bash` 3.2 and the BSD userland. Validate inputs that end up in XML or shell, and keep each script's test file up to date.
