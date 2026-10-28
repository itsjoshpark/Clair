# Clair

Clair is a macOS web browser in the style of Arc, built on ungoogled-chromium. It targets Apple Silicon only, with macOS 15.6 as the minimum. How its UI is built is still open: C++ Views and WebUI with Objective-C++ for native macOS behavior, native AppKit or SwiftUI views inside Chromium's window, or a fully native window like Crest's. The UX spike (roadmap step 2 in the active change's `proposal.md`) decides. Swift is allowed. Updates use Sparkle 2.

## Planning: OpenSpec

The work is planned as OpenSpec changes in `openspec/changes/<name>/`, each with `proposal.md`, `design.md`, `specs/` and `tasks.md`. Product decisions, the roadmap and the MVP feature list are in the active change's `proposal.md`. Arc behavior references are in its `arc-reference/`. Arc stops working on 2026-12-22.

- Read the relevant change's proposal, design and specs before implementing anything.
- Mark a task `- [x]` only once its stated verification has passed. For anything that needs a build, that means the CI build passing.
- If implementation contradicts the specs or design, update those artifacts rather than drifting from them silently.

## Building: GitHub Actions is the build machine

Never fetch Chromium or build it on the development machine, which is resource-limited. Builds run in GitHub Actions on pull requests:

- `build.yml` runs one fetch job (`./build.sh fetch prepare`, the patch-only mode), then up to 20 chained compile phases through `build-phase.yml`, each one under the 6-hour job limit. The finishing phase runs a headless smoke test and uploads an unsigned app artifact. A full build takes many hours.
- `ci.yml` runs on every push and PR: the `scripts/*.test.sh` tests, `shellcheck -S warning` and `actionlint`.
- Release builds run on the owner's self-hosted Mac runner (label `clair-release`, M1 Pro with 32 GB, external SSD). Only manually started releases from `main` may target it, never pull requests, and especially not fork PRs. Release secrets live in the `release` environment. Never run `.github/scripts/prepare-runner.sh` on the self-hosted runner: it deletes Xcode versions and simulators.
- Read job logs with `gh run view --job <id> --log`, or with `gh api --allow-escape-sequences repos/itsjoshpark/Clair/actions/jobs/<id>/logs`. Fix what they show, then push.

Local work is limited to editing files and running the small script tests.

## Git and PRs

- Use Conventional Commits (`feat:`, `fix:`, `build:`, `ci:`, `docs:`, `chore:`…) for commits and PR titles. The PR title becomes the squash commit message.
- Work on a branch and open a PR. Never push to `main`.
- **Every push to an open PR restarts its build** and cancels the one in progress, including docs-only pushes, because `paths-ignore` compares the whole PR diff. While a build is running, keep small follow-ups (task checkmarks, notes) as local commits or on a follow-up branch.
- Once a PR's checks pass (CI, plus Build when it ran), squash-merge it with `gh pr merge --squash --delete-branch`. Then switch to `main`, pull, and delete the local branch.

## Repository layout

- `ungoogled-chromium/`: a submodule pinned to an ungoogled-chromium tag. Bump the tag to update the engine.
- `patches/series`: Clair's patch series, applied after ungoogled's. Paths in it are relative to `patches/`:
  - `ungoogled-chromium-macos/`: copied from ungoogled-chromium-macos
  - `helium/`: adapted from Helium (GPLv3)
  - `clair/`: Clair's own patches

  Keep original patch headers, and credit sources in `CREDITS.md`.
- `build.sh`: the staged build (`fetch`, `prepare`, `configure`, `compile`), used both locally and in CI. See `docs/building.md`.
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
