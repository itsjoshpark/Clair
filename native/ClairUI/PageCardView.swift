// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost

/// The card that holds the active tab's page (design D5): rounded corners from
/// a masked container, and a soft shadow from the outer layer, since a masked
/// layer can't cast one. Docked DevTools fills the container, with the page on
/// top at the bounds DevTools asks for.
final class PageCardView: NSView {
  static let cornerRadius: CGFloat = 8

  /// Holds the page (and DevTools); Chromium's tab-modal dialogs centre on it.
  let container = FlippedView()

  private(set) weak var pageView: NSView?
  private(set) weak var devToolsView: NSView?

  /// The tab's infobars, above the page.
  var infobarView: NSView? {
    didSet {
      oldValue?.removeFromSuperview()
      if let infobarView { container.addSubview(infobarView) }
      needsLayout = true
    }
  }

  /// The crashed-page view, in place of the page.
  var crashedView: NSView? {
    didSet {
      oldValue?.removeFromSuperview()
      if let crashedView { container.addSubview(crashedView) }
      needsLayout = true
    }
  }
  private var devToolsLayout = DevToolsLayout(dockSide: .none, pageBounds: .zero, hidesPage: false)

  /// Whether the card shows the page alone, as in page full screen: no corners
  /// or shadow.
  var isBare = false {
    didSet { updateAppearance() }
  }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.masksToBounds = false
    container.wantsLayer = true
    container.layer?.masksToBounds = true
    container.layer?.cornerCurve = .continuous
    container.setAccessibilityIdentifier("clair.card")
    addSubview(container)
    updateAppearance()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not used")
  }

  override var isFlipped: Bool { true }

  private func updateAppearance() {
    container.layer?.cornerRadius = isBare ? 0 : Self.cornerRadius
    layer?.shadowOpacity = isBare ? 0 : 0.18
    layer?.shadowRadius = 6
    layer?.shadowOffset = CGSize(width: 0, height: -1)
    layer?.shadowColor = NSColor.black.cgColor
    needsLayout = true
  }

  /// Shows `view` as the page, replacing the previous one. Chromium owns the
  /// view; the card only places it.
  func show(page view: NSView?) {
    guard view !== pageView else { return }
    pageView?.removeFromSuperview()
    pageView = view
    if let view {
      container.addSubview(view, positioned: .above, relativeTo: devToolsView)
    }
    needsLayout = true
  }

  /// Shows the active tab's docked DevTools, or none.
  func show(devTools view: NSView?, layout: DevToolsLayout) {
    if view !== devToolsView {
      devToolsView?.removeFromSuperview()
      devToolsView = view
      if let view {
        container.addSubview(view, positioned: .below, relativeTo: pageView)
      }
    }
    devToolsLayout = layout
    needsLayout = true
  }

  override func layout() {
    super.layout()
    container.frame = bounds
    layer?.shadowPath = isBare ? nil : CGPath(
      roundedRect: bounds, cornerWidth: Self.cornerRadius, cornerHeight: Self.cornerRadius, transform: nil)
    var card = container.bounds
    if let infobarView {
      let height = infobarView.fittingSize.height
      infobarView.frame = CGRect(x: 0, y: 0, width: card.width, height: height)
      card = card.divided(atDistance: height, from: .minYEdge).remainder
    }
    if let crashedView {
      crashedView.frame = card
    }
    if let devToolsView {
      devToolsView.frame = card
      let page = DevToolsPlacement.pageFrame(in: card.size, layout: devToolsLayout)
      pageView?.frame = page?.offsetBy(dx: card.minX, dy: card.minY) ?? .zero
      pageView?.isHidden = page == nil || crashedView != nil
    } else {
      pageView?.frame = card
      pageView?.isHidden = crashedView != nil
    }
  }
}

/// An NSView whose origin is at the top left, as Chromium's and DevTools'
/// coordinates are.
final class FlippedView: NSView {
  override var isFlipped: Bool { true }
}

/// Where the page sits when DevTools is docked: Chromium's
/// ApplyDevToolsContentsResizingStrategy(), in points.
enum DevToolsPlacement {
  /// The least DevTools keeps when the card shrinks, as Chromium's.
  static let minimumDevToolsWidth: CGFloat = 250
  static let minimumDevToolsHeight: CGFloat = 72

  /// The page's frame in a card of `size`, or nil when DevTools hides it.
  static func pageFrame(in size: CGSize, layout: DevToolsLayout) -> CGRect? {
    if layout.hidesPage {
      return nil
    }
    let bounds = layout.pageBounds
    if bounds.size.width <= 0 || bounds.size.height <= 0 {
      return CGRect(origin: .zero, size: size)
    }
    let left = min(bounds.origin.x, size.width)
    let top = min(bounds.origin.y, size.height)
    var width = min(bounds.size.width, size.width)
    var height = min(bounds.size.height, size.height)
    switch layout.dockSide {
    case .right:
      width = min(width, max(0, size.width - minimumDevToolsWidth))
    case .bottom:
      height = min(height, max(0, size.height - minimumDevToolsHeight))
    default:
      break
    }
    return CGRect(x: left, y: top, width: width, height: height)
  }
}
