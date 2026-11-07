// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import SwiftUI

/// A hosting view sized to its SwiftUI content.
final class FittingHostingView<Content: View>: NSHostingView<Content> {
  required init(rootView: Content) {
    super.init(rootView: rootView)
    sizingOptions = []
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not used")
  }

  /// The content's size, at most `maxWidth` wide.
  func fittingSize(maxWidth: CGFloat) -> CGSize {
    let size = fittingSize
    return CGSize(width: min(size.width, maxWidth), height: size.height)
  }
}

/// The native window's content view (design D4): one translucent material
/// behind everything, the sidebar at the leading edge, the card with the page,
/// and the overlays above it. Laid out in AppKit, so a resize lays out the
/// page directly.
final class BrowserRootView: NSView {
  static let springAnimation = Animation.spring(response: 0.35, dampingFraction: 0.85)
  /// The strip at the leading edge that reveals a hidden sidebar.
  static let revealStripWidth: CGFloat = 6
  static let revealDelay: Duration = .milliseconds(150)
  static let concealDelay: Duration = .milliseconds(300)

  let background = NSVisualEffectView()
  let revealedBackground = NSVisualEffectView()
  let card = PageCardView()
  let sidebar: NSView
  let resizeHandle = SidebarResizeHandle()
  private let model: BrowserWindowModel

  // Overlays, set by the controller.
  var findHost: NSView? { didSet { replace(oldValue, with: findHost) } }
  var statusHost: NSView? { didSet { replace(oldValue, with: statusHost) } }
  var toastHost: NSView? { didSet { replace(oldValue, with: toastHost) } }
  var noticeHost: NSView? { didSet { replace(oldValue, with: noticeHost) } }
  var commandBarHost: NSView? { didSet { replace(oldValue, with: commandBarHost, scrim: true) } }
  private let commandBarScrim = ClickCatcherView()
  /// Called when the scrim behind the command bar is clicked.
  var onScrimClick: (() -> Void)? {
    get { commandBarScrim.onClick }
    set { commandBarScrim.onClick = newValue }
  }

  private var revealTask: Task<Void, Never>?
  private var animatesNextLayout = false

  init(model: BrowserWindowModel, sidebar: NSView) {
    self.model = model
    self.sidebar = sidebar
    super.init(frame: .zero)
    wantsLayer = true
    background.material = .sidebar
    background.blendingMode = .behindWindow
    background.state = .followsWindowActiveState
    revealedBackground.material = .sidebar
    revealedBackground.blendingMode = .withinWindow
    revealedBackground.state = .active
    revealedBackground.wantsLayer = true
    revealedBackground.layer?.cornerRadius = 10
    revealedBackground.layer?.masksToBounds = true
    revealedBackground.isHidden = true
    addSubview(background)
    addSubview(card)
    addSubview(revealedBackground)
    addSubview(sidebar)
    addSubview(resizeHandle)
    commandBarScrim.isHidden = true
    sidebar.setAccessibilityIdentifier("clair.sidebar")
    observeModel()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not used")
  }

  override var isFlipped: Bool { true }

  private func replace(_ old: NSView?, with new: NSView?, scrim: Bool = false) {
    old?.removeFromSuperview()
    if let new {
      if scrim {
        addSubview(commandBarScrim)
      }
      addSubview(new)
    } else if scrim {
      commandBarScrim.removeFromSuperview()
    }
    commandBarScrim.isHidden = commandBarHost == nil
    needsLayout = true
  }

  /// Lays out again whenever what the layout reads changes; a change to the
  /// sidebar's hidden state animates.
  private func observeModel() {
    let hidden = model.sidebar.isHidden
    withObservationTracking {
      _ = model.sidebar
      _ = model.isPageFullscreen
      _ = model.find
      _ = model.statusText
      _ = model.toast
      _ = model.exclusiveAccessNotice
      _ = model.commandBar
    } onChange: { [weak self] in
      Task { @MainActor in
        guard let self else { return }
        if self.model.sidebar.isHidden != hidden {
          self.animatesNextLayout = true
        }
        self.needsLayout = true
        self.observeModel()
      }
    }
  }

  var currentLayout: WindowLayout {
    WindowLayout(size: bounds.size, sidebar: model.sidebar, isPageFullscreen: model.isPageFullscreen)
  }

  /// Where the sidebar goes while revealed over the page.
  var revealedSidebarFrame: CGRect {
    CGRect(x: 6, y: 6, width: model.sidebar.width, height: max(0, bounds.height - 12))
  }

  override func layout() {
    super.layout()
    background.frame = bounds
    let layout = currentLayout
    let revealed = model.sidebar.isHidden && model.sidebar.isRevealed && !model.isPageFullscreen
    let sidebarFrame = revealed ? revealedSidebarFrame : layout.sidebar
    let place = {
      self.card.frame = layout.card
      self.sidebar.frame = sidebarFrame
    }
    if animatesNextLayout, window != nil {
      animatesNextLayout = false
      NSAnimationContext.animate(Self.springAnimation) { place() }
    } else {
      animatesNextLayout = false
      place()
    }
    sidebar.isHidden = model.isPageFullscreen
    revealedBackground.isHidden = !revealed
    revealedBackground.frame = revealedSidebarFrame
    card.isBare = model.isPageFullscreen
    resizeHandle.isHidden = model.sidebar.isHidden || model.isPageFullscreen
    resizeHandle.frame = CGRect(x: layout.sidebar.maxX - 3, y: 0, width: 6, height: bounds.height)
    TrafficLights.place(in: window, visible: !model.isPageFullscreen && (!model.sidebar.isHidden || revealed))
    layoutOverlays(card: layout.card)
    updateRevealTracking()
  }

