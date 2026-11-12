# Spec Delta

## MODIFIED Requirements

### Requirement: Install confirmation as a native sheet
Before an extension is installed, Clair SHALL ask in a Clair dialog (`dialogs`) on the window. The dialog SHALL show the extension's icon, the title "Add "<name>" to Clair?", the heading "It can:" followed by the extension's permissions as a list, and the buttons "Add Extension" (default, Return) and "Cancel" (Esc). The window SHALL stay blocked until the user answers.

#### Scenario: Confirming an install
- **WHEN** the user clicks "Add to Clair" on a store page
- **THEN** a sheet asks "Add "<name>" to Clair?" with the extension's permissions under "It can:", and pressing Return installs the extension

#### Scenario: Cancelling an install
- **WHEN** the install sheet is shown and the user presses Esc or clicks "Cancel"
- **THEN** the sheet closes, the extension isn't installed, and the store page shows it as not installed

#### Scenario: Extension without permissions
- **WHEN** the extension being installed asks for no permissions
- **THEN** the sheet shows the title and buttons without the "It can:" list

#### Scenario: Many permissions
- **WHEN** the extension being installed asks for more permissions than fit
- **THEN** the list scrolls inside the dialog, and the buttons stay visible

### Requirement: Remove confirmation as a native sheet
When an extension is removed through a path that asks for confirmation, such as the store's "Remove from Clair" button, Clair SHALL ask in a Clair dialog (`dialogs`) on the window. The dialog SHALL have the title "Remove "<name>" from Clair?", the extension's icon, a destructive "Remove Extension" button (Return) and "Cancel" (Esc), and no "report abuse" option.

#### Scenario: Removing from the store
- **WHEN** the user clicks "Remove from Clair" on an installed extension's store page and clicks "Remove Extension"
- **THEN** the extension is removed, its button leaves the sidebar, and the store page shows it as not installed

#### Scenario: Keeping the extension
- **WHEN** the remove sheet is shown and the user presses Esc
- **THEN** the extension stays installed
