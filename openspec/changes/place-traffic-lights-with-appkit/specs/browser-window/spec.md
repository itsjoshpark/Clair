# Spec Delta

## ADDED Requirements

### Requirement: Window controls stay in place
The close, minimize and zoom buttons SHALL sit at the top of the sidebar at Arc's positions and SHALL stay there, without showing anywhere else even for a frame, when the window's title changes, the window becomes or stops being key, or the window is resized.

#### Scenario: Page title changes
- **WHEN** the active tab navigates to a page with a different title
- **THEN** the window controls stay 12, 35 and 58 points from the sidebar's leading edge and 16 points from the top

#### Scenario: Window loses and regains focus
- **WHEN** another window becomes key and then the native window becomes key again
- **THEN** the window controls dim and brighten in place without moving

#### Scenario: Window resized
- **WHEN** the user resizes the window from any edge
- **THEN** the window controls keep their place relative to the sidebar's top leading corner

### Requirement: Window controls follow the sidebar
The window controls SHALL move with the sidebar: they SHALL slide with it while it hides, shows or is revealed over the page, sit at the same offsets from the revealed sidebar's corner, and be hidden while the sidebar is hidden and not revealed, and in page full screen.

#### Scenario: Hiding the sidebar
- **WHEN** the user presses Cmd+S with the sidebar shown
- **THEN** the window controls slide out with the sidebar and are hidden once it is hidden

#### Scenario: Revealed sidebar
- **WHEN** the sidebar is hidden and the pointer rests on the window's leading edge
- **THEN** the window controls slide in with the revealed sidebar and sit 12, 35 and 58 points from its leading edge and 16 points below its top

#### Scenario: Page full screen
- **WHEN** a page enters full screen
- **THEN** the window controls are hidden until it leaves full screen
