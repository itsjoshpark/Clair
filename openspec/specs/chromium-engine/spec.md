# chromium-engine Specification

## Purpose

Defines Clair's engine baseline. Clair is a build of a specific ungoogled-chromium release with that release's privacy defaults and feature removals intact, and it can move to any newer ungoogled-chromium release on its own schedule.

## Requirements

### Requirement: Built from a pinned ungoogled-chromium release
Each Clair build SHALL come from exactly one tagged ungoogled-chromium release. That release's full patch series, binary pruning and domain substitution SHALL be applied, and the tag SHALL be recorded in the Clair source tree.

#### Scenario: Engine release is identifiable from source
- **WHEN** the Clair source at a release tag is inspected
- **THEN** it identifies exactly one ungoogled-chromium tag, for example `156.0.8078.47-1`, as the engine the release was built from

#### Scenario: Patch that does not apply fails the build
- **WHEN** any ungoogled-chromium, macOS or Clair patch fails to apply cleanly during a build
- **THEN** the build stops with an error naming the patch and produces no app bundle

### Requirement: ungoogled-chromium privacy defaults preserved
Clair SHALL ship ungoogled-chromium's default settings and Google-service removals unchanged, except for the password and autofill settings that Clair turns off. This change MUST NOT re-enable any Google service integration that ungoogled-chromium removes or disables.

#### Scenario: Default settings match ungoogled-chromium
- **WHEN** a fresh Clair profile is compared with a fresh profile of the same ungoogled-chromium release
- **THEN** the defaults documented by ungoogled-chromium match, for example third-party cookies blocked, search suggestions disabled, and preload pages disabled

#### Scenario: No Google service traffic on an idle first launch
- **WHEN** Clair is launched for the first time with default settings and left on its new tab page with no user navigation
- **THEN** it makes no network requests to Google service endpoints, such as Safe Browsing, sync, sign-in, metrics, or component and variations servers

### Requirement: Browser behavior as in ungoogled-chromium outside Clair's interface
Apart from its identity (`app-identity`), native layer (`native-layer`), updater (`software-updates`), native window (`browser-window`, `sidebar` and `command-bar`) and the password and autofill features it turns off, Clair SHALL behave the same as the ungoogled-chromium release it is built from. That includes page rendering, settings, `chrome://` pages, profiles, history, extensions' APIs, and the menus and keyboard shortcuts the native window doesn't change.

#### Scenario: Stock browser UI
- **WHEN** a user opens a window in a bare engine build
- **THEN** it shows Chromium's standard tab strip, toolbar and menus, as the same ungoogled-chromium release does on macOS

#### Scenario: Settings unchanged
- **WHEN** a user opens `chrome://settings` in the native window
- **THEN** it shows the same settings and defaults as the same ungoogled-chromium release, apart from Clair's identity and versions and the absent "Autofill and passwords" section

### Requirement: Changes to Chromium limited to hooks and identity
Clair's patches to existing Chromium source files SHALL be limited to macOS build fixes, identity and branding, versioning, and hooks: loading the native layer, handing Chromium's browser window and its attached UI to Clair's code, and turning off or hiding the password and autofill features. Each hook SHALL only redirect to Clair's code or switch a Chromium feature off. Other behaviour Clair adds SHALL live in the native layer or in new source files added to the Chromium tree.

#### Scenario: Reviewing Clair's patch series
- **WHEN** the patches in `patches/clair/` and `patches/helium/` are listed
- **THEN** each one is a build fix, an identity or branding change, a versioning change, or a hook, and none implements the updater, the update menu or the native window

#### Scenario: Reviewing a window hook
- **WHEN** a hunk of the native-window hook patch is read
- **THEN** it calls into Clair's overlay files or the native layer, makes Chromium skip UI the native window replaces, or switches off a feature Clair removes, and any behavior is in Clair's files

### Requirement: Extension installation as in ungoogled-chromium
Clair SHALL support installing Chrome extensions through the same mechanisms as ungoogled-chromium. One example is the `--extension-mime-request-handling=always-prompt-for-install` option, available as a flag in `chrome://flags`, which lets users install CRX files. Installed extensions SHALL run with full Chrome extension API support, except for APIs that show UI the native window doesn't host, such as side panels, as `browser-window` defines.

#### Scenario: Installing an extension from a CRX file
- **WHEN** a user enables "Always prompt for install" for extension MIME handling in `chrome://flags`, and then opens a link to an extension's CRX file
- **THEN** Clair prompts to install the extension, and after installation the extension runs and its action is listed in the sidebar's extensions button

### Requirement: Engine updates without third-party macOS packaging
Clair SHALL be able to move to any newer ungoogled-chromium release tag without waiting for a matching `ungoogled-chromium-macos` release. Moving to a new tag SHALL only require changing the pinned engine tag, plus adjusting a macOS or Clair patch where one no longer applies.

#### Scenario: Security patch release
- **WHEN** ungoogled-chromium publishes a new patch-level tag for the Chromium major version Clair already uses, and all of Clair's patches still apply
- **THEN** a Clair release on that tag can be produced by changing only the pinned engine tag, with no other source changes

### Requirement: Passwords and autofill turned off
Clair SHALL NOT offer to save passwords and SHALL NOT fill saved passwords, addresses or payment methods into pages, whatever the profile's earlier settings were. The "Autofill and passwords" section of `chrome://settings` SHALL be hidden. Passwords saved before this change SHALL stay in the profile and viewable at `chrome://password-manager`, so the user can export them to a password manager.

#### Scenario: Signing in to a site
- **WHEN** the user submits a sign-in form with a username and password
- **THEN** Clair offers no prompt to save the password, and none is saved

#### Scenario: Filling an address form
- **WHEN** the user focuses an address field in a form, in a profile that has saved addresses
- **THEN** no autofill suggestions appear

#### Scenario: Settings page
- **WHEN** the user opens `chrome://settings`
- **THEN** it has no "Autofill and passwords" section
