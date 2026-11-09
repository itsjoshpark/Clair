# Design

## Context

The sidebar was a column of top row, URL field, tools row (extensions and downloads) and tab list, padded 8 pt at the bottom. Arc's footer was measured on 2026-11-08 in the owner's Arc, from its accessibility frames and window screenshots at 2x.

**Arc's footer, measured:** a 50 pt band at the bottom of the sidebar; the library button is 32 pt, 8 pt from the leading edge and 9 pt from the bottom; the plus is the same size and inset at the trailing edge. The library glyph is 14.5 × 16.5 pt; the plus is 14 × 14 pt with 2 pt arms, which is SF Symbols' `plus` at 17 pt medium, in a grey of about 125 on the light sidebar (Clair's `.secondary`). The library button's hover fill is 32 pt with a corner radius of about 6 pt, as Clair's icon buttons'. With a short window, the tab list scrolls behind a 1 pt line on the footer's top edge, across the sidebar: about 4% black in Light Mode and 8% white in Dark Mode. The plus has no tooltip or accessibility label.

## Decisions

### D1. Layout

`SidebarFooter` is the last child of the sidebar's column, 50 pt tall with 8 pt side insets, after a `Spacer`, so it stays at the bottom however short the list is. The tab list gets `layoutPriority(1)`: otherwise the spacer and the list, both flexible, split the free height and the list scrolls at half the room.

### D2. The downloads button always shows

As Arc's library button does. It used to appear only with downloads, which made the footer empty most of the time. Its list says "No recent downloads" when empty, above "Show All Downloads". The glyph is `arrow.down.circle` at 18 pt medium (the owner's choice, close to the library glyph's height).

### D3. The plus menu

An `IconMenu` (SwiftUI `Menu` in the icon buttons' style) with one item, New Tab, carrying ⌘T as its shortcut; it calls the same action as ⌘T, which opens the command bar for a new tab. Clair has no Spaces or folders yet. Its tooltip is "New".

- Alternative: an `NSMenu` placed above the button, so the menu never covers it near the bottom of the screen. Built and reverted at the owner's request in favour of SwiftUI's own menu.

### D4. The line above the footer

Shown while the list is shorter than its rows: the list's laid-out height against `TabList.contentHeight(tabCount:)`, so it follows both the window's height and the number of tabs. 1 pt, `Color.primary` at 4% (Light) or 8% (Dark), as measured.

### D5. The tools row

With downloads gone from it, it shows only while some extension has an action. The "New Tab" row then starts 6 pt below it, as the row starts 6 pt below the URL field; the extension icons sit inside 32 pt buttons with no visible edge, so the old 8 pt looked larger than it was.

## Risks / Trade-offs

- **The footer takes 50 pt from the tab list** even with no downloads, as in Arc, so the tab list ends where Arc's does.
- **SwiftUI's menu can slide over its button** near the bottom of the screen. Accepted (D3).
