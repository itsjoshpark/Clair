# Spec Delta

## ADDED Requirements

### Requirement: Loading indicator
While the active tab loads a new document in its main frame (the state that shows stop), the window SHALL show a loading indicator along the top edge of the page card, in the inset above it, that advances with the load's progress, as Arc's does. It SHALL fade in when the load starts and fade out once the load ends, whether it finished, was stopped or failed.

#### Scenario: Loading a page
- **WHEN** the user opens a slow page in the active tab
- **THEN** a glow appears along the top edge of the page card, advances as the page loads, and fades out once it has loaded

#### Scenario: Stopping a load
- **WHEN** the user clicks stop while a page loads
- **THEN** the indicator fades out

#### Scenario: Sidebar hidden
- **WHEN** the sidebar is hidden and the active tab loads a page
- **THEN** the indicator shows along the card's top edge as it does with the sidebar shown

### Requirement: Loading indicator shows the active tab only
The loading indicator SHALL NOT show for frames loading on their own, same-document navigations or background tabs, nor in page full screen. Switching tabs SHALL show the newly active tab's state at once.

#### Scenario: Background tab loading
- **WHEN** a link opens in a background tab and loads there
- **THEN** the active tab's card shows no indicator

#### Scenario: Switching to a loading tab
- **WHEN** the user switches to a tab that is still loading
- **THEN** the indicator shows that tab's progress straight away
