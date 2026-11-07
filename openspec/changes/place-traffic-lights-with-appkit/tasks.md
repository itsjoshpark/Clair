# Tasks

Per CLAUDE.md, a task that needs a build is done only once CI passes on it. The engine for this change's key is built by `engine.yml` on the owner's Mac, which the owner starts or authorizes.

## 1. Engine: the title bar frame and the contract

- [ ] 1.1 Add the `ClairWindowControls` protocol to `native/ClairHost.h` (D2), with its comments. Verify that `ClairUI` builds against it and that `ClairHostObjCxxTests.mm` still compiles.
- [ ] 1.2 In `clair_native_window.{h,mm}`, add `ClairWindowFrame` and `+frameViewClassForStyleMask:` (D1), and make `ClairNativeWindow` adopt `ClairWindowControls`, laying out its theme frame at once when either property changes (D2). Verify that `./build.sh fetch prepare` applies cleanly in the patch check and that the engine compiles in `engine.yml`.
- [ ] 1.3 Spike on the built engine, before 2.1: from a scratch `ClairUI` change that removes `TrafficLights` and only sets `windowControlsOrigin` to (12, 16), read the buttons' accessibility frames. Verify that they read 12/35/58, y 16, as Arc's do, and stay there after a title change, a key change and a resize. If they're a point off, adjust D1's inset or height and record the measured offset in design.md.

## 2. Native layer

- [ ] 2.1 Replace `TrafficLights` in `BrowserRootView.swift` with setting `windowControlsOrigin` and `windowControlsHidden` from the sidebar's frame (D3), removing the frame setting and its observers. Make the fake browser's window in `ClairUITests` adopt `ClairWindowControls`, and add unit tests for the shown, half-hidden, hidden, revealed and page full-screen values. Verify that `ClairUI`'s tests pass in CI.
- [x] 2.2 Update `replace-browser-window`'s design.md (D4's traffic-light note) to point to this change instead of describing re-placing after each window update. Verify that `openspec validate --strict` passes for both changes.

## 3. Verification

- [ ] 3.1 Add a runtime test to `NativeWindowStructureTests`: open a page, navigate to one with another title, make another window key and back, and check the buttons' accessibility frames against the sidebar's each time. Verify that `quality.yml`, dispatched on the branch, passes, and that the test fails when `ClairWindowFrame`'s inset is changed on purpose.
- [ ] 3.2 Compare with Arc side by side with the XCUITest probe (CLAUDE.md): the buttons' accessibility frames shown and revealed, 60 fps recordings of Cmd+S and the hover reveal with no frame showing the buttons at AppKit's default spot, and clicks on the top-row buttons and the URL field's top edge reaching them. Verify each item and note the results in the PR.

## Workflow follow-up

- Archive this change after `replace-browser-window` is archived, since this delta adds to the `browser-window` capability that change introduces.
