# Design

## Context

See proposal.md, "Why". What shapes the approach:

- **Arc's dialogs are macOS sheets with Arc's own content.** The accessibility tree shows each (new profile, rename, delete, the confirmations) as a sheet of its window. They are centred cards: an icon, a title, a paragraph, sometimes a field, then Cancel with an "ESC" capsule and a filled default button with a "↩" capsule, red when it destroys something. Sizes seen: 450×426 and 496×255 pt. The `add-spaces` change's `arc-reference.md` has their text.
- **Clair's prompts today:** `ExtensionPromptAlert` builds an `NSAlert` per prompt, and `ExtensionPromptSheets` queues them per window, showing one at a time with `beginSheetModal(for:)`, and can dismiss one without an answer when Chromium no longer needs it. `UpdateAlerts` runs app-modal alerts with `runModal()` and returns their answer in place.
- **Extension prompts come from Chromium** through `-[ClairWindow showExtensionPrompt:]` and are answered through `-[ClairBrowser answerExtensionPrompt:accepted:]`. That contract doesn't change.

## Goals / Non-Goals

**Goals:**
- One dialog component whose card is fully Clair's, for this and later changes.
- Keep what AppKit gives a sheet: modality to its window, the focus loop, and the dialog's accessibility role.

**Non-Goals:**
- A dialog drawn inside the window's own view hierarchy.
- One dialog on top of another.

## Decisions

### D1. A sheet with Clair's own content

`ClairDialog.swift` adds:

- **`ClairDialogView`,** the SwiftUI card: an optional icon, a title, a message, a content slot (a field, a permission list, or a later change's larger content), and a button row built from roles: cancel (Esc), default (Return) and destructive default (Return, drawn in the system's red). The two keyed buttons show their key in a small capsule, as Arc's do. Its metrics are Arc's, measured from its extension dialogs in Light and Dark Mode. Arc tints the card, and in Dark Mode the Cancel button and its key, with the Space's colour; until Clair has Spaces, the card uses the accent colour.
- **`ClairDialogPresenter`,** one per window: it hosts the card in a borderless, clear `NSWindow` and shows it with `beginSheet(_:)` on its window, so AppKit provides the centring, the dimming, the modality and the focus loop. It queues requests, showing one at a time, and can dismiss the one showing without an answer. This is `ExtensionPromptSheets`' queue, generalised.
- **Swapping content:** a dialog can replace its card's content and return to it, for a question asked from inside a larger dialog. No dialog opens on top of another.

- **Why not `NSAlert`:** its layout, icon size, buttons and key hints can't be styled to match Arc's.
- **Why a sheet and not a view drawn in the window:** modality, focus, and VoiceOver's dialog role come from AppKit, it needs no layering over the page views, and it works the same on the Settings window.

### D2. Keys and focus

The card handles Esc and Return itself, through the buttons' key equivalents, so a disabled default button ignores Return. First responder goes to the first field, or else to the default button. The presenter records the window's first responder before showing and restores it after, as the command bar does for the page.

### D3. The extension prompts move over unchanged in behaviour

`ExtensionPromptAlert` becomes `ExtensionPromptDialog`, a builder of the card's pages with the same three cases and wording, with typographic quotes around the name as in Arc's titles. Remove Extension is a plain default button, not marked destructive, as Arc's isn't. The permission list is a scrolling list capped at the current 200 pt, so the buttons stay visible. The queue and `cancelAll` move to the presenter, which serves every dialog on the window; `ExtensionPromptSheets` keeps the prompts' IDs, answers Chromium once per prompt, and keeps `dismiss`. `BrowserWindowController` owns the window's presenter, cancels everything on it when the window closes, and hands it to later changes' dialogs.

The runtime suite raises a real install dialog without Google's servers: `make-crx.py` packs a fixture extension as a CRX3 file signed with a new key (standard library and `openssl`), the test server serves it as `application/x-chrome-extension`, and Clair runs with ungoogled-chromium's `--extension-mime-request-handling=always-prompt-for-install`.

### D4. The update prompts stay

`UpdateAlerts` shows with no window open and `UpdateController` waits on `askToRestart` in place. A window-less dialog and an asynchronous update flow are a separate change.

## Risks / Trade-offs

- **[macOS draws the dimming and the sheet's animation]** → Accepted; Arc lives with the same.
- **[A clear sheet window may still get a system background or shadow]** → Task 1.2 checks it by hand first; the fallback is the system's sheet shape with Clair's content inside it, which is what Arc appears to do.
- **[The runtime suite finds the prompts by their alert's elements]** → Task 2.2 gives the card's title and buttons stable identifiers and updates the helpers.
