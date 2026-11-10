// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import ClairHost
import CoreGraphics

/// A control in the sidebar that Chromium's bubbles attach to.
enum AnchorControl: Hashable {
  case siteControls
  /// An indicator, by its TabIndicators raw value.
  case indicator(UInt)
  case extensionAction(String)
  case downloads
}

/// Where a Chromium bubble attaches (design D7): to its control in the sidebar
/// while the sidebar is shown in place, or else to the card's top-leading
/// corner. A revealed sidebar slides away when the pointer leaves, which would
/// orphan a bubble, so it never anchors one.
struct AnchorResolver {
  /// Chromium's kNoToolbarLeftOffset, from the card's leading edge.
  static let fallbackInset: CGFloat = 40

  /// Whether the sidebar is beside the card (not hidden, revealed, or in full
  /// screen).
  var sidebarInPlace: Bool
  /// The controls' frames, in window coordinates (origin at the bottom left).
  var controls: [AnchorControl: CGRect]
  /// The card's frame, in window coordinates.
  var card: CGRect

  func anchor(for kind: AnchorKind, indicator: TabIndicators, extensionID: String?) -> BubbleAnchor {
    if sidebarInPlace, let rect = controlRect(for: kind, indicator: indicator, extensionID: extensionID) {
      return BubbleAnchor(rect: rect, edge: .trailing)
    }
    return fallback
  }

  /// The card's top-leading corner.
  var fallback: BubbleAnchor {
    BubbleAnchor(rect: CGRect(x: card.minX + Self.fallbackInset, y: card.maxY, width: 0, height: 0), edge: .bottom)
  }

  private func controlRect(for kind: AnchorKind, indicator: TabIndicators, extensionID: String?) -> CGRect? {
    switch kind {
    case .siteControls:
      return controls[.siteControls]
    case .indicator:
      // An indicator the field doesn't show falls back to the site controls.
      for element in [TabIndicators.camera, .microphone, .location, .screenCapture, .blockedPermission]
      where indicator.contains(element) {
        if let rect = controls[.indicator(element.rawValue)] {
          return rect
        }
      }
      return controls[.siteControls]
    case .extensionAction:
      if let extensionID, let rect = controls[.extensionAction(extensionID)] {
        return rect
      }
      return controls[.siteControls]
    case .downloads:
      return controls[.downloads]
    @unknown default:
      return nil
    }
  }
}
