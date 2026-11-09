# Tasks

Recorded after the fact: the work shipped in PR #111. "By hand" means a check through `scripts/run-local.sh`; probe runs drove Arc and Clair with XCUITest, moving the pointer only. "quality.yml" means a run dispatched on the branch (`gh workflow run quality.yml --ref refactor/shared-icon-button`).

## 1. Measure Arc

- [x] 1.1 Measure Arc's footer: band height, the library and plus buttons' frames, insets, glyph sizes and grey, hover fill, and the line above it in Light and Dark Mode. Verified: values recorded in design.md's Context.

## 2. Footer

- [x] 2.1 Add `SidebarFooter` at the bottom of the sidebar with the downloads button, and give the tab list layout priority. Verified: `ClairUI` builds and its unit tests pass; the owner checked the footer and its buttons in a local build.
- [ ] 2.2 Always show the downloads button, with "No recent downloads" in an empty list, and update the sidebar spec. Verify: `openspec validate --all --strict` passes (done), and `DownloadsTests` pass in quality.yml.
- [ ] 2.3 Add the plus button's `IconMenu` with New Tab (⌘T). Verify by hand: the menu shows New Tab ⌘T, and choosing it opens the command bar for a new tab. (The owner has checked its hover highlight, not the menu.)
- [ ] 2.4 Show the line above the footer while the list scrolls, following the tab count. Verify: unit tests `TabListOverflowTests` pass (done), and by hand the line shows with a long list and goes when tabs are closed, in Light and Dark Mode.
- [ ] 2.5 Show the tools row only with extensions, with 6 pt above the "New Tab" row. Verify by hand: no tools row without extensions, and the gap with one.

## 3. Release

- [x] 3.1 Add a Changie fragment. Verified: `.changes/unreleased/` has it.
