# Spec Delta

## Purpose

Clair's own dialogs: a card with Clair's content and styling, attached to the window it belongs to as Arc's are, used where Clair asks the user for a name, a confirmation or a small set of edits, in place of macOS's standard alerts.

## ADDED Requirements

### Requirement: Dialogs are attached to their window
A Clair dialog SHALL show as a rounded card with Clair's own layout, centred on the window it belongs to, which dims behind it, and SHALL move with that window. It SHALL NOT use macOS's standard alert layout. While it shows, the rest of that window SHALL NOT respond to clicks or keys, and other windows SHALL stay usable. A window SHALL show one dialog at a time: another one asked for meanwhile SHALL wait its turn.

#### Scenario: Showing a dialog
- **WHEN** a dialog opens on a browser window
- **THEN** a card shows centred on the dimmed window, and clicking a tab row behind it does nothing

#### Scenario: Another window
- **WHEN** a dialog shows on one browser window and the user clicks another browser window
- **THEN** the other window becomes key and works as usual

#### Scenario: Keys don't reach the page
- **WHEN** a dialog shows and the user types
- **THEN** the typing goes to the dialog, and the page behind it receives none of it

#### Scenario: Two dialogs asked for at once
- **WHEN** two extensions ask for confirmation on the same window at the same time
- **THEN** one dialog shows, and the other shows once the first is answered

### Requirement: Dialog buttons and keys
A dialog's buttons SHALL sit at its bottom trailing corner, the default button last and filled with the accent colour. Esc SHALL choose the cancelling button and Return the default button, and each of those buttons SHALL show its key beside its title, as in Arc. A disabled default button SHALL ignore Return. A click outside the card SHALL do nothing.

#### Scenario: Esc
- **WHEN** a dialog with Cancel shows and the user presses Esc
- **THEN** the dialog closes as if Cancel was clicked

#### Scenario: Return on a disabled default
- **WHEN** the default button is disabled and the user presses Return
- **THEN** nothing happens

#### Scenario: Clicking outside
- **WHEN** the user clicks the dimmed window around the card
- **THEN** the dialog stays open

### Requirement: Destructive dialog buttons
A dialog MAY mark its default button as destructive, for an action that destroys something. A destructive default button SHALL be filled with the system's red in place of the accent colour, and SHALL otherwise behave as any default button.

#### Scenario: A destructive default
- **WHEN** a dialog's default button is marked destructive
- **THEN** it shows in red, last in the row, and Return chooses it

### Requirement: Dialog focus and accessibility
When a dialog opens, keyboard focus SHALL go to its first field, or to its default button when it has no field, and Tab SHALL move among the dialog's controls only. When it closes, focus SHALL return to where it was. VoiceOver SHALL announce it as a dialog with its title.

#### Scenario: Focus on opening
- **WHEN** a dialog with a name field opens
- **THEN** the field has keyboard focus

#### Scenario: Focus on closing
- **WHEN** a dialog opened while a page had focus closes
- **THEN** the page has focus again
