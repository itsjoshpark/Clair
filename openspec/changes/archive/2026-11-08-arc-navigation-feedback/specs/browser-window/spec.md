# Spec Delta

## ADDED Requirements

### Requirement: New Incognito Window from the Dock with no windows
Clair's Dock menu SHALL offer New Incognito Window whether or not a window is open.

#### Scenario: No windows open
- **WHEN** the user closes every window, right-clicks Clair in the Dock and chooses New Incognito Window
- **THEN** an incognito window opens

### Requirement: Loading indicator
While the active tab loads a new document in its main frame (the state that shows stop), the window SHALL show Arc's loading indicator: a small capsule in the inset above the page card, centred on the card. As Arc's does, it SHALL run on time rather than on the load's progress: it pulses from the start of the load, then, if the load is still running after two pulses, widens into a track with a looping sweep.

#### Scenario: Loading a page
- **WHEN** the user opens a slow page in the active tab
- **THEN** a capsule pulses above the centre of the page card, widens into a sweeping track after about three seconds, and shrinks away once the page has loaded

#### Scenario: Sidebar hidden
- **WHEN** the sidebar is hidden and the active tab loads a page
- **THEN** the indicator shows above the centre of the card as it does with the sidebar shown

### Requirement: Loading indicator ends with the load
When the load ends, whether it finished, was stopped or failed, the loading indicator SHALL flash and shrink away, as Arc's does.

#### Scenario: Stopping a load
- **WHEN** the user clicks stop while a page loads
- **THEN** the indicator shrinks away

### Requirement: Loading indicator shows the active tab only
The loading indicator SHALL NOT show for frames loading on their own, same-document navigations or background tabs, nor in page full screen. Switching tabs SHALL show the newly active tab's state at once.

#### Scenario: Background tab loading
- **WHEN** a link opens in a background tab and loads there
- **THEN** the active tab's card shows no indicator

#### Scenario: Switching to a loading tab
- **WHEN** the user switches to a tab that is still loading
- **THEN** the indicator shows straight away
