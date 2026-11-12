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

  /// The tabs Close Tabs Below closes: every tab after `tabID` and its Peek,
  /// which stays (add-peek design D8).
  static func tabsBelow(_ tabID: TabID, in tabs: [any ClairTab]) -> [TabID] {
    let last = peek(ofRow: tabID, in: tabs)?.tabID ?? tabID
    guard let index = tabs.firstIndex(where: { $0.tabID == last }) else {
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

  /// The number of rows: every tab but the Peeks.
  static func rowCount(_ tabs: [any ClairTab]) -> Int {
    tabs.reduce(0) { $0 + (isPeek($1) ? 0 : 1) }
  }

  /// Each row's Peek, by the row's tab ID, in one pass over the tabs: the
  /// sidebar's list asks for every row's on each update.
  static func peeksByRow(_ tabs: [any ClairTab]) -> [TabID: any ClairTab] {
    var byID: [TabID: any ClairTab] = [:]
    for tab in tabs { byID[tab.tabID] = tab }
    var peeks: [TabID: any ClairTab] = [:]
    for tab in tabs where tab.peekID != ClairTabIDNone {
      if let peek = byID[tab.peekID], peek.peekParentID == tab.tabID {
        peeks[tab.tabID] = peek
      }
    }
    return peeks
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

  /// The Peek the card shows while `activeTabID` is active: over its parent,
  /// while either is active. A parent that becomes active some other way, as
  /// when the tab next to it closes, shows with its Peek at once, and the
  /// engine then activates the Peek. A Peek that's closing has left its
  /// parent's `peekID`, so the card closes it as soon as the parent is active,
  /// without waiting for its page to unload.
  static func shownPeek(activeTabID: TabID, in tabs: [any ClairTab]) -> ShownPeek? {
    guard let active = tabs.first(where: { $0.tabID == activeTabID }) else { return nil }
    if isPeek(active) {
      guard tabs.contains(where: { $0.tabID == active.peekParentID && $0.peekID == active.tabID }) else {
        return nil
      }
      return ShownPeek(parentID: active.peekParentID, peekID: active.tabID)
    }
    guard let peek = peek(ofRow: active.tabID, in: tabs) else { return nil }
    return ShownPeek(parentID: active.tabID, peekID: peek.tabID)
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

  /// The index in its Space's list that a tab of the window, dragged to
  /// `index` among the window's tabs (as `stripIndex` gives it), asks for:
  /// before the window's tab it lands on, or after the window's last. Other
  /// windows' tabs of the Space keep their places (add-spaces D2). Nil when
  /// the tab isn't listed.
  static func spaceIndex(
    movingTab tabID: TabID, toWindowIndex index: Int, windowTabs: [any ClairTab], spaceTabs: [any ClairTab]
  ) -> Int? {
    guard let tab = windowTabs.first(where: { $0.tabID == tabID }) else { return nil }
    // The tab moves with its Peek.
    let family: Set<TabID> = [tab.tabID, tab.peekID]
    let windowRest = windowTabs.filter { !family.contains($0.tabID) }
    let spaceRest = spaceTabs.filter { !family.contains($0.tabID) }
    let target = min(max(index, 0), windowRest.count)
    if target < windowRest.count {
      return spaceRest.firstIndex { $0.tabID == windowRest[target].tabID }
    }
    guard let last = windowRest.last else { return 0 }
    return spaceRest.firstIndex { $0.tabID == last.tabID }.map { $0 + 1 }
  }

  /// The URL Copy Link puts on the pasteboard.
  static func link(of tab: any ClairTab) -> String? {
    if let url = tab.url {
      return url.absoluteString
    }
    return tab.urlText.isEmpty ? nil : tab.urlText
  }
}
