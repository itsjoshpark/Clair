# Spec Delta

## Purpose

Defines Clair's product identity on macOS: its name, bundle and data identifiers, version scheme, and supported platform. These identifiers are fixed with the first shipped build and must stay stable for every later release.

## ADDED Requirements

### Requirement: Product name
The application SHALL present itself as "Clair". This applies to the app bundle name (`Clair.app`), the application menu title, the Dock, the About screen, and the window titles that Chromium would otherwise brand as "Chromium".

#### Scenario: App bundle and menu use the Clair name
- **WHEN** a user installs and launches the app
- **THEN** the installed bundle is `Clair.app`, the first menu bar item is titled "Clair", and its items read "About Clair", "Hide Clair" and "Quit Clair"

#### Scenario: No Chromium branding in user-facing chrome
- **WHEN** a user opens the About screen, the application menu, or a new window
- **THEN** none of them shows "Chromium" as the product name, except where the Chromium version is labelled as the engine version

### Requirement: Stable bundle identifier
The application SHALL use the bundle identifier `dev.joshuapark.Clair`. Every helper app inside the bundle SHALL use an identifier prefixed with `dev.joshuapark.Clair.`. These identifiers MUST NOT change in later releases.

#### Scenario: Main bundle identifier
- **WHEN** the `CFBundleIdentifier` of the shipped `Clair.app` is read
- **THEN** it is exactly `dev.joshuapark.Clair`

#### Scenario: Helper bundle identifiers
- **WHEN** the bundle identifiers of all helper apps inside `Clair.app` are listed
- **THEN** each one starts with `dev.joshuapark.Clair.`

### Requirement: Isolated user data location
The application SHALL store profile data under `~/Library/Application Support/Clair` and caches under `~/Library/Caches/Clair`. It MUST NOT read from or write to the data directories of Chromium, Google Chrome, or other Chromium-based browsers, except through an explicit user-initiated import.

#### Scenario: First launch creates the Clair data directory
- **WHEN** Clair is launched for the first time on a Mac with no previous Clair data
- **THEN** a default profile is created under `~/Library/Application Support/Clair`

#### Scenario: Side by side with another Chromium build
- **WHEN** Clair and an ungoogled-chromium or Chromium build are installed and running at the same time
- **THEN** both run as separate instances with separate profiles, and neither opens the other's profile or blocks its launch through the other's single-instance lock

### Requirement: Clair-specific keychain item
The application SHALL store its OS-encrypted storage key in the login keychain under the service name "Clair Safe Storage". It MUST NOT read or create the keychain items of other Chromium-based browsers.

#### Scenario: Keychain item on first launch
- **WHEN** Clair first needs to encrypt local data, such as cookies
- **THEN** a "Clair Safe Storage" item is created in the login keychain, and no "Chromium Safe Storage" item is created or read

### Requirement: Clair version scheme
The application SHALL report a Clair version in `MAJOR.MINOR.PATCH` form as its `CFBundleShortVersionString`. The version SHALL start at `0.1.0` and stay below `1.0.0` until the MVP release.

#### Scenario: First release version
- **WHEN** the first public release is published
- **THEN** its `CFBundleShortVersionString` is `0.1.0`

#### Scenario: Pre-MVP releases stay below 1.0.0
- **WHEN** any release before the MVP is published
- **THEN** its version is `0.y.z`

### Requirement: Monotonic build number
The application SHALL report an integer build number as its `CFBundleVersion`. Each release's build number SHALL be strictly greater than that of every earlier release.

#### Scenario: Later release has a larger build number
- **WHEN** two releases are published one after the other
- **THEN** the later release's `CFBundleVersion` is a larger integer than the earlier one's

### Requirement: Engine version preserved for web and extension compatibility
The Chromium version SHALL remain the version that websites and extensions see. The user agent and client hints MUST report the same Chromium version and brand information as the ungoogled-chromium release Clair is built from, and extension `minimum_chrome_version` checks MUST compare against that Chromium version, never against the Clair version.

#### Scenario: User agent reports the Chromium version
- **WHEN** a website reads `navigator.userAgent` in Clair built from ungoogled-chromium `156.0.8078.47-1`
- **THEN** it contains the same `Chrome/156` version token as that ungoogled-chromium build, and it does not contain the Clair version

#### Scenario: Extension minimum version check
- **WHEN** a user installs an extension that declares `minimum_chrome_version` of `150`
- **THEN** the installation is allowed, because the Chromium version (156) meets it, even though the Clair version is `0.1.0`

### Requirement: About screen shows both versions
The About Clair screen (which Chromium shows as its About settings page) SHALL show the Clair version with its build number, and separately, labelled as the engine, the Chromium version and the ungoogled-chromium revision Clair is built from.

#### Scenario: Opening About Clair
- **WHEN** a user chooses "About Clair" from the application menu
- **THEN** the About screen shows the Clair version, for example "0.1.0 (123)", and separately the Chromium version, for example "Chromium 156.0.8078.47 (ungoogled-chromium 156.0.8078.47-1)"

### Requirement: Supported platform
The application SHALL be built for Apple Silicon (arm64) only and SHALL declare a minimum macOS version of 15.6 (Sequoia).

#### Scenario: Architecture of shipped binaries
- **WHEN** the architectures of the shipped main executable and helper executables are inspected
- **THEN** each contains only an `arm64` slice

#### Scenario: Minimum macOS version declared
- **WHEN** the `LSMinimumSystemVersion` of the shipped `Clair.app` is read
- **THEN** it is `15.6`

### Requirement: Default browser registration as Clair
The application SHALL register as a web browser under its own bundle identifier, so that macOS lists it as "Clair" in the default web browser setting.

#### Scenario: Setting Clair as default browser
- **WHEN** a user picks "Clair" as the default web browser in System Settings
- **THEN** opening an `http` or `https` link from another app opens it in Clair
