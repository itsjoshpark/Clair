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
  /// The card's inset on every edge with the sidebar hidden: the same as
  /// with it shown, as in Arc, so only the card's leading edge moves.
  static let hiddenInset: CGFloat = 10
  /// The revealed sidebar's inset from the window's edges, as in Arc.
  static let revealedInset: CGFloat = 5

  var sidebar: CGRect
  var card: CGRect

  init(sidebar: CGRect, card: CGRect) {
    self.sidebar = sidebar
    self.card = card
  }

  init(size: CGSize, sidebar state: SidebarState, isPageFullscreen: Bool) {
    if isPageFullscreen {
      // The page alone fills the window.
      self.init(
        sidebar: CGRect(x: -state.width, y: 0, width: state.width, height: size.height),
        card: CGRect(origin: .zero, size: size))
      return
    }
    self = Self.blended(size: size, width: state.width, shown: state.isHidden ? 0 : 1)
  }

  /// The layout part way through hiding or showing the sidebar: 0 is hidden,
  /// 1 is shown, and a spring may overshoot either.
  static func blended(size: CGSize, width: CGFloat, shown: CGFloat) -> WindowLayout {
    blended(size: size, width: width, sidebarShown: shown, cardShown: shown)
  }

  /// The same, with the sidebar and the card at different points: docking a
  /// revealed sidebar puts the sidebar in place at once while the card
  /// follows (design D12).
  static func blended(size: CGSize, width: CGFloat, sidebarShown: CGFloat, cardShown: CGFloat) -> WindowLayout {
    let hidden = hiddenInset, inset = shownInset
    let hiddenCard = CGRect(origin: .zero, size: size).insetBy(dx: hidden, dy: hidden)
    let shownCard = CGRect(
      x: width, y: inset,
      width: max(0, size.width - width - inset),
      height: max(0, size.height - 2 * inset))
    return WindowLayout(
      sidebar: CGRect(x: -width * (1 - sidebarShown), y: 0, width: width, height: size.height),
      card: hiddenCard.interpolated(to: shownCard, by: cardShown))
  }

  /// The hidden sidebar's frame while it floats over the page: 0 is off the
  /// leading edge, 1 is in place.
  static func revealedSidebar(size: CGSize, width: CGFloat, revealed: CGFloat) -> CGRect {
    let inset = revealedInset
    // Off screen, its shadow included.
    let away = -width - 2 * inset
    return CGRect(
      x: away + (inset - away) * revealed, y: inset,
      width: width, height: max(0, size.height - 2 * inset))
  }
}

extension CGRect {
  /// The rectangle `t` of the way from this one to `other`.
  func interpolated(to other: CGRect, by t: CGFloat) -> CGRect {
    func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }
    return CGRect(
      x: mix(minX, other.minX), y: mix(minY, other.minY),
      width: max(0, mix(width, other.width)), height: max(0, mix(height, other.height)))
  }
}
