# Spec Delta

## MODIFIED Requirements

### Requirement: One contract between Chromium and the native layer
The native layer SHALL reach Chromium only through the Objective-C protocols declared in `native/ClairHost.h`, and Chromium SHALL reach the native layer only through the entry point that header declares and the objects it returns. The contract SHALL cover at least what the updater needs, opening a URL in a browser tab, and everything the native window needs.

#### Scenario: Contract contents
- **WHEN** `native/ClairHost.h` is read
- **THEN** it covers the graceful relaunch that restores the session, whether a silent relaunch is safe (no download in progress, no incognito window, no audible or capturing tab), the Chromium and ungoogled-chromium versions, opening a URL in a browser tab, and, for the native window: creating and closing windows, each window's tabs and their state, the active page's view and its docked DevTools, navigation, find, autocomplete, downloads, extension actions, extension install and remove confirmations, extension context menus, infobars, toasts and where Chromium's bubbles attach

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

#### Scenario: Extension confirmation answered
- **WHEN** Chromium asks the native layer to confirm an extension install or removal and the user answers
- **THEN** the native layer reports the answer through the contract exactly once, and Chromium installs, removes or cancels accordingly; a window that closes first reports a cancel
