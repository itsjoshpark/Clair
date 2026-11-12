# Spec Delta

## MODIFIED Requirements

### Requirement: Browser behavior as in ungoogled-chromium outside Clair's interface
Apart from its identity (`app-identity`), native layer (`native-layer`), updater (`software-updates`), native window (`browser-window`, `sidebar` and `command-bar`), Spaces (`spaces`), extensions (`extensions`) and the password and autofill features it turns off, Clair SHALL behave the same as the ungoogled-chromium release it is built from. That includes page rendering, settings, `chrome://` pages, profiles, history, extensions' APIs, and the menus and keyboard shortcuts the native window doesn't change.

#### Scenario: Stock browser UI
- **WHEN** a user opens a window in a bare engine build
- **THEN** it shows Chromium's standard tab strip, toolbar and menus, as the same ungoogled-chromium release does on macOS

#### Scenario: Settings unchanged
- **WHEN** a user opens `chrome://settings` in the native window
- **THEN** it shows the same settings and defaults as the same ungoogled-chromium release, apart from Clair's identity and versions, the absent "Autofill and passwords" section, and "On startup" set to continue where the user left off

### Requirement: What Clair's Chromium hooks may do
Clair's hooks SHALL load the native layer, hand Chromium's browser window and its attached UI to Clair's code, register Clair's component extensions, register Clair's own preferences, tag Clair's tabs in the sessions Chromium saves and read the tags back, free keyboard shortcuts that Clair assigns to its own commands, turn off or hide the password and autofill features, make Chromium restore the previous session's tabs by default and into one window, and turn off extensions' uninstall pages. Each hook SHALL only redirect to Clair's code or switch a Chromium feature off.

#### Scenario: Reviewing a window hook
- **WHEN** a hunk of the native-window hook patch is read
- **THEN** it calls into Clair's overlay files or the native layer, makes Chromium skip UI the native window replaces, or switches off a feature Clair removes, and any behavior is in Clair's files

#### Scenario: Reviewing a session hook
- **WHEN** a hunk of a patch to Chromium's session code is read
- **THEN** it calls into Clair's overlay files to write or read a tag on a tab, and decides nothing itself
