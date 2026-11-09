# Tasks

Recorded after the fact: the work shipped in PR #111. Probe runs drove Arc or a packaged Clair with XCUITest, moving the pointer only, with a control case and the screenshots checked.

## 1. Measure Arc

- [x] 1.1 Measure where Arc reveals its hidden sidebar from beside the window: crossing the edge to 40–380 pt out, coming around the window to 30–300 pt out, above and below, from near and far starting points. Verified: the results are in design.md's Context.

## 2. Reveal

- [x] 2.1 Reveal after 80 ms of rest, restarted by moves in the strip, and hide 100 ms after the pointer leaves. Verified: `ClairUI` builds and its unit tests pass, including `mouseMoveInTheRevealStripDoesNotCrash` for the crash this found by hand.
- [x] 2.2 Treat the area beside the window as the inset, 50 pt or 250 pt, judged from the exit event's position. Verified: Clair probe run matched Arc for the strip, 40, 240 and 300 pt after crossing, and 30 and 100 pt from elsewhere.
- [x] 2.3 Follow the pointer with a local monitor only while the sidebar is hidden and the window is key; moves only; remove it with the window or view. Verified: measured with a packaged build: every move beside the window seen about 8 ms late, no global monitor needed, and no extra `mousemove` for the page.
- [x] 2.4 Update the sidebar spec. Verified: `openspec validate --all --strict` passes.

## 3. Release

- [x] 3.1 Add a Changie fragment. Verified: `.changes/unreleased/` has it.
