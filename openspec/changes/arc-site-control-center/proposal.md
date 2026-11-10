# Proposal

## Why

Clair shows pinned extensions as one row of fixed-size icons, with the full list behind a separate button. Arc wraps pinned extensions across the sidebar and lists every extension as a grid in its Site Control Center. Clair's Site Control Center is Chromium's page info bubble, which ClairUI can't add to, and it doesn't exist on the new tab page at all. Arc stops working on 2026-12-22, and this is a surface Arc users touch daily.

## What Changes

- **Pinned extensions wrap, as in Arc.** They become tiles that stretch to share the width of the sidebar, spread over as many rows as they need, using Arc's rule for how many go on each row. Unlike Arc, a single pinned extension and very wide sidebars keep the same separate row, rather than moving into the URL field.
- **A native Site Control Center.** The site-controls button opens a native popover with Arc's look: a grid of every extension with a pin badge on each, a tile for adding extensions, a "Site Info" pill that opens Chromium's page info, and a "…" menu.
- **The extensions button is removed.** Its list moves into the Site Control Center. Popups for unpinned extensions, and `chrome.action.openPopup()` for them, open beside the site-controls button. The pinned row shows only while something is pinned. **BREAKING (`ClairHost.h`):** the extensions button's anchor kind is removed.
- **A revealed sidebar waits for its popovers.** It stays revealed while the Site Control Center or the downloads list is open.
- **The site-controls button is on every tab,** including the new tab page. What doesn't apply is hidden or dimmed: "Site Info" is hidden on internal and file pages, and an extension off for the current tab is dimmed.
- **New icon.** The site-controls button uses `slider.horizontal.2.square`.
- **A not-secure icon, as in Arc.** On pages Chromium rates as not secure, a red `lock.slash.fill` shows at the leading end of the URL field. It's informational: hovering shows a tooltip, and it can't be clicked.
- **Dimmed extensions don't run.** An extension that's off for the current tab is dimmed and ignores a left click, in the sidebar and in the Site Control Center. Its right-click menu keeps working.

**Out of scope:**
- Native connection and permission controls. Page info stays Chromium's, and the URL field's camera, microphone, location and screen-capture indicators keep opening it directly.
- Arc's Share, Boost and Capture buttons, its Settings rows (Developer Mode, Block Ads & Trackers, Picture-in-Picture), and Clear Cache and Clear Cookies, which Clair doesn't have.
- Showing "Secure" on the pill. Its label stays "Site Info", the page info it opens shows the connection's state, and the not-secure icon is the only security signal in the sidebar.

## Capabilities

### New Capabilities

- `site-control-center`: the native popover opened by the site-controls button: its extension grid, pin badges, add tile, Site Info pill and "…" menu.

### Modified Capabilities

- `sidebar`:
  - "Site controls and indicators" opens the Site Control Center, on every tab.
  - "Extension actions" drops the extensions button, and pinned extensions wrap.
  - "Tooltips in Arc's wording" drops "Extensions".
  - A revealed sidebar stays revealed while its popovers are open.
  - The URL field shows an icon on pages that aren't secure.
- `extensions`: the list of every extension moves from the extensions button to the Site Control Center, for installing from a CRX, the API's popup anchor and the context menu.

## Impact

- **Native layer:** `native/ClairUI/SidebarView.swift` (the pinned row, the URL field's button), a new view for the Site Control Center, `AnchorResolver.swift`, and unit tests in `native/ClairUITests/`.
- **Contract and engine:** `native/ClairHost.h` loses `ClairAnchorKindExtensionsButton`, and `overlay/chrome/browser/clair/window/clair_extensions.mm` requests `ClairAnchorKindSiteControls` for unpinned popups. `ClairTab` gains `isNotSecure`, set in `clair_browser_bridge.mm`. The engine key changes, so `engine.yml` builds one new engine.
- **Tests:** the runtime test for pinning an extension goes through the Site Control Center (`tests/runtime/`).
- **Users:** a Changie fragment.
