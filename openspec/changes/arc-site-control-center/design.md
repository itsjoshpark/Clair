# Design

## Context

See proposal.md, "Why". What stands in the way today:

- **The Site Control Center is Chromium's page info bubble,** shown by `showPageInfoAtAnchor:` in `clair_browser_bridge.mm`. ClairUI can't add to it. On internal and file pages Chromium shows only a bare `InternalPageInfoBubbleView`.
- **`ClairHost.h` already has what this change needs:** `extensionActions`, `runExtensionAction:anchor:`, `setExtensionAction:pinned:`, `contextMenuForExtension:`, `openURL:disposition:` (which opens `chrome://` URLs) and `showPageInfoAtAnchor:indicator:`.

**Arc, as measured** by driving it with XCUITest and real mouse events, with its accessibility frames:

| | Measured |
|---|---|
| Pinned tiles | 28 pt tall, 18 pt icon, 8 pt gaps both ways, stretching to share a row 16 pt narrower than the sidebar |
| Columns across | 4 at sidebars of 164–187 pt, 5 from 195 to 340 pt; from somewhere above 340 pt, pinned extensions move into the URL field |
| Tiles per row, 4 across | 2 → 2; 3 → 3; 4 → 4; 5 → 3+2; 6 → 3+3; 7 → 4+3; 8 → 4+4; 9 → 3+3+3; 10 → 4+4+2 |
| Popover | Content 236 pt wide with a 10 pt inset, attached below the button; 262×446 pt in all with Arc's sections and 10 extensions |
| Extensions section | Heading 17 pt tall, 10 pt above the grid; 4 columns of 48×32 pt tiles, 8 pt gaps |
| Pin badge | 14 pt, at +37, +21 from a tile's top-leading corner, so it overhangs 3 pt on each side; solid when pinned, faint on hover otherwise |
| Footer | 32 pt tall, a divider above it, a pill on the left and a 32 pt round "…" button on the right |

Arc's "Secure" pill opens the macOS certificate sheet. Its "…" menu offers Clear Cache, Clear Cookies, Manage Boosts…, New Boost…, Manage Extensions…, Add Extension… and All Site Settings….

## Goals / Non-Goals

**Goals:**
- Match Arc's pinned row and popover in layout and behaviour, using Clair's own colours and system popover material.
- Keep the engine change to removing one anchor kind; everything else is in `ClairUI`.

**Non-Goals:**
- Reordering pinned extensions by dragging.
- Changing where the downloads list opens.

## Decisions

### D1. A custom `Layout` for the pinned tiles, with the rule in a pure function

`PinnedExtensionsLayout` is a SwiftUI `Layout`. The rule, in a pure helper that unit tests cover:

```
maxColumns = max(1, min(5, floor((width + 8) / 37)))   // a tile at least 29 pt
rows       = ceil(count / maxColumns)
columns    = ceil(count / rows)
tileWidth  = (width - 8 * (columns - 1)) / columns
```

The rule reproduces every count measured in Arc, and 10 tiles at 5 across. With one extension it gives one full-width tile, as the owner asked; Arc moves a single pinned extension into its URL field instead. The cap of five holds at every width, since Clair never moves them into the URL field.

`sizeThatFits` returns the proposed width and the height of the rows, so the tab list moves down by itself. `.extensionAction` anchor frames keep working on each tile.

The 29 pt minimum is inferred: Arc's switch to 5 across is somewhere between sidebars of 187 and 195 pt, which is a tile minimum between 27.8 and 29.4 pt.

*Alternatives:* `LazyVGrid` with adaptive columns fills the first rows and can't express the "as few columns as those rows allow" rule. `ViewThatFits` would need every layout enumerated.

The tiles use `SidebarFill.field` as their fill, a corner radius of about 8 pt, and keep the highlight under the pointer that `sidebar` requires. The row sits 8 pt under the URL field, and the tab list 8 pt under the row, replacing the 6 and 4 pt that suited buttons without a visible edge.

### D2. A SwiftUI popover on the always-present anchor view

The popover is a `.popover(isPresented:attachmentAnchor:arrowEdge: .bottom)` attached to the invisible view the URL field already keeps where the button shows (`.anchorFrame(.siteControls)`). That's the same mechanism as the downloads list. Attaching it to the visible button would dismiss it when the button fades out.

A click on the button while the popover is open also reaches the button once the transient popover has closed, which would open it again. The button stops taking clicks while the popover is open, so that click only closes it, with no timing to get wrong.

*Alternative:* an `NSPopover` with its own controller, as Arc has. It gives the same result with more code.

### D3. Unpinned popups use the site-controls anchor kind

