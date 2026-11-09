# Tasks

Recorded after the fact: the work shipped in PR #111. "By hand" means a check through `scripts/run-local.sh`; probe runs drove Arc and Clair with XCUITest, moving the pointer only. "quality.yml" means a run dispatched on the branch (`gh workflow run quality.yml --ref refactor/shared-icon-button`).

## 1. Measure Arc

- [x] 1.1 Measure Arc's footer: band height, the library and plus buttons' frames, insets, glyph sizes and grey, hover fill, and the line above it in Light and Dark Mode. Verified: values recorded in design.md's Context.

## 2. Footer

- [x] 2.1 Add `SidebarFooter` at the bottom of the sidebar with the downloads button, and give the tab list layout priority. Verified: `ClairUI` builds and its unit tests pass; the owner checked the footer and its buttons in a local build.
- [x] 2.2 Always show the downloads button, with "No recent downloads" in an empty list, and update the sidebar spec. Verified: `openspec validate --all --strict` passes, and `DownloadsTests` pass in quality.yml (run 42546108466).
- [x] 2.3 Add the plus button's `IconMenu` with New Tab (⌘T). Verify by hand: the menu shows New Tab ⌘T, and choosing it behaves as ⌘T does (the command bar in new-tab mode). Verified: signed off by the owner (2026-11-08).
- [x] 2.4 Show the line above the footer while the list scrolls, following the tab count. Verify: unit tests `TabListOverflowTests` pass, and by hand the line shows with a long list and goes when tabs are closed, in Light and Dark Mode. Verified: the unit tests pass; the hand check signed off by the owner (2026-11-08).
- [x] 2.5 Show the tools row only with extensions, with 6 pt above the "New Tab" row. Verified: signed off by the owner (2026-11-08).

## 3. Release

- [x] 3.1 Add a Changie fragment. Verified: `.changes/unreleased/` has it.