  private func layoutOverlays(card: CGRect) {
    func fit(_ view: NSView?, maxWidth: CGFloat) -> CGSize {
      guard let view else { return .zero }
      let size = view.fittingSize
      return CGSize(width: min(size.width, maxWidth), height: size.height)
    }
    if let findHost {
      let size = fit(findHost, maxWidth: card.width - 20)
      findHost.frame = CGRect(x: card.maxX - size.width - 10, y: card.minY + 10, width: size.width, height: size.height)
    }
    if let statusHost {
      let size = fit(statusHost, maxWidth: card.width / 2)
      statusHost.frame = CGRect(x: card.minX + 8, y: card.maxY - size.height - 8, width: size.width, height: size.height)
    }
    if let toastHost {
      let size = fit(toastHost, maxWidth: card.width - 40)
      toastHost.frame = CGRect(x: card.midX - size.width / 2, y: card.maxY - size.height - 16, width: size.width, height: size.height)
    }
    if let noticeHost {
      let size = fit(noticeHost, maxWidth: bounds.width - 40)
      noticeHost.frame = CGRect(x: bounds.midX - size.width / 2, y: 24, width: size.width, height: size.height)
    }
    if let commandBarHost {
      commandBarScrim.frame = bounds
      let width = min(CommandBarView.width, bounds.width - 40)
      commandBarHost.frame.size.width = width
      let height = commandBarHost.fittingSize.height
      commandBarHost.frame = CGRect(x: bounds.midX - width / 2, y: bounds.height / 3 - 27, width: width, height: height)
    }
  }

  // MARK: Hover reveal (design D12)

  private var revealTrackingArea: NSTrackingArea?

  private func updateRevealTracking() {
    if let revealTrackingArea {
      removeTrackingArea(revealTrackingArea)
    }
    revealTrackingArea = nil
    guard model.sidebar.isHidden, !model.isPageFullscreen else { return }
    let rect =
      model.sidebar.isRevealed
      ? revealedSidebarFrame.insetBy(dx: -8, dy: -8)
      : CGRect(x: 0, y: 0, width: Self.revealStripWidth, height: bounds.height)
    let area = NSTrackingArea(
      rect: rect, options: [.mouseEnteredAndExited, .activeInKeyWindow, .assumeInside], owner: self)
    addTrackingArea(area)
    revealTrackingArea = area
  }

  override func mouseEntered(with event: NSEvent) {
    guard model.sidebar.isHidden else { return }
    revealTask?.cancel()
    guard !model.sidebar.isRevealed else { return }
    revealTask = Task { [weak self] in
      try? await Task.sleep(for: Self.revealDelay)
      guard !Task.isCancelled, let self else { return }
      self.animatesNextLayout = true
      self.model.sidebar.isRevealed = true
    }
  }

  override func mouseExited(with event: NSEvent) {
    revealTask?.cancel()
    guard model.sidebar.isRevealed else { return }
    revealTask = Task { [weak self] in
      try? await Task.sleep(for: Self.concealDelay)
      guard !Task.isCancelled, let self else { return }
      self.animatesNextLayout = true
      self.model.sidebar.isRevealed = false
    }
  }
}

/// Catches clicks outside the command bar, without dimming the page.
final class ClickCatcherView: NSView {
  var onClick: (() -> Void)?

  override func mouseDown(with event: NSEvent) {
    onClick?()
  }
}

/// The sidebar's trailing edge, dragged to resize it (design D12).
final class SidebarResizeHandle: NSView {
  /// Called with the new width while dragging, and once more when it ends.
  var onResize: ((CGFloat, Bool) -> Void)?
  private var startX: CGFloat = 0
  private var startWidth: CGFloat = 0
  var currentWidth: () -> CGFloat = { SidebarState.defaultWidth }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .resizeLeftRight)
  }

  override func mouseDown(with event: NSEvent) {
    startX = event.locationInWindow.x
    startWidth = currentWidth()
  }

  override func mouseDragged(with event: NSEvent) {
    onResize?(SidebarState.clamp(startWidth + event.locationInWindow.x - startX), false)
  }

  override func mouseUp(with event: NSEvent) {
    onResize?(SidebarState.clamp(startWidth + event.locationInWindow.x - startX), true)
  }
}

/// The window controls, in the sidebar (design D4).
enum TrafficLights {
  /// The buttons' leading edges, and their top, from the window's top left.
  static let xPositions: [CGFloat] = [12, 35, 58]
  static let top: CGFloat = 16

  static func place(in window: NSWindow?, visible: Bool) {
    guard let window else { return }
    let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    for (type, x) in zip(buttons, xPositions) {
      guard let button = window.standardWindowButton(type), let titlebar = button.superview else { continue }
      button.isHidden = !visible
      // The title bar view isn't flipped; it may be shorter than the
      // controls' new place, so keep the buttons inside its height.
      let height = titlebar.bounds.height
      let y = max(0, height - top - button.frame.height)
      button.setFrameOrigin(NSPoint(x: x, y: y))
    }
  }
}
