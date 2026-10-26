# Spec Delta

## Purpose

Defines Clair's engine baseline. Clair is a build of a specific ungoogled-chromium release with that release's privacy defaults and feature removals intact, and it can move to any newer ungoogled-chromium release on its own schedule.

## ADDED Requirements

### Requirement: Built from a pinned ungoogled-chromium release
Each Clair build SHALL come from exactly one tagged ungoogled-chromium release. That release's full patch series, binary pruning and domain substitution SHALL be applied, and the tag SHALL be recorded in the Clair source tree.

#### Scenario: Engine release is identifiable from source
- **WHEN** the Clair source at a release tag is inspected
- **THEN** it identifies exactly one ungoogled-chromium tag, for example `156.0.8078.47-1`, as the engine the release was built from

#### Scenario: Patch that does not apply fails the build
- **WHEN** any ungoogled-chromium, macOS or Clair patch fails to apply cleanly during a build
- **THEN** the build stops with an error naming the patch and produces no app bundle

### Requirement: ungoogled-chromium privacy defaults preserved
Clair SHALL ship ungoogled-chromium's default settings and Google-service removals unchanged. This change MUST NOT re-enable any Google service integration that ungoogled-chromium removes or disables.

#### Scenario: Default settings match ungoogled-chromium
- **WHEN** a fresh Clair profile is compared with a fresh profile of the same ungoogled-chromium release
- **THEN** the defaults documented by ungoogled-chromium match, for example third-party cookies blocked, search suggestions disabled, and preload pages disabled

#### Scenario: No Google service traffic on an idle first launch
- **WHEN** Clair is launched for the first time with default settings and left on its new tab page with no user navigation
- **THEN** it makes no network requests to Google service endpoints, such as Safe Browsing, sync, sign-in, metrics, or component and variations servers

### Requirement: No browser behavior changes beyond identity and updates
Apart from the identity defined in `app-identity` and the updater defined in `software-updates`, Clair in this change SHALL behave the same as the ungoogled-chromium release it is built from. That includes browser UI, menus, keyboard shortcuts and settings.

#### Scenario: Stock browser UI
- **WHEN** a user opens a window in this release of Clair
- **THEN** it shows Chromium's standard tab strip, toolbar and menus, as the same ungoogled-chromium release does on macOS

### Requirement: Extension installation as in ungoogled-chromium
Clair SHALL support installing Chrome extensions through the same mechanisms as ungoogled-chromium. One example is the `--extension-mime-request-handling=always-prompt-for-install` option, available as a flag in `chrome://flags`, which lets users install CRX files. Installed extensions SHALL run with full Chrome extension API support.

#### Scenario: Installing an extension from a CRX file
- **WHEN** a user enables "Always prompt for install" for extension MIME handling in `chrome://flags`, and then opens a link to an extension's CRX file
- **THEN** Clair prompts to install the extension, and after installation the extension runs and shows its toolbar action

### Requirement: Engine updates without third-party macOS packaging
Clair SHALL be able to move to any newer ungoogled-chromium release tag without waiting for a matching `ungoogled-chromium-macos` release. Moving to a new tag SHALL only require changing the pinned engine tag, plus adjusting a macOS or Clair patch where one no longer applies.

#### Scenario: Security patch release
- **WHEN** ungoogled-chromium publishes a new patch-level tag for the Chromium major version Clair already uses, and all of Clair's patches still apply
- **THEN** a Clair release on that tag can be produced by changing only the pinned engine tag, with no other source changes
