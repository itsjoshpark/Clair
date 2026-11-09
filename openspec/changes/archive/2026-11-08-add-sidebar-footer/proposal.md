# Proposal

## Why

Arc's sidebar ends in a footer: the library button, the Space switcher and a plus button. Clair's had none, and its downloads button sat in the tools row under the URL field, only once something had been downloaded, where Arc users don't look for it. Recorded after the fact: the work shipped in PR #111, which grew from an icon-button refactor, before `CLAUDE.md` said when work needs a change.

## What Changes

- **A footer at the bottom of the sidebar,** 50 pt tall, as in Arc, whatever the tab list's length; the space above it still moves the window.
- **The downloads button moves into the footer** where Arc has its library button, and always shows. With nothing downloaded yet, its list says "No recent downloads".
- **A plus button at the footer's trailing end** opens a native menu with New Tab (⌘T), which opens the command bar as ⌘T does. Arc's plus also offers Spaces and folders, which Clair doesn't have.
- **A line between a scrolling tab list and the footer,** as in Arc.
- **The tools row** (pinned extensions and the extensions button) shows only while some extension has an action, and the tab list takes all the room it needs before the space above the footer.

**Out of scope:** a Space switcher, and the plus menu's other items.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `sidebar`: adds the footer and its plus menu; the downloads button always shows, in the footer; the "Many tabs" scenario names the footer.

## Impact

- **Native layer:** `SidebarFooter`, `DownloadsButton` and `DownloadsList` in `native/ClairUI/SidebarView.swift`, with `IconMenu` in `IconButton.swift` for the plus. No contract or engine change.
- **Tests:** the runtime `DownloadsTests` still covers the downloads button; a unit test covers when the line shows.
- **Users:** a Changie fragment.
