# Spec Delta

## Purpose

Defines Clair's native layer: a Swift framework that Chromium loads at start-up, and the contract it uses to reach Chromium. In this change it hosts the updater and the update menu. Later changes build Clair's native interface on it.

## ADDED Requirements

### Requirement: Native framework loaded at start-up
Clair SHALL load its native framework, `ClairUI.framework`, from `Clair.app/Contents/Frameworks` during start-up, after Chromium has created its main menu. When the framework is absent, as in a bare engine build, Chromium SHALL start normally without it and log that it is missing.

#### Scenario: Packaged app
- **WHEN** a packaged `Clair.app` is launched
- **THEN** `ClairUI.framework` is loaded, and its update items appear in the Clair application menu

#### Scenario: Bare engine
- **WHEN** an engine build without `ClairUI.framework` is launched for its smoke test
- **THEN** it starts and renders a page with Chromium's stock menus, and logs that the native layer is missing

### Requirement: One contract between Chromium and the native layer
The native layer SHALL reach Chromium only through the Objective-C protocols declared in `native/ClairHost.h`, and Chromium SHALL reach the native layer only through the entry point that header declares. In this change the contract SHALL cover at least the graceful relaunch that restores the session, whether a silent relaunch is safe (no download in progress, no incognito window, no audible or capturing tab), and the Chromium and ungoogled-chromium versions.

#### Scenario: Relaunch from the native layer
- **WHEN** the native layer asks the host to relaunch
- **THEN** Chromium runs its own graceful relaunch, including its quit confirmations, and restores the previous session

#### Scenario: Contract change
- **WHEN** `native/ClairHost.h` changes
- **THEN** the engine key changes, so a new engine is built for the new contract

### Requirement: Native layer builds without Chromium
The native layer and its unit tests SHALL build and run with Xcode against `native/ClairHost.h` alone, with no Chromium source or engine present.

#### Scenario: Building on the development machine
- **WHEN** the native layer is built and tested on a Mac with Xcode and no Chromium checkout
- **THEN** the build and its unit tests succeed

### Requirement: Native layer embedded at packaging
Packaging SHALL embed `ClairUI.framework` and its dependencies into the engine's app bundle and sign them with the rest of the bundle. A change to the native layer alone SHALL produce a new app without a new engine build.

#### Scenario: Native-only change reaches the app
- **WHEN** only the native layer changes and the quality checks package the app
- **THEN** the packaged app contains the new `ClairUI.framework` and uses the same `chromium-engine-<key>` as the previous commit
