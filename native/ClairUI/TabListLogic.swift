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

  /// The URL Copy Link puts on the pasteboard.
  static func link(of tab: any ClairTab) -> String? {
    if let url = tab.url {
      return url.absoluteString
    }
    return tab.urlText.isEmpty ? nil : tab.urlText
  }
}
