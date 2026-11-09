# Spec Delta

## ADDED Requirements

### Requirement: Overshooting the window's edge
The area outside the key window's leading edge, as tall as the window, SHALL count as the leading inset, as in Arc. It SHALL be 50 points wide, and 250 points wide while the pointer was last in the window or is in that area, so a pointer that overshoots the inset still reveals the sidebar, and the revealed sidebar stays while the pointer is there. Only pointer moves count, not drags.

#### Scenario: Overshooting the inset
- **WHEN** the sidebar is hidden and the pointer leaves the window through its leading edge and comes to rest up to 250 points beyond it, level with the window
- **THEN** the sidebar is revealed and stays revealed while the pointer rests there

#### Scenario: Too far out
- **WHEN** the pointer leaves the window through its leading edge and comes to rest 260 points or more beyond it, or higher or lower than the window
- **THEN** the sidebar isn't revealed, or hides if it was

#### Scenario: Arriving from elsewhere
- **WHEN** the pointer reaches the area beside the window's leading edge without crossing the window
- **THEN** the sidebar is revealed if the pointer comes to rest within 50 points of the edge, and not if it comes to rest 100 points away

#### Scenario: Dragging past the edge
- **WHEN** the sidebar is hidden and the user drags past the window's leading edge, as when selecting text
- **THEN** the sidebar isn't revealed

## MODIFIED Requirements

### Requirement: Revealing the hidden sidebar
While the sidebar is hidden, the pointer coming to rest in the key window's leading inset, with no move for about 80 ms, SHALL slide the sidebar in as a floating overlay above the page, without resizing the page, as in Arc. A pointer moving through without stopping SHALL NOT reveal it. Once the pointer leaves the overlay, the sidebar SHALL slide back out about 100 ms later. Showing the sidebar while it's revealed SHALL dock it where it is, with only the card moving to make room.

#### Scenario: Hover reveal
- **WHEN** the sidebar is hidden and the pointer comes to rest at the window's leading edge
- **THEN** the sidebar slides in over the page, the page keeps its size, and moving the pointer off the overlay hides it again

#### Scenario: Passing through
- **WHEN** the sidebar is hidden and the pointer moves through the leading inset, or the area beside the window, without stopping
- **THEN** the sidebar isn't revealed

#### Scenario: Showing a revealed sidebar
- **WHEN** the sidebar is revealed over the page and the user presses Cmd+S
- **THEN** the sidebar stays where it is and becomes the docked sidebar, and the card narrows to make room
