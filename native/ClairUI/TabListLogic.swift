// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import ClairHost
import Foundation

/// The tab list's logic (design D12). The list mirrors Chromium's tab strip,
/// which keeps the order; this only translates the sidebar's gestures.
enum TabListLogic {
  /// The tab strip index a tab dragged from `source` ends up at when dropped
  /// before row `destination` (SwiftUI's onMove offset, counted in the
  /// original list).
  static func moveTarget(from source: Int, to destination: Int, count: Int) -> Int? {
    guard source >= 0, source < count, destination >= 0, destination <= count else {
      return nil
    }
    let target = destination > source ? destination - 1 : destination
    return target == source ? nil : target
  }

  /// The tabs Close Tabs Below closes: every tab after `tabID`.
  static func tabsBelow(_ tabID: TabID, in tabs: [any ClairTab]) -> [TabID] {
    guard let index = tabs.firstIndex(where: { $0.tabID == tabID }) else {
      return []
    }
    return tabs[(index + 1)...].map(\.tabID)
  }

  // MARK: Peeks (add-peek design D4)

  /// Whether `tab` is a Peek, which has no row of its own.
  static func isPeek(_ tab: any ClairTab) -> Bool {
    tab.peekParentID != ClairTabIDNone
  }

  /// The tabs with a row in the sidebar: every tab but the Peeks, in order.
  static func rows(_ tabs: [any ClairTab]) -> [any ClairTab] {
    tabs.filter { !isPeek($0) }
  }

  /// The row highlighted while `activeTabID` is active: the tab's own, or its
  /// parent's while a Peek shows.
  static func highlightedRow(activeTabID: TabID, in tabs: [any ClairTab]) -> TabID {
    guard let active = tabs.first(where: { $0.tabID == activeTabID }), isPeek(active),
      tabs.contains(where: { $0.tabID == active.peekParentID })
    else { return activeTabID }
    return active.peekParentID
  }

  /// The tab a click on `row` activates: its Peek, if it has one, so the tab
  /// shows with its Peek as it was.
  static func tabToActivate(forRow row: TabID, in tabs: [any ClairTab]) -> TabID {
    peek(ofRow: row, in: tabs)?.tabID ?? row
  }

  /// The Peek of the tab with `row`, whose favicon the row shows as a badge.
  static func peek(ofRow row: TabID, in tabs: [any ClairTab]) -> (any ClairTab)? {
    guard let tab = tabs.first(where: { $0.tabID == row }), tab.peekID != ClairTabIDNone else { return nil }
    return tabs.first { $0.tabID == tab.peekID && $0.peekParentID == row }
  }

  /// A tab and its Peek as the card shows them.
  struct ShownPeek: Equatable {
    let parentID: TabID
    let peekID: TabID
  }

  /// The Peek the card shows while `activeTabID` is active: the active Peek
  /// over its parent. Selecting a row activates its Peek, so the parent is
  /// active only while its Peek closes: Chromium makes it active first, then
  /// waits for the Peek's page to unload, and the card closes the Peek at once.
  static func shownPeek(activeTabID: TabID, in tabs: [any ClairTab]) -> ShownPeek? {
    guard let active = tabs.first(where: { $0.tabID == activeTabID }), isPeek(active),
      tabs.contains(where: { $0.tabID == active.peekParentID && $0.peekID == active.tabID })
    else { return nil }
    return ShownPeek(parentID: active.peekParentID, peekID: active.tabID)
  }

  /// The tab strip index a row dragged from row `source` to row `target` (as
  /// `moveTarget` gives it) asks for: where the tab ends up once each tab is
  /// counted with its Peek, which moves with it.
  static func stripIndex(movingRow source: Int, toRow target: Int, in tabs: [any ClairTab]) -> Int? {
    var rows = rows(tabs)
    guard rows.indices.contains(source), target >= 0, target < rows.count else { return nil }
    let moving = rows.remove(at: source)
    rows.insert(moving, at: target)
    return rows[..<target].reduce(0) { count, row in
      count + 1 + (peek(ofRow: row.tabID, in: tabs) == nil ? 0 : 1)
    }
  }

  /// The URL Copy Link puts on the pasteboard.
  static func link(of tab: any ClairTab) -> String? {
    if let url = tab.url {
      return url.absoluteString
    }
    return tab.urlText.isEmpty ? nil : tab.urlText
  }
}
