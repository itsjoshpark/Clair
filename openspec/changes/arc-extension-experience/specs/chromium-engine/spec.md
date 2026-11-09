# Spec Delta

## MODIFIED Requirements

### Requirement: Built from a pinned ungoogled-chromium release
Each Clair build SHALL come from exactly one tagged ungoogled-chromium release. That release's full patch series, binary pruning and domain substitution SHALL be applied, and the tag SHALL be recorded in the Clair source tree. The only exception is a list kept in Clair's source of files that domain substitution leaves out, which SHALL hold only files that name the Chrome Web Store's addresses, or the XML namespace of its update responses, for `extensions`.

#### Scenario: Engine release is identifiable from source
- **WHEN** the Clair source at a release tag is inspected
- **THEN** it identifies exactly one ungoogled-chromium tag, for example `156.0.8078.47-1`, as the engine the release was built from

#### Scenario: Patch that does not apply fails the build
- **WHEN** any ungoogled-chromium, macOS or Clair patch fails to apply cleanly during a build
- **THEN** the build stops with an error naming the patch and produces no app bundle

#### Scenario: Files left out of domain substitution
- **WHEN** the list of files that domain substitution leaves out is read
- **THEN** every file on it is one that names the Chrome Web Store's addresses or the XML namespace of its update responses, and a file on it that no longer exists in ungoogled-chromium's substitution list stops the build with an error naming it

### Requirement: ungoogled-chromium privacy defaults preserved
Clair SHALL ship ungoogled-chromium's default settings and Google-service removals unchanged, except for the password and autofill settings that Clair turns off, and the Chrome Web Store installs and extension update checks that `extensions` restores. Clair MUST NOT re-enable any other Google service integration that ungoogled-chromium removes or disables.

#### Scenario: Default settings match ungoogled-chromium
- **WHEN** a fresh Clair profile is compared with a fresh profile of the same ungoogled-chromium release
- **THEN** the defaults documented by ungoogled-chromium match, for example third-party cookies blocked, search suggestions disabled, and preload pages disabled

#### Scenario: No Google service traffic on an idle first launch
- **WHEN** Clair is launched for the first time with default settings and left on its new tab page with no user navigation
- **THEN** it makes no network requests to Google service endpoints, such as Safe Browsing, sync, sign-in, metrics, extension updates, or component and variations servers

#### Scenario: Google contacted only for store extensions
- **WHEN** the user has installed an extension from the Chrome Web Store
- **THEN** Clair contacts Google's extension servers only to download that extension and to check it for updates, and no other Google service

### Requirement: Browser behavior as in ungoogled-chromium outside Clair's interface
Apart from its identity (`app-identity`), native layer (`native-layer`), updater (`software-updates`), native window (`browser-window`, `sidebar` and `command-bar`), extensions (`extensions`) and the password and autofill features it turns off, Clair SHALL behave the same as the ungoogled-chromium release it is built from. That includes page rendering, settings, `chrome://` pages, profiles, history, extensions' APIs, and the menus and keyboard shortcuts the native window doesn't change.

#### Scenario: Stock browser UI
- **WHEN** a user opens a window in a bare engine build
- **THEN** it shows Chromium's standard tab strip, toolbar and menus, as the same ungoogled-chromium release does on macOS

#### Scenario: Settings unchanged
- **WHEN** a user opens `chrome://settings` in the native window
- **THEN** it shows the same settings and defaults as the same ungoogled-chromium release, apart from Clair's identity and versions and the absent "Autofill and passwords" section

### Requirement: Changes to Chromium limited to hooks and identity
Clair's patches to existing Chromium source files SHALL be limited to macOS build fixes, identity and branding, versioning, hooks, and restoring the Chrome Web Store installer and extension update checks that ungoogled-chromium removes, including sending those checks through the restored code. The hooks load the native layer, hand Chromium's browser window and its attached UI to Clair's code, register Clair's component extensions, and turn off or hide the password and autofill features. Each hook SHALL only redirect to Clair's code or switch a Chromium feature off. Other behaviour Clair adds SHALL live in the native layer or in new source files added to the Chromium tree.

#### Scenario: Reviewing Clair's patch series
- **WHEN** the patches in `patches/clair/` and `patches/helium/` are listed
- **THEN** each one is a build fix, an identity or branding change, a versioning change, a hook, or the store and update restoration, and none implements the updater, the update menu or the native window

#### Scenario: Reviewing a window hook
- **WHEN** a hunk of the native-window hook patch is read
- **THEN** it calls into Clair's overlay files or the native layer, makes Chromium skip UI the native window replaces, or switches off a feature Clair removes, and any behavior is in Clair's files

#### Scenario: Reviewing the store restoration
- **WHEN** the patch that restores the Chrome Web Store is read
- **THEN** each hunk puts back code that ungoogled-chromium's patches removed for the store installer or for extension update checks, or sends store update checks through that code, and adds no other behavior

## REMOVED Requirements

### Requirement: Extension installation as in ungoogled-chromium
**Reason**: Clair no longer installs extensions only as ungoogled-chromium does: it adds Chrome Web Store installs, native confirmations and automatic updates.
**Migration**: The CRX installation path and the extension API support move to the `extensions` capability's "Other installation paths kept" requirement, with the same scenario.
