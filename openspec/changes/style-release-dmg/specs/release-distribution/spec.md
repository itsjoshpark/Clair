# Spec Delta

## ADDED Requirements

### Requirement: Disk image window layout
When the release DMG is opened in Finder, its window SHALL open at a fixed size, with large icons and no toolbar, sidebar or status bar. It SHALL show only `Clair.app` on the left and the `Applications` shortcut on the right, side by side and fully visible.

#### Scenario: Opening the DMG
- **WHEN** a user opens the release DMG in Finder
- **THEN** its window shows `Clair.app` on the left and `Applications` on the right at their fixed positions, both fully visible without scrolling or resizing, with no toolbar, sidebar or status bar

#### Scenario: Layout files stay hidden
- **WHEN** a user opens the release DMG in Finder, with hidden files not shown
- **THEN** the window shows no items other than `Clair.app` and `Applications`

### Requirement: Disk image background
The DMG window SHALL show a background drawn from Clair's artwork, with an arrow from `Clair.app` to `Applications` that tells the user to drag one onto the other. The background SHALL be sharp on both standard and Retina displays.

#### Scenario: Background on a Retina display
- **WHEN** the release DMG is opened on a Retina display
- **THEN** the background is drawn at twice its point size, with no blur, and its arrow points from `Clair.app` to `Applications`

#### Scenario: Labels in both appearances
- **WHEN** the release DMG is opened with macOS set to Light, then to Dark appearance
- **THEN** the "Clair" and "Applications" labels Finder draws under the icons are readable against the background in both

#### Scenario: Background on a standard display
- **WHEN** the release DMG is opened on a non-Retina display
- **THEN** the background is drawn at its point size and lines up with the icons as it does on a Retina display

### Requirement: Disk image volume icon
The mounted release DMG SHALL show Clair's app icon as its volume icon, in place of the generic disk icon.

#### Scenario: Mounted volume
- **WHEN** the release DMG is mounted
- **THEN** the Finder sidebar, the desktop and the window's title bar show the volume named Clair with Clair's app icon

### Requirement: Layout leaves installs and updates unchanged
The window layout SHALL change only how the DMG looks. Dragging `Clair.app` to `Applications` SHALL install the same signed app as before, and a Sparkle update from the DMG SHALL install only `Clair.app`.

#### Scenario: Installing by drag
- **WHEN** a user drags `Clair.app` from the release DMG onto `Applications` and opens it
- **THEN** the installed app passes `codesign --verify --strict` and opens after only the standard "downloaded from the internet" confirmation

#### Scenario: Updating from the DMG
- **WHEN** Sparkle installs an update from a release DMG with the layout
- **THEN** only `Clair.app` is replaced, and no background, layout or volume icon file is copied into `/Applications`

#### Scenario: The DMG stays notarized
- **WHEN** `spctl --assess --type open --context context:primary-signature` and `stapler validate` are run on the release DMG
- **THEN** both pass and identify Clair's Developer ID team
