# Spec Delta

## Purpose

Defines how a Clair release is produced and published. It covers building, signing and notarizing the app, packaging it, publishing it to GitHub Releases, and announcing it to installed copies through the appcast, so that each release can be installed and trusted on a clean Mac.

## ADDED Requirements

### Requirement: Signed and notarized disk image
Each release SHALL be distributed as a DMG containing `Clair.app` and a shortcut to `/Applications`. The app SHALL be signed with Clair's Developer ID Application certificate using the hardened runtime. The app and the DMG SHALL be notarized by Apple, with the notarization ticket stapled to both.

#### Scenario: Opening the download on a clean Mac
- **WHEN** a user downloads the release DMG with a browser on a Mac that has never run Clair, opens it, drags `Clair.app` to Applications and launches it
- **THEN** macOS opens Clair after only the standard "downloaded from the internet" confirmation, with no warning about an unidentified developer or malware

#### Scenario: Gatekeeper assessment
- **WHEN** `spctl --assess --type execute` is run on the shipped `Clair.app`, and `stapler validate` on the app and the DMG
- **THEN** all checks pass and identify Clair's Developer ID team

### Requirement: GitHub release per version
Each release SHALL be published as a GitHub Release on `itsjoshpark/Clair`, tagged `v<version>` (for example `v0.1.0`). The release SHALL include:
- the DMG
- the delta update files
- SHA-256 checksums for every asset
- release notes that state the Clair version, the build number and the ungoogled-chromium version

#### Scenario: Release page contents
- **WHEN** a user opens the GitHub Release for `v0.1.0`
- **THEN** it shows the release notes, the Clair version and build number, the ungoogled-chromium version, the DMG, and a checksum for each asset

#### Scenario: Tag matches shipped source
- **WHEN** the source at tag `v0.1.0` is built
- **THEN** it reports version `0.1.0` and the same build number and engine version as the published release

### Requirement: Appcast published after release assets
The appcast entry for a release SHALL be published to `main` only after the GitHub Release and all its assets exist. No published appcast entry may point to a missing file.

#### Scenario: Failed release leaves the appcast unchanged
- **WHEN** a release run fails before the GitHub Release and its assets are fully uploaded
- **THEN** `.sparkle/appcast.xml` on `main` is unchanged, and installed copies are not offered the failed release

#### Scenario: Appcast entry links resolve
- **WHEN** any appcast entry on `main` is followed
- **THEN** its full download and each delta download resolve to an existing asset on a GitHub Release

### Requirement: Appcast entry contents
Each appcast entry SHALL include:
- the build number and the display version
- a minimum macOS version of 15.6
- a link to the full DMG with its EdDSA signature and length
- delta entries with signatures for up to the three previous releases
- the release notes as HTML

#### Scenario: New release with deltas
- **WHEN** a release is published after at least three earlier releases
- **THEN** its appcast entry lists delta updates from each of the three previous build numbers, each with its own EdDSA signature

### Requirement: Release validation before publishing
The release process SHALL refuse to publish, and change nothing, when any of these is true:
- the new build number is not greater than the newest appcast entry
- the release notes file is missing or is still the unedited template
- archived notes for that version already exist

#### Scenario: Build number not increasing
- **WHEN** a release is started whose build number is not greater than the newest build number in the appcast
- **THEN** the release fails before building, with an error saying Sparkle would never offer it

#### Scenario: Missing release notes
- **WHEN** a release is started while `.sparkle/notes/next.md` is missing or still equals the template
- **THEN** the release fails before building, with an error asking for release notes

### Requirement: Manual release with version bump choice
A release SHALL be started manually, by choosing a patch, minor or major bump. The new version SHALL be derived from the latest released version.

#### Scenario: Patch bump
- **WHEN** a release is started with a patch bump and the latest release is `0.1.0`
- **THEN** the new release is `0.1.1`

#### Scenario: Minor bump
- **WHEN** a release is started with a minor bump and the latest release is `0.1.3`
- **THEN** the new release is `0.2.0`

### Requirement: Build-only dry run
The release process SHALL offer a dry-run mode that builds, signs and notarizes the app but creates no tag, GitHub Release or appcast change.

#### Scenario: Dry run
- **WHEN** a dry-run release is started
- **THEN** a signed, notarized DMG is available as a workflow artifact, and no tag, release or appcast change is made

### Requirement: Pull request builds run on GitHub-hosted runners
Builds triggered by pull requests SHALL run on standard GitHub-hosted macOS arm64 runners. They MUST NOT run on a self-hosted runner, and MUST NOT need paid build services.

#### Scenario: Pull request build
- **WHEN** a pull request triggers a build
- **THEN** every job in that build runs on a standard GitHub-hosted macOS runner

### Requirement: Release builds run on the owner's self-hosted runner
Release builds SHALL run on the repository owner's self-hosted Mac runner (label `clair-release`). Only manually started release runs from `main` MAY use that runner. Jobs from fork pull requests MUST NOT run on it.

#### Scenario: Release run
- **WHEN** the owner starts a release from `main`
- **THEN** its build, package and publish jobs run on the `clair-release` self-hosted runner

#### Scenario: Fork pull request
- **WHEN** a pull request from a fork changes a workflow to target the `clair-release` label
- **THEN** no job from that pull request runs on the self-hosted runner without the owner's approval

### Requirement: Secrets never exposed
Signing certificates, notarization credentials and the Sparkle EdDSA private key SHALL be provided only as encrypted secrets of a `release` environment that is limited to `main`. They MUST NOT appear in the repository, in build logs, in any published artifact, or on the self-hosted runner's disk after a job ends.

#### Scenario: Inspecting a release's logs and assets
- **WHEN** a release run's logs and every published asset are searched for the private key or the certificate password
- **THEN** neither is found
