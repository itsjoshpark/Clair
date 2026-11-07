# Tasks

Per CLAUDE.md, a task that needs a build is done only once CI passes on it. The engine for this change's key is built by `engine.yml` on the owner's Mac, which the owner starts or authorizes.

## 1. Engine: the title bar frame and the contract

- [ ] 1.1 Add the `ClairWindowControls` protocol to `native/ClairHost.h` (D2), with its comments. Verify that `ClairUI` builds against it in CI.
- [x] 1.2 In `clair_native_window.{h,mm}`, add `ClairWindowFrame` and `+frameViewClassForStyleMask:` (D1), and make `ClairNativeWindow` adopt `ClairWindowControls`, laying out its theme frame at once when either property changes (D2). Verify that `./build.sh fetch prepare` applies cleanly in the patch check and that the engine compiles in `engine.yml`.
- [x] 1.3 Spike on the built engine, before 2.1: from a scratch `ClairUI` change that removes `TrafficLights` and only sets `windowControlsOrigin` to (12, 16), read the buttons' accessibility frames. Verify that they read 12/35/58, y 16, as Arc's do, and stay there after a title change, a key change and a resize. If they're a point off, adjust D1's inset or height and record the measured offset in design.md.

- [ ] 1.4 Add D1's fallback to `ClairNativeWindow`: without the re-tiling methods, hide the buttons while `windowControlsOrigin` keeps changing, re-set the style mask and show them once it has been still for 150 ms, and log once per launch with `os_log` under `dev.joshuapark.Clair`. Verify that the engine compiles in `engine.yml`; that on macOS 27, with `CLAIR_WINDOW_CONTROLS_FALLBACK=1` in Clair's environment, a 60 fps recording shows the buttons hidden during Cmd+S and the reveal and at their place once each ends, and `log show --predicate 'subsystem == "dev.joshuapark.Clair"'` shows the message once; and that without the scratch change the recordings match task 1.3's. Record in design.md whether re-setting the style mask re-tiled the title bar.

## 2. Native layer

- [ ] 2.1 Replace `TrafficLights` in `BrowserRootView.swift` with setting `windowControlsOrigin` and `windowControlsHidden` from the sidebar's frame (D3), removing the frame setting and its observers. Make the fake browser's window in `ClairUITests` adopt `ClairWindowControls` so the tests build, and remove `WindowControlsTests` and the protocol's entry in `ClairHostObjCxxTests.mm` (D4). Verify that `ClairUI`'s build and tests pass in CI.
- [x] 2.2 Update `replace-browser-window`'s design.md (D4's traffic-light note) to point to this change instead of describing re-placing after each window update. Verify that `openspec validate --strict` passes for both changes.

- [ ] 2.3 Lay the top row out from the buttons' accessibility frames (D3b): its centre line, the hide-sidebar button's place, the compact threshold and the narrowest sidebar. Verify with `run-local.sh` on macOS 27 that nothing moves from today except the owner's wider gap (hide-sidebar at x 81, the row centred at y 24, compact below 218, narrowest 164); and, with D1's requested place moved 6 pt down and 10 pt right in a scratch build, that the row's centre follows the buttons and the hide-sidebar button and the narrowest compact row stay clear of the zoom button.

## 3. Verification

- [ ] 3.1 Make `testWindowControlsStayInPlace` in `NativeWindowStructureTests` the change's one automated test (D4): the close button 12 and 16 from the sidebar's corner, the top row centred on it and starting after the zoom button, checked at launch and after the page's title changes. Verify that `quality.yml`, dispatched on the branch, passes. (Its earlier version already failed as expected with the place moved 7 pt on purpose, on the throwaway branch `scratch/traffic-lights-offset-check`.)
- [ ] 3.2 Compare with Arc side by side with the XCUITest probe (CLAUDE.md): the buttons' accessibility frames shown and revealed, 60 fps recordings of Cmd+S and the hover reveal with no frame showing the buttons at AppKit's default spot, and clicks on the top-row buttons and the URL field's top edge reaching them. Verify each item and note the results in the PR.

## Workflow follow-up

- Archive this change after `replace-browser-window` is archived, since this delta adds to the `browser-window` capability that change introduces.
