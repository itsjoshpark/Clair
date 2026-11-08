# Spec Delta

## ADDED Requirements

### Requirement: Window controls stay in place
The close button SHALL sit at a fixed place near the sidebar's top leading corner, with the minimize and zoom buttons after it at the system's spacing. On macOS 27 that place SHALL be Arc's: 12 points from the sidebar's leading edge and 16 points from its top. The buttons SHALL stay there, without showing anywhere else even for a frame, when the window's title changes, the window becomes or stops being key, or the window is resized.

#### Scenario: Default place on macOS 27
- **WHEN** a native window opens with the sidebar shown on macOS 27
- **THEN** the close button reads 12 points from the sidebar's leading edge and 16 points from its top, as Arc's does

#### Scenario: Page title changes
- **WHEN** the active tab navigates to a page with a different title
- **THEN** the window controls keep their place

#### Scenario: Window loses and regains focus
- **WHEN** another window becomes key and then the native window becomes key again
- **THEN** the window controls dim and brighten in place without moving

#### Scenario: Window resized
- **WHEN** the user resizes the window from any edge
- **THEN** the window controls keep their place relative to the sidebar's top leading corner

### Requirement: Top row laid out from the window controls
The sidebar's top-row buttons SHALL be vertically centred on the window controls, and the first of them SHALL start after the zoom button, wherever the system draws the window controls and whatever their size and spacing. The sidebar SHALL NOT narrow so far that the compact top row reaches the zoom button.

#### Scenario: Default top row on macOS 27
- **WHEN** a native window opens with the sidebar shown on macOS 27
- **THEN** the top-row buttons are centred 24 points below the sidebar's top, on the window controls' centre line, and the hide-sidebar button starts 7 points after the zoom button, at 81 points

#### Scenario: Window controls drawn elsewhere
- **WHEN** the system draws the window controls a few points higher or lower, or wider apart, than on macOS 27
- **THEN** the top-row buttons move to stay centred on them, and the hide-sidebar button still starts after the zoom button

#### Scenario: Narrowest sidebar
- **WHEN** the user drags the sidebar's edge as far left as it goes
- **THEN** the compact top row's back button starts after the zoom button

### Requirement: Window controls follow the sidebar
The window controls SHALL move with the sidebar: they SHALL slide with it while it hides, shows or is revealed over the page, sit at the same place relative to the revealed sidebar's corner, and be hidden while the sidebar is hidden and not revealed, and in page full screen. Where the system can't move them while the sidebar moves, they SHALL instead be hidden during the motion and shown at their place once it ends, and Clair SHALL log that once per launch.

#### Scenario: Hiding the sidebar
- **WHEN** the user presses Cmd+S with the sidebar shown
- **THEN** the window controls slide out with the sidebar and are hidden once it is hidden

#### Scenario: Revealed sidebar
- **WHEN** the sidebar is hidden and the pointer rests on the window's leading edge
- **THEN** the window controls slide in with the revealed sidebar and sit at the same place relative to its top leading corner as in the shown sidebar

#### Scenario: Page full screen
- **WHEN** a page enters full screen
- **THEN** the window controls are hidden until it leaves full screen

#### Scenario: System that can't move them during motion
- **WHEN** the sidebar hides, shows or is revealed on a macOS where the window controls can't follow it
- **THEN** the window controls are hidden while it moves, appear at their place once it stops, and Clair's log says once that they can't follow the sidebar on this macOS
