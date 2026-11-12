# Spec Delta

## MODIFIED Requirements

### Requirement: Settings pages
The Settings window SHALL show a toolbar of pages, General, Profiles, Links and Advanced in that order, with each page's rows grouped in rounded cards. Choosing a toolbar item SHALL show that page in place of the current one, and the window's title SHALL be the shown page's name. The window SHALL open on General the first time, and afterwards on the page last shown, across launches.

#### Scenario: First opening
- **WHEN** the user opens Settings for the first time
- **THEN** the window shows the General page, titled "General", with toolbar items General, Profiles, Links and Advanced

#### Scenario: Switching pages
- **WHEN** the Settings window shows General and the user chooses Advanced in the toolbar
- **THEN** the window shows the Advanced page in place of General, and its title becomes "Advanced"

#### Scenario: Last page remembered
- **WHEN** the user leaves the Settings window on Advanced, quits Clair, relaunches it and opens Settings
- **THEN** the window shows the Advanced page

#### Scenario: Profiles page
- **WHEN** the user chooses Profiles in the toolbar
- **THEN** the window shows the Profiles page, wider than the other pages, and its title becomes "Profiles"
