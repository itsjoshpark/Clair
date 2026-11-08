# Spec Delta

## MODIFIED Requirements

### Requirement: Quality checks after merge
Every push to `main` SHALL run quality checks on a GitHub-hosted runner. They package the app from the published engine and the commit's native layer, run the static app checks, and run the automated runtime suite against the packaged app. A push to `main` SHALL skip the suite and count as passed when a quality run on a commit with the same file tree has already passed. The checks MAY also be started by hand on any branch. They SHALL NOT block merging. A failure on `main` SHALL be reported in a GitHub issue that names the commit, the failing tests and the run, so the failure can be assigned and fixed.

#### Scenario: Regression on main
- **WHEN** a merged commit breaks a runtime test
- **THEN** the quality run for that commit fails, and an open `quality-failure` issue names the commit, the failing test and the run link

#### Scenario: Merge of a branch that passed
- **WHEN** an up-to-date branch whose quality run passed is squash-merged, so `main` has the branch's file tree
- **THEN** the quality run for the merge commit finds the branch's run, skips the suite, passes, and closes any open `quality-failure` issue

#### Scenario: Runtime suite contents
- **WHEN** the quality checks run
- **THEN** the runtime suite covers at least: launch and page rendering, the Clair application menu items, the data directory and keychain item, the user agent's Chromium version, the About page versions, a manual update check against local test appcasts, and session restore after a relaunch

#### Scenario: Native window coverage
- **WHEN** the quality checks run
- **THEN** the runtime suite also covers the native window's fundamentals: the window's structure, launch and session restore, the page shown in the card, tab selection, creation (at the top), closing and reordering in the sidebar, navigation controls, opening and switching tabs through the command bar, hiding and revealing the sidebar, a permission prompt with the sidebar shown and hidden, an extension action's popup, the downloads indicator, a toast, page full screen, and docked DevTools
