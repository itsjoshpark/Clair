# Spec Delta

## MODIFIED Requirements

### Requirement: Browser behavior as in ungoogled-chromium outside Clair's interface
Apart from its identity (`app-identity`), native layer (`native-layer`), updater (`software-updates`), native window (`browser-window`, `sidebar` and `command-bar`), Spaces and profile management (`spaces` and `profiles`), extensions (`extensions`) and the password and autofill features it turns off, Clair SHALL behave the same as the ungoogled-chromium release it is built from. That includes page rendering, settings, `chrome://` pages, each profile's own data and settings, history, extensions' APIs, and the menus and keyboard shortcuts the native window doesn't change.

#### Scenario: Stock browser UI
- **WHEN** a user opens a window in a bare engine build
- **THEN** it shows Chromium's standard tab strip, toolbar and menus, as the same ungoogled-chromium release does on macOS

#### Scenario: Settings unchanged
- **WHEN** a user opens `chrome://settings` in the native window
- **THEN** it shows the same settings and defaults as the same ungoogled-chromium release, apart from Clair's identity and versions and the absent "Autofill and passwords" section
