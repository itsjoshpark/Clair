# native-layer Specification

## Purpose

Defines Clair's native layer: a Swift framework that Chromium loads at start-up, and the contract it uses to reach Chromium. In this change it hosts the updater and the update menu. Later changes build Clair's native interface on it.

## Requirements

### Requirement: Native framework loaded at start-up
Clair SHALL load its native framework, `ClairUI.framework`, from `Clair.app/Contents/Frameworks` during start-up, after Chromium has created its main menu and before it opens the first browser window. When the framework is absent, as in a bare engine build, Chromium SHALL start normally without it, open its own browser windows, and log that it is missing. When the framework is present but fails to load, Clair SHALL log why, show an alert, and quit without opening a browser window.

#### Scenario: Packaged app
- **WHEN** a packaged `Clair.app` is launched
- **THEN** `ClairUI.framework` is loaded, its update items appear in the Clair application menu, and the first browser window is the native window

#### Scenario: Bare engine
- **WHEN** an engine build without `ClairUI.framework` is launched for its smoke test
- **THEN** it starts and renders a page in Chromium's own window with Chromium's stock menus, and logs that the native layer is missing

#### Scenario: Framework fails to load
- **WHEN** `Clair.app` contains a `ClairUI.framework` that can't be loaded, for example because its binary is damaged
- **THEN** Clair logs the loader's error, shows an alert that it couldn't start its interface, and quits without opening a browser window

### Requirement: One contract between Chromium and the native layer
The native layer SHALL reach Chromium only through the Objective-C protocols declared in `native/ClairHost.h`, and Chromium SHALL reach the native layer only through the entry point that header declares and the objects it returns. The contract SHALL cover at least what the updater needs, opening a URL in a browser tab, and everything the native window needs.

#### Scenario: Contract contents
- **WHEN** `native/ClairHost.h` is read
- **THEN** it covers the graceful relaunch that restores the session, whether a silent relaunch is safe (no download in progress, no incognito window, no audible or capturing tab), the Chromium and ungoogled-chromium versions, opening a URL in a browser tab, and, for the native window: creating and closing windows, each window's tabs and their state, the active page's view and its docked DevTools, navigation, find, autocomplete, downloads, extension actions, infobars, toasts and where Chromium's bubbles attach

#### Scenario: Relaunch from the native layer
- **WHEN** the native layer asks the host to relaunch
- **THEN** Chromium runs its own graceful relaunch, including its quit confirmations, and restores the previous session

#### Scenario: Opening a URL from the native layer
- **WHEN** the native layer asks the host to open a URL, including a `chrome://` URL
- **THEN** Chromium opens it in a new foreground tab of the most recently active browser window, or in a new browser window if none is open

#### Scenario: Window created by Chromium
- **WHEN** Chromium creates a normal browser window, for a new window, session restore, an extension's `chrome.windows.create` or a link opened in a new window
- **THEN** it asks the native layer for that window through the contract, and the native layer creates and shows it

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

### Requirement: Native window logic tested without Chromium
The native window's logic, namely the tab list's order and insertion, the URL field's display rules, the command bar's keyboard handling and modes, and where Chromium's bubbles attach, SHALL be unit-tested against a fake implementation of the contract, with no Chromium engine present.

#### Scenario: Merge gate for a sidebar change
- **WHEN** a pull request changes only the sidebar's Swift code
- **THEN** the merge gate builds and runs the native layer's unit tests for the sidebar against the fake host, without a Chromium build
