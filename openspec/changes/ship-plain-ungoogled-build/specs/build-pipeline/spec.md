# Spec Delta

## Purpose

Defines how Clair is built and checked, so that most changes are checked in minutes, the expensive Chromium build runs only when Chromium's inputs change, and runtime regressions are caught before any release.

## ADDED Requirements

### Requirement: Engine key
The repository SHALL define an engine key: a hash computed from the contents of every input to the Chromium build, as listed in design D10. Files that are not Chromium build inputs MUST NOT affect the key.

#### Scenario: Engine input changes
- **WHEN** a commit changes a file in `patches/`
- **THEN** the engine key differs from the previous commit's key

#### Scenario: Native-only change
- **WHEN** a commit changes only Swift sources of the native layer
- **THEN** the engine key is the same as the previous commit's key

#### Scenario: Release commit
- **WHEN** the release commit changes `version.txt`, the release notes and the appcast
- **THEN** its engine key is the same as its parent's key

### Requirement: Prebuilt engines published per key
Each engine build SHALL be published as a GitHub prerelease named `chromium-engine-<key>`. It SHALL contain the built, unsigned Chromium app bundle, its SHA-256 checksum, and a manifest naming the key, the input files and their hashes, the ungoogled-chromium tag, the Chromium version and the toolchain versions. Packaging, quality checks and releases SHALL use the published engine for their commit's key, and MUST NOT compile Chromium themselves.

#### Scenario: App packaged from a prebuilt engine
- **WHEN** the quality checks run on a commit whose key is already published
- **THEN** they download `chromium-engine-<key>` and package the app without compiling any Chromium source

#### Scenario: Engine releases don't affect app releases
- **WHEN** an `chromium-engine-<key>` prerelease is published
- **THEN** it is not the repository's latest release, and the release tooling's version calculation ignores it

### Requirement: Engine builds run on the owner's Mac when started by the owner
Chromium SHALL be compiled only on the repository owner's self-hosted Mac runner (label `clair-release`), in a run that the owner starts by hand on one of the repository's branches, or in a release. No pull request event MAY start a job on that runner. A build whose engine key is already published SHALL stop without rebuilding.

#### Scenario: Owner builds an engine for a branch
- **WHEN** the owner starts the engine build for a branch whose key has no published engine
- **THEN** the self-hosted Mac builds it with the release build settings, runs the headless smoke test, and publishes `chromium-engine-<key>`

#### Scenario: Engine already published
- **WHEN** the engine build is started for a key that is already published
- **THEN** it finishes without compiling and reports the existing engine

#### Scenario: Fork pull request
- **WHEN** a pull request from a fork changes a workflow to target the `clair-release` label
- **THEN** no job from that pull request runs on the self-hosted runner

### Requirement: Incremental engine rebuilds
When the ungoogled-chromium pin is unchanged and only Clair's patches or overlay change, the engine build SHALL reuse the owner's Mac's existing source tree and build output, so that only the affected targets recompile. When it can't establish that the existing tree matches the previous key's inputs, it SHALL rebuild from a fresh source tree.

#### Scenario: Patch fix
- **WHEN** an engine build starts after only one Clair patch changed since the workspace's last build
- **THEN** the build reuses the workspace and recompiles only the targets affected by that patch

#### Scenario: Unknown workspace state
- **WHEN** the workspace's recorded key is missing, or its inputs can't be reverted cleanly
- **THEN** the build starts from a fresh source tree, and the published engine still matches its key

### Requirement: Fast merge gate
Every pull request SHALL run a merge gate on GitHub-hosted runners that compiles no Chromium source. The gate covers the script tests, shellcheck, actionlint, and the native layer's build and unit tests against the contract header. The gate SHALL be the set of required checks for merging into `main`. For a pull request that doesn't change the engine key, the gate SHALL finish within 10 minutes.

#### Scenario: Native-only pull request
- **WHEN** a pull request changes only the native layer's Swift sources
- **THEN** its checks finish within 10 minutes, and no job fetches Chromium source

### Requirement: Patch check for engine changes
A pull request that changes the engine key SHALL also run a patch check on a GitHub-hosted runner. The check fetches the pinned Chromium source and applies ungoogled-chromium's series, Clair's series, the overlay and domain substitution, without compiling. Such a pull request SHALL NOT merge until its patch check passes and `chromium-engine-<key>` is published for its head commit's key.

#### Scenario: Patch no longer applies
- **WHEN** a pull request bumps the ungoogled-chromium tag and one Clair patch no longer applies
- **THEN** the patch check fails and names that patch

#### Scenario: Engine not yet built
- **WHEN** an engine pull request's patch check passes but its engine has not been published
- **THEN** the engine check fails with a message naming the key and the command to build it, and the pull request can't merge

### Requirement: Quality checks after merge
Every push to `main` SHALL run quality checks on a GitHub-hosted runner. They package the app from the published engine and the commit's native layer, run the static app checks, and run the automated runtime suite against the packaged app. The checks MAY also be started by hand on any branch. They SHALL NOT block merging. A failure on `main` SHALL be reported in a GitHub issue that names the commit, the failing tests and the run, so the failure can be assigned and fixed.

#### Scenario: Regression on main
- **WHEN** a merged commit breaks a runtime test
- **THEN** the quality run for that commit fails, and an open `quality-failure` issue names the commit, the failing test and the run link

#### Scenario: Runtime suite contents
- **WHEN** the quality checks run
- **THEN** the runtime suite covers at least: launch and page rendering, the Clair application menu items, the data directory and keychain item, the user agent's Chromium version, the About page versions, no Google service traffic on an idle first launch, a manual update check against local test appcasts, and session restore after a relaunch

### Requirement: Releases need passing quality checks
A release SHALL ship only a commit whose quality checks have passed. The release process SHALL run the quality checks for its commit when they haven't already passed, and SHALL stop if they fail or haven't finished. If no engine is published for the release commit's key, the release SHALL build it on the owner's Mac first.

#### Scenario: Quality checks failed
- **WHEN** a release is started on a commit whose quality checks failed
- **THEN** the release stops before packaging, with no tag, GitHub Release or appcast change

#### Scenario: Engine missing at release
- **WHEN** a release is started on a commit whose engine key has no published engine
- **THEN** the release builds and publishes the engine, runs the quality checks against it, and continues only if they pass