`ClairAnchorKindExtensionsButton` is removed from `ClairHost.h`, and `ClairAnchorKindDownloads` becomes 3. ClairUI passes `.siteControls` to `runExtensionAction(_:anchor:)` for an unpinned extension, and `ClairExtensions::ShowToolbarActionPopupForAPICall` requests `ClairAnchorKindSiteControls` for an action that isn't pinned. `AnchorControl.extensionsButton` and its `AnchorResolver` cases are removed. The kind only places the popup, and `ExtensionPopupWindow` closes on a click in its anchor rectangle whichever control that is.

*Alternative:* renaming the kind. The site-controls kind already names this place, so a new name would be a second kind for the same control. Keeping the stale name would avoid an engine build, but the owner preferred a correct contract.

### D4. Extension tiles

Tiles follow the measurements in Context. Unpinned extensions sort with `localizedStandardCompare`, in a pure helper. A tile click passes `pinned: false`, so its popup opens from the site-controls button whether the extension is pinned or not, as the click came from the popover. The list is built from `model.extensionActions`, so pinning reorders it live, as Arc does.

A tile in the popover and a pinned tile both ignore a left click while their action's `isEnabled` is false; the context menu still works on both. The context menu reuses `RowClickCatcher`. A pin badge appears under the pointer, so unpinned badges aren't in the accessibility tree until then; the runtime test hovers the tile first.

The grid scrolls beyond 8 rows, so the popover fits on a small display. That's Clair's choice; Arc wasn't measured with that many extensions.

### D5. "Site Info" opens Chromium's page info

The pill's label is always "Site Info", at the owner's choice, rather than Arc's "Secure", and it opens the same Chromium dialog the site-controls button opens today, which shows the connection's state. Clicking it calls `showPageInfo(at: .siteControls, indicator: [])`. The check for `chrome:`, `devtools:`, `view-source:` and `file:` mirrors `PageInfo::IsFileOrInternalPage`, in a pure helper.

### D6. Menu destinations

"Manage Extensions…" opens `chrome://extensions`, "Add Extension…" and the plus tile open `https://chromewebstore.google.com/`, and "All Site Settings…" opens `chrome://settings/content`, all with `open(_:disposition: .newForegroundTab)`.

### D7. The button shows on every tab and while the popover is open

`hasSiteControls` drops its `isNewTabPage` check and keeps `tab != nil`, for the moment before a window's first tab exists. The URL field's `showsButtons` also holds true while the popover is open, since the buttons otherwise depend on the window being key and the pointer being over the sidebar, and either can stop while the popover is up.

### D8. A revealed sidebar waits for its popovers

`BrowserWindowModel` gains a flag set while the Site Control Center or the downloads list is open. `BrowserRootView` won't start concealing a revealed sidebar while it's set, and rechecks the pointer when it clears.

### D9. The not-secure icon comes from Chromium's security level

`ClairTab` gains `isNotSecure`, true for Chromium's `WARNING` and `DANGEROUS` security levels, read in the tab snapshot through `chrome/browser/ssl/chrome_security_state_util.h`. Those levels cover plain HTTP, certificate errors and active mixed content, and exclude `localhost`, internal and file pages, so ClairUI needs no rules of its own about schemes.

`ProgressObserver` also overrides `DidChangeVisibleSecurityState` to call `tabChanged:`, so mixed content found after a load shows the icon.

The icon is informational: a plain image with a tooltip, not a control.

*Alternative:* deciding from the URL's scheme in ClairUI. It would miss certificate errors and mixed content, and would wrongly flag `http://localhost`.

### D10. Badge colours

Chromium reports a badge colour the extension didn't set as transparent and substitutes its own when it draws, picking black or white text for contrast. The bridge passed the transparent colour on, so the pinned tile drew white text with no background. The bridge now reports an unset background or text colour as nil, and a set background as opaque, as Chromium draws it. `ClairExtensionAction` gains `badgeTextColor` for `chrome.action.setBadgeTextColor`.

ClairUI draws Clair's default, white on the system red, when the extension sets no background. On a background the extension chose, it uses the extension's text colour, or else black or white, whichever has the higher WCAG contrast. This is a pure helper that unit tests cover.

*Alternative:* treating a transparent colour as unset in ClairUI alone. It would avoid an engine build, but would keep ignoring `setBadgeTextColor` and leave the bridge contradicting `ClairHost.h`.

## Risks / Trade-offs

- **[The 29 pt minimum is inferred]** → It only moves the switch from 4 to 5 across by a few points of sidebar width. The value is one constant.
- **[A runtime test depends on hover]** → Hidden views leave the accessibility tree, so the test must hover the URL field, then the tile, before finding the buttons.
- **[`ClairUI` and the engine must match the changed enum]** → The engine key includes `ClairHost.h`, so packaging only pairs `ClairUI` with the engine built for that header.
- **[SwiftUI popovers and revealed sidebars]** → The `BrowserRootView` guard (D8) is checked by hand, as a revealed sidebar needs a real pointer.

## Migration Plan

Nothing to migrate: pinned state lives in Chromium's extension preferences and doesn't change. Rolling back is reverting the change, which returns to the previous engine key.
