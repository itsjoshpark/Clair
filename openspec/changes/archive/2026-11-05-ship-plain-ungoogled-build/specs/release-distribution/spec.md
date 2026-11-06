# Spec Delta

## Purpose

Defines how a Clair release is produced and published. It covers packaging, signing and notarizing the app, packaging it, publishing it to GitHub Releases, and announcing it to installed copies through the appcast, so that each release can be installed and trusted on a clean Mac.

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
- release notes that state the Clair version, the build number, the ungoogled-chromium version and the engine key

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
- `.changes/unreleased/` holds no Changie fragments
- `.changes/<version>.md` or the tag `v<version>` already exists

#### Scenario: Build number not increasing
- **WHEN** a release is started whose build number is not greater than the newest build number in the appcast
- **THEN** the release fails before building, with an error saying Sparkle would never offer it

#### Scenario: Missing release notes
- **WHEN** a release is started while `.changes/unreleased/` holds no fragments
- **THEN** the release fails before building, with an error asking for fragments

### Requirement: Manual release with version bump choice
A release SHALL be started manually, by choosing auto, patch, minor or major. The new version SHALL be derived from the latest released version. With auto, a `New` fragment SHALL bump the minor version, and fragments of any other kind SHALL bump the patch version.

#### Scenario: Patch bump
- **WHEN** a release is started with a patch bump and the latest release is `0.1.0`
- **THEN** the new release is `0.1.1`

#### Scenario: Minor bump
- **WHEN** a release is started with a minor bump and the latest release is `0.1.3`
- **THEN** the new release is `0.2.0`

#### Scenario: Auto bump with a new feature
- **WHEN** a release is started with auto, the latest release is `0.1.3`, and the fragments include a `New` one
- **THEN** the new release is `0.2.0`

#### Scenario: Auto bump with only fixes
- **WHEN** a release is started with auto, the latest release is `0.1.3`, and the only fragments are `Fixed` ones
- **THEN** the new release is `0.1.4`

### Requirement: Release notes from Changie fragments
Each user-facing change SHALL add a Changie fragment. A release SHALL batch the fragments into `.changes/<version>.md` and `CHANGELOG.md` and stamp the version into `version.txt`, all in the release commit. A dry run SHALL change none of these on `main`.

#### Scenario: Release commit
- **WHEN** a release of `0.1.1` is published with two fragments in `.changes/unreleased/`
- **THEN** its release commit adds both to `.changes/0.1.1.md` and `CHANGELOG.md`, removes the fragments, and sets `version.txt` to `0.1.1`

#### Scenario: Notes reach both destinations
- **WHEN** a release is published
- **THEN** the GitHub Release and the appcast entry both show the notes from `.changes/<version>.md`

### Requirement: Credentials checked before packaging
The release process SHALL check its signing and notarization credentials before packaging. It SHALL stop when the Developer ID identity is missing, the certificate has expired, or Apple rejects the App Store Connect API key, and it SHALL warn when the certificate has fewer than 30 days left.

#### Scenario: Expired certificate
- **WHEN** a release reaches packaging with an expired Developer ID certificate
- **THEN** it stops before packaging, with an error saying the certificate expired and how to replace it

#### Scenario: Certificate close to expiry
- **WHEN** a release reaches packaging with a certificate that has 20 days left
- **THEN** it warns about the expiry and continues

#### Scenario: Rejected API key
- **WHEN** a release reaches packaging with an App Store Connect API key that Apple rejects
- **THEN** it stops before packaging, with an error naming the API key secrets

### Requirement: Build-only dry run
The release process SHALL offer a dry-run mode that packages, signs and notarizes the app but creates no tag, GitHub Release or appcast change.

#### Scenario: Dry run
- **WHEN** a dry-run release is started
- **THEN** a signed, notarized DMG is available as a workflow artifact, and no tag, release or appcast change is made

### Requirement: Secrets never exposed
Signing certificates, notarization credentials, the Sparkle EdDSA private key and the deploy key that pushes release commits SHALL be provided only as encrypted secrets of a `release` environment that is limited to `main`. They MUST NOT appear in the repository, in build logs, in any published artifact, or on the self-hosted runner's disk after a job ends.

#### Scenario: Inspecting a release's logs and assets
- **WHEN** a release run's logs and every published asset are searched for the private key or the certificate password
- **THEN** neither is found
