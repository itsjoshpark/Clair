# Spec Delta

## ADDED Requirements

### Requirement: Download progress
While downloads run, the downloads button SHALL show the same progress as the Dock icon, in every window: the running downloads of every profile, paused ones included, and no progress while any of them has an unknown size.

#### Scenario: Download in progress
- **WHEN** a download starts
- **THEN** the downloads button shows the download's progress until it finishes

#### Scenario: Download in another profile
- **WHEN** a download runs in one profile while a window of another profile is open
- **THEN** both windows' downloads buttons show the same progress as the Dock, and clear it when the download ends
