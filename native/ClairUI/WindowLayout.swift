// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import CoreGraphics

/// Where the sidebar and the card go in a native window (design D4, D12), in
/// the window's content coordinates with the origin at the top left.
struct WindowLayout: Equatable {
  /// The card's inset at the top, trailing and bottom edges with the sidebar
  /// shown; it touches the sidebar.
  static let shownInset: CGFloat = 10
  /// The card's inset on every edge with the sidebar hidden.
  static let hiddenInset: CGFloat = 5

  var sidebar: CGRect
  var card: CGRect

  init(size: CGSize, sidebar state: SidebarState, isPageFullscreen: Bool) {
    if isPageFullscreen {
      // The page alone fills the window.
      sidebar = CGRect(x: -state.width, y: 0, width: state.width, height: size.height)
      card = CGRect(origin: .zero, size: size)
      return
    }
    if state.isHidden {
      let inset = Self.hiddenInset
      sidebar = CGRect(x: -state.width, y: 0, width: state.width, height: size.height)
      card = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
      return
    }
    let inset = Self.shownInset
    sidebar = CGRect(x: 0, y: 0, width: state.width, height: size.height)
    card = CGRect(
      x: state.width, y: inset,
      width: max(0, size.width - state.width - inset),
      height: max(0, size.height - 2 * inset))
  }
}
