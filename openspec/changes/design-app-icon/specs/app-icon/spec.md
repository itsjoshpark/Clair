# Spec Delta

## Purpose

Defines how Clair's icon and product logo appear across macOS: the mark itself, its system appearances, its fallback on older macOS, its legibility at small sizes, and the logo shown inside the app.

## ADDED Requirements

### Requirement: Clair mark as the application icon
The application icon SHALL be the Clair gilded ring: a thick open gold ring opening to the right, a thin inner hairline with a bead, a curl at the ring's lower end and a short flick at its upper end. Gold SHALL be the mark's only color. Surfaces that show the application icon MUST NOT show Chromium's logo.

#### Scenario: Dock and Finder show the Clair mark
- **WHEN** Clair is installed and launched
- **THEN** its Dock tile, its Finder icon, its Get Info window and the Cmd+Tab app switcher all show the gold gilded ring, and none of them shows Chromium's logo

#### Scenario: Gold is the only mark color
- **WHEN** the icon is viewed in its default light or dark appearance
- **THEN** the mark is drawn only in gold tones, on the system's default icon background

### Requirement: Mark proportions
The ring's outer diameter SHALL be 72% of the icon tile's width, with a tolerance of one percentage point. The mark SHALL be offset to the right of the tile's center by about 2% of the tile's width, so that the open side does not make it look off-center.

#### Scenario: Ring size on the 1024 px canvas
- **WHEN** the default-appearance icon is rendered on a 1024 px canvas, whose tile is 824 px wide
- **THEN** the ring's outer diameter measures between 585 px and 602 px

#### Scenario: Optical offset
- **WHEN** the same rendering is measured
- **THEN** the ring's center lies between 12 px and 22 px to the right of the canvas center, and within 2 px of it vertically

### Requirement: System icon appearances
On macOS 26 and later, the icon SHALL follow the user's icon appearance setting. It SHALL use the system's default icon background in each appearance rather than a custom background.

#### Scenario: Light and dark appearances
- **WHEN** the user sets icons to the light appearance, then to the dark appearance
- **THEN** the icon shows the gold mark on the system's light background, then on the system's dark background, with the gold adjusted so it stays legible on each

#### Scenario: Tinted appearance
- **WHEN** the user sets icons to a tinted appearance with any tint color
- **THEN** the mark is drawn in that tint, and its ring, curl, flick, hairline and bead are all still distinguishable

#### Scenario: Clear appearance
- **WHEN** the user sets icons to the clear appearance
- **THEN** the mark is drawn as clear glass and its outline is still recognisable

### Requirement: Fallback on macOS 15
On macOS 15.6 through 15.x, the application SHALL show a rendition of the same mark in its light appearance, inside a standard macOS rounded-square tile.

#### Scenario: Icon on macOS 15.6
- **WHEN** Clair is installed on macOS 15.6
- **THEN** the Dock and Finder show the gold mark on a light rounded-square tile, never a generic application icon or Chromium's logo

### Requirement: Small-size legibility
At 16 px and 32 px, the open ring and its curl SHALL stay recognisable as a clear shape on every supported macOS version. The inner hairline and bead are allowed to fade at these sizes, but they MUST NOT turn the mark into a blur.

#### Scenario: Finder list view on macOS 26
- **WHEN** Clair is shown in a Finder list view or in the Finder sidebar at 16 px on macOS 26
- **THEN** the open ring and its curl are recognisable

#### Scenario: Finder list view on macOS 15
- **WHEN** Clair is shown in a Finder list view at 16 px on macOS 15.6
- **THEN** the open ring and its curl are recognisable

### Requirement: Product logo inside the app
Every in-app surface that Chromium brands with its product logo SHALL show the Clair mark instead, without the icon's rounded-square background. Where Chromium shows a color logo, the mark SHALL be gold. Where Chromium draws its logo in a single color, the mark SHALL be a single-color silhouette in that color. Chromium's logo MUST NOT appear on any of these surfaces.

#### Scenario: About Clair
- **WHEN** the user opens About Clair
- **THEN** the product logo shown is the gold gilded ring, and Chromium's logo does not appear anywhere on the page

#### Scenario: Single-color logo surfaces
- **WHEN** the user opens a `chrome://` page, so that the address bar shows the product icon
- **THEN** the icon is a one-color silhouette of the gilded ring, not Chromium's logo

### Requirement: Clair wordmark
Where Chromium shows its wordmark, the application SHALL show the Clair wordmark: the gold mark followed by "Clair" set in Albert Sans. A variant with white text SHALL be used where Chromium uses its white wordmark.

#### Scenario: Version page
- **WHEN** the user opens `chrome://version`
- **THEN** the page header shows the gold mark followed by "Clair", and no "chromium" wordmark appears
