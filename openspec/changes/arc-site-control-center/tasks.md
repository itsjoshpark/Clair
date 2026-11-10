# Tasks

Group 1 changes the engine key, so build the engine first and push docs afterwards, as `CLAUDE.md` describes. "CI" is the merge gate in `ci.yml`. "By hand" means the owner launches a test build of the branch; pointer-driven behaviour is checked there. `quality.yml` runs on the branch before merging (`gh workflow run quality.yml --ref <branch>`).

Suggested order: 1, 2, 3, 4, then 5. Groups 2 and 3 can start in `ClairUI` against `FakeBrowser` while the engine builds.

## 1. Contract and engine

- [x] 1.1 Remove `ClairAnchorKindExtensionsButton` from `native/ClairHost.h`, renumber `ClairAnchorKindDownloads` to 3, and correct the comment on `runExtensionAction:anchor:` (D3). Make `ClairExtensions::ShowToolbarActionPopupForAPICall` in `overlay/chrome/browser/clair/window/clair_extensions.mm` request `ClairAnchorKindSiteControls` for an unpinned action. In ClairUI, pass `.siteControls` for an unpinned extension, remove `AnchorControl.extensionsButton` and its `AnchorResolver` cases, and update `FakeBrowser` and `SidebarLogicTests`. Verify in CI that ClairUI's unit tests pass and that an unpinned action resolves to the site controls.
- [x] 1.2 Add `isNotSecure` to `ClairTab` in `native/ClairHost.h` and set it in `clair_browser_bridge.mm`'s tab snapshot, adding any build dependency it needs. Override `DidChangeVisibleSecurityState` in `ProgressObserver` to refresh the tab (D9). Update `FakeBrowser`. Verify in CI that ClairUI's unit tests pass, and by the engine build in 1.3.
- [x] 1.3 Build the engine with `gh workflow run engine.yml -f ref=<branch>`. Verify that `chromium-engine-<key>` is published and CI's engine check passes.

## 2. Pinned extensions wrap

- [x] 2.1 Add the pure helper for columns, rows and tile width (D1). Verify with unit tests in CI, covering the counts 1–10 at 4 across, 10 at 5 across, a row too narrow for one tile, and the cap of five at a very wide row.
- [x] 2.2 Add `PinnedExtensionsLayout` and the pinned tile (D1): 28 pt tall, 18 pt icon, 8 pt gaps, the field fill, the highlight under the pointer and the badge, with each tile's `.extensionAction` anchor frame. A dimmed tile ignores a left click (D4). Replace `ToolsRow`'s `HStack` with it and remove the extensions button. Show the row only while something is pinned, and set the 8 pt spacing above and below it. Verify with a unit test of the `Layout`'s reported height, passing in CI, and by hand: 1, 5 and 10 pinned, resizing the sidebar across the 4-to-5 switch, and the tab list moving down.
- [x] 2.3 Drop "Extensions" from the sidebar's tooltips, leaving nothing that refers to the removed button. Verify by searching `ClairUI` for `clair.extensions` and `showsExtensions`, with no matches.

## 3. The Site Control Center

- [x] 3.1 Add the pure helpers for tile order (D4) and for when "Site Info" shows (D5). Verify with unit tests in CI: pinned first in their order, then A–Z; hidden for `chrome:`, `devtools:`, `view-source:` and `file:`, shown for `http:` and `https:`.
- [x] 3.2 Add the popover's view: the "Extensions" heading, the grid of 48×32 pt tiles with name tooltips and dimming, the pin badges, the plus tile and scrolling beyond 8 rows (D4), with the footer's "Site Info" pill and "…" menu (D5, D6). Verify by hand against Arc side by side: layout, a pinned and an unpinned badge, a dimmed tile.
- [x] 3.3 Open it from the site-controls button on the always-present anchor view (D2), and change the button to `slider.horizontal.2.square`. Make a click on the button while open close it. Verify by hand: opening, clicking the button again, Esc and clicking outside.
- [x] 3.4 Show the button on the new tab page and keep it shown while the popover is open (D7). Verify by hand on the new tab page: the button shows, the popover opens, and "Site Info" is hidden.
- [x] 3.5 Keep a revealed sidebar revealed while the Site Control Center or the downloads list is open (D8). Verify by hand for both: open from a revealed sidebar, move the pointer over the page, then close the popover and see the sidebar conceal.

- [x] 3.6 Add the URL field's red `lock.slash.fill` icon at its leading end, with the "Site is not secure" tooltip and VoiceOver label, as a plain image rather than a control (D9). Verify with a unit test of a pure helper that it shows only for a tab with `isNotSecure`, passing in CI, and by hand against Arc: an HTTP site's icon position and colour, an expired certificate after proceeding, no icon on `localhost`, the tooltip on hover, and no response to a click.

## 4. Popups, menus and tests

- [x] 4.1 Wire the tile's click, the pin badge and the `RowClickCatcher` context menu to the existing `SidebarActions`, and "Site Info" and the "…" menu's items to `showPageInfo` and `open`. Verify by hand: a popup from a tile opens beside the site-controls button, clicking that button then closes only the popup, right-clicking a tile shows the extension's menu, "Site Info" opens Chromium's page info, and each menu item opens its page.
- [x] 4.2 Update `ExtensionActionTests` to pin through the Site Control Center: hover the URL field, open `clair.siteControls`, hover the tile and click its "Pin" badge. Verify with a `quality.yml` run on the branch.
- [x] 4.3 Add a Changie fragment (`changie new`) for the wrapped pinned extensions and the new Site Control Center. Verify that it's in the PR.

## 5. Integration

- [x] 5.1 Run `openspec validate --all --strict` and the merge gate, and verify that CI passes.
- [x] 5.2 Run `quality.yml` on the branch and verify that it passes before merging.

## 6. Badge colours and polish

- [x] 6.1 Report unset badge colours as nil and a set background as opaque in `clair_extensions.mm`, and add `badgeTextColor` to `ClairExtensionAction` (D10). Build the engine. Verify that `chromium-engine-<key>` is published and CI's engine check passes.
- [x] 6.2 Draw the badge with the default black on white (white on near-black in Dark Mode), or the extension's colours with contrasting text, through a pure helper (D10). Verify with unit tests in CI, and by hand in Light and Dark Mode with the default colours, a light background and a set text colour.
- [x] 6.3 Add a divider between "Add Extension…" and "All Site Settings…", size the URL field's glyphs to Arc's (the square 16 pt and the link 14.5 pt across, drawn, with the square at regular weight), and draw the tiles' and pill's focus rings 2 pt wide with their rounded corners. Verify by hand against Arc.
- [x] 6.4 Make the runtime test move across the tile until its pin badge shows. Verify with a `quality.yml` run on the branch.

## Workflow follow-up

- Archive the change after it merges.
