# Spec Delta

## MODIFIED Requirements

### Requirement: Extension actions
The sidebar SHALL show the actions of extensions the user has pinned as buttons with their icons and badges, and an extensions button that lists every extension with an action. Clicking an action SHALL run it as Chromium's toolbar would, opening its popup window beside the button, as `extensions` defines. The row holding them SHALL show only while some extension has an action.

#### Scenario: Pinned extension with a popup
- **WHEN** the user clicks a pinned extension's button and its action has a popup
- **THEN** the popup window opens beside that button and is interactive

#### Scenario: Badge text
- **WHEN** an extension sets its action's badge text to "3"
- **THEN** its button in the sidebar shows a "3" badge

#### Scenario: Extension without a pin
- **WHEN** the user opens the extensions button's list and chooses an unpinned extension
- **THEN** its action runs, and its popup window opens beside the extensions button

#### Scenario: Newly installed extension
- **WHEN** the user installs an extension with an action
- **THEN** its button appears among the pinned actions, and the row shows if it was hidden
