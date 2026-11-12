# Tasks

This change is `ClairUI` only: the engine key doesn't change. "CI" is the merge gate in `ci.yml`. "By hand" means the owner launches a test build of the branch; looks compared with Arc are checked there with `tests/probe/`. Because it changes views the runtime suite drives, `quality.yml` runs on the branch before merging (`gh workflow run quality.yml --ref <branch>`). D-numbers are `design.md`'s decisions.

## 1. The dialog

- [ ] 1.1 Add `ClairDialog.swift` with `ClairDialogView` (D1): the card, its icon, title, message and content slot, and the button row from roles, with the Esc and Return capsules. Verify with unit tests in a new `ClairDialogTests` in CI: the roles map to Esc and Return, a destructive default is marked destructive, and a disabled default has no Return key equivalent.
- [ ] 1.2 Add `ClairDialogPresenter` (D1, D2): the clear sheet window on its parent window, the queue that shows one at a time, dismissing without an answer, swapping a card's content and returning, and saving and restoring first responder. Verify with unit tests in CI (a second request waits for the first; a dismissed dialog isn't answered; `cancelAll` answers every pending request as cancelled), and by hand that the card shows with no system background behind it, on a browser window and on the Settings window. If macOS draws its own background, use the fallback in the design's risks and update `design.md`.
- [ ] 1.3 Check the card against Arc's dialogs by hand, side by side in Light and Dark Mode: corner radius, shadow, padding, the buttons' size and capsules, and the destructive colour. Check with VoiceOver that it is announced as a dialog with its title, and with the keyboard that Tab stays inside it. Verify by the owner accepting the comparison.

## 2. The extension prompts

- [ ] 2.1 Replace `ExtensionPromptAlert` with a builder of `ClairDialogView`s for install, remove and other prompts (D3), with the same wording, the extension's icon, and the permission list scrolling at 200 pt. Make `ExtensionPromptSheets` use the presenter, and have `BrowserWindowController` own it. Verify that `ExtensionPromptTests` pass in CI, adapted to the new view, with every existing case kept.
- [ ] 2.2 Give the card's title and buttons accessibility identifiers, and update the runtime suite's helpers and the extension tests that answer these prompts. Add a runtime test that, with an install dialog showing, a click on a tab row does nothing, typing doesn't reach the page, and a second browser window still responds. Verify with a `quality.yml` run on the branch.

## 3. Release notes and integration

- [x] 3.1 Add a Changie fragment (`changie new`, kind Changed) for the extension prompts' new look. Verify that it's in the PR.
- [ ] 3.2 Run `openspec validate --all --strict` and the merge gate. Verify that CI and the quality checks pass.
