# Spec Delta

## Purpose

Clair's own dialogs: a card drawn inside the window it belongs to, in Arc's style, used where Clair asks the user for a name, a confirmation or a small set of edits, in place of macOS's standard sheets and alerts.

## ADDED Requirements

### Requirement: Dialogs are drawn in their window
A Clair dialog SHALL show as a rounded card centred in the window it belongs to, over a dimmed view of the window's content, and SHALL move and resize with that window. It SHALL NOT be a macOS sheet or alert. While it shows, the rest of that window SHALL NOT respond to clicks or keys, and other windows SHALL stay usable.

#### Scenario: Showing a dialog
- **WHEN** a dialog opens in a browser window
- **THEN** a card shows centred over the dimmed sidebar and page, and clicking a tab row behind it does nothing

#### Scenario: Another window
- **WHEN** a dialog shows in one browser window and the user clicks another browser window
- **THEN** the other window becomes key and works as usual

#### Scenario: Keys don't reach the page
- **WHEN** a dialog shows and the user types
- **THEN** the typing goes to the dialog, and the page behind it receives none of it

### Requirement: Dialog buttons and keys
A dialog's buttons SHALL sit at its bottom trailing corner, the default button last and filled with the accent colour, or with red when it destroys something. Esc SHALL choose the cancelling button and Return the default button, and each of those buttons SHALL show its key beside its title, as in Arc. A disabled default button SHALL ignore Return. A click on the dimmed area SHALL do nothing.

#### Scenario: Esc
- **WHEN** a dialog with Cancel shows and the user presses Esc
- **THEN** the dialog closes as if Cancel was clicked

#### Scenario: Return on a disabled default
- **WHEN** the default button is disabled and the user presses Return
- **THEN** nothing happens

#### Scenario: Clicking outside
- **WHEN** the user clicks the dimmed area around the card
- **THEN** the dialog stays open

### Requirement: Dialog focus and accessibility
When a dialog opens, keyboard focus SHALL go to its first field, or to its default button when it has no field, and Tab SHALL move among the dialog's controls only. When it closes, focus SHALL return to where it was. VoiceOver SHALL announce it as a dialog with its title, and SHALL NOT reach the content behind it. With Reduce Motion on, it SHALL appear and disappear without scaling.

#### Scenario: Focus on opening
- **WHEN** a dialog with a name field opens
- **THEN** the field has keyboard focus

#### Scenario: Focus on closing
- **WHEN** a dialog opened from the command bar's field closes
- **THEN** the page or field that had focus before has it again
