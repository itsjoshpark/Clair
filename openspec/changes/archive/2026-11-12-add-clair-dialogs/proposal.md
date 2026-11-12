# Proposal

## Why

Clair asks its questions with macOS's standard alert, whose layout, icon size and buttons can't be changed much: the extension prompts already work around its 64 pt icon. Arc's dialogs are its own cards, with the keys shown on the buttons. Spaces and Profiles, the next changes, need several dialogs (a name, a confirmation, a list to manage), and one of them can't be built as an alert at all. A dialog of Clair's own, built once, serves them all.

## What Changes

- **Clair's own dialog.** A card with Clair's content and styling, attached to its window as Arc's dialogs are: an optional icon, a title, a message, room for a field or other content, and buttons that show Esc and Return beside their titles. It blocks only its own window, and one shows at a time.
- **The extension prompts use it.** The install, remove and permission prompts keep their wording, icon, permission list and behaviour, in the new card.

**Out of scope:**
- The update prompts. They show without a window and the updater waits on their answer in place, so moving them means reworking the update flow.
- Chromium's own dialogs, such as JavaScript alerts, HTTP authentication and permission bubbles.
- Restyling the dimming and the open and close animation, which macOS draws for a sheet.

## Capabilities

### New Capabilities

- `dialogs`: Clair's own dialogs: how they look, attach to and block their window, and handle keys, focus and accessibility.

### Modified Capabilities

- `extensions`: "Install confirmation as a native sheet" and "Remove confirmation as a native sheet" ask in a Clair dialog, where they named macOS's alert, and a long permission list scrolls inside it.

## Impact

- **`ClairUI` only:** a new `ClairDialog.swift`; `ExtensionPromptSheets.swift` and `BrowserWindowController.swift` change. No engine change, so the engine key stays.
- **Tests:** `ExtensionPromptTests` and the runtime suite's extension tests follow the new view.
- **Later changes:** `add-spaces` and `add-profiles` build their dialogs on this one, so it lands first.
