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
    safeAreaRegions = []
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
  /// The strip at the leading edge that reveals a hidden sidebar.
  static let revealStripWidth: CGFloat = 6
  static let revealDelay: Duration = .milliseconds(150)
  static let concealDelay: Duration = .milliseconds(300)

  let background = NSVisualEffectView()
  /// The revealed sidebar's panel: a shadow around a lighter material.
  let revealedPanel = NSView()
  let revealedBackground = NSVisualEffectView()
  let card = PageCardView()
  let sidebar: NSView
  let resizeHandle = SidebarResizeHandle()
  private let model: BrowserWindowModel
  private lazy var trafficLights = TrafficLights()

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

  // The sidebar's motion (design D12): how far it's shown in place (0 hidden,
  // 1 shown) and how far the hidden sidebar is revealed over the page.
  private var shown: SpringValue
  private var revealed = SpringValue(0)
  private var animationLink: CADisplayLink?

  private var revealTask: Task<Void, Never>?
  /// Whether `revealTask` reveals (rather than conceals) the sidebar.
  private var revealTaskReveals = false

  init(model: BrowserWindowModel, sidebar: NSView) {
    self.model = model
    self.sidebar = sidebar
    shown = SpringValue(model.sidebar.isHidden ? 0 : 1)
    super.init(frame: .zero)
    wantsLayer = true
    background.material = .sidebar
    background.blendingMode = .behindWindow
    background.state = .followsWindowActiveState
    revealedBackground.material = .popover
    revealedBackground.blendingMode = .withinWindow
    revealedBackground.state = .active
    revealedBackground.wantsLayer = true
    revealedBackground.layer?.cornerRadius = 10
    revealedBackground.layer?.cornerCurve = .continuous
    revealedBackground.layer?.masksToBounds = true
    revealedBackground.layer?.borderWidth = 1
    revealedBackground.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
    revealedPanel.wantsLayer = true
    revealedPanel.layer?.shadowColor = NSColor.black.cgColor
    revealedPanel.layer?.shadowOpacity = 0.22
    revealedPanel.layer?.shadowRadius = 8
    revealedPanel.layer?.shadowOffset = CGSize(width: 0, height: -2)
    revealedPanel.addSubview(revealedBackground)
    revealedPanel.isHidden = true
    addSubview(background)
    addSubview(card)
    addSubview(revealedPanel)
    addSubview(sidebar)
    addSubview(resizeHandle)
    commandBarScrim.isHidden = true
    sidebar.setAccessibilityElement(true)
    sidebar.setAccessibilityRole(.group)
    sidebar.setAccessibilityLabel("Sidebar")
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

  /// Lays out again whenever what the layout reads changes, and springs the
  /// sidebar towards its new place.
  private func observeModel() {
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
        self.updateSidebarTargets()
        self.needsLayout = true
        self.observeModel()
      }
    }
  }

  /// Moves the sidebar's springs to the model's state; in page full screen,
  /// or before the window shows, they jump there.
  private func updateSidebarTargets() {
    let shownTarget: CGFloat = model.sidebar.isHidden ? 0 : 1
    let revealedTarget: CGFloat = model.sidebar.isHidden && model.sidebar.isRevealed ? 1 : 0
    guard window?.isVisible == true, !model.isPageFullscreen else {
      shown.jump(to: shownTarget)
      revealed.jump(to: revealedTarget)
      return
    }
    let now = CACurrentMediaTime()
    shown.animate(to: shownTarget, at: now)
    revealed.animate(to: revealedTarget, at: now)
    if shown.isMoving || revealed.isMoving {
      startAnimating()
    }
  }

  private func startAnimating() {
    guard animationLink == nil else { return }
    let link = displayLink(target: self, selector: #selector(animationStep))
    link.add(to: .main, forMode: .common)
    animationLink = link
  }

  @objc private func animationStep(_ link: CADisplayLink) {
    let now = CACurrentMediaTime()
    let moving = [shown.step(at: now), revealed.step(at: now)].contains(true)
    // Lay out now rather than on the next pass, so the page resizes in step.
    needsLayout = true
    layoutSubtreeIfNeeded()
    if !moving {
      link.invalidate()
      animationLink = nil
    }
  }

  var currentLayout: WindowLayout {
    if model.isPageFullscreen {
      return WindowLayout(size: bounds.size, sidebar: model.sidebar, isPageFullscreen: true)
    }
    return WindowLayout.blended(size: bounds.size, width: model.sidebar.width, shown: shown.value)
  }

  /// Where the hidden sidebar is while it floats over the page.
  var revealedSidebarFrame: CGRect {
    WindowLayout.revealedSidebar(size: bounds.size, width: model.sidebar.width, revealed: revealed.value)
  }

  override func layout() {
    super.layout()
    background.frame = bounds
    let layout = currentLayout
    card.frame = layout.card
    // The floating sidebar while it's revealed or sliding away; the one in
    // place once that is further in, as when Cmd+S shows a revealed sidebar.
    let floating = revealedSidebarFrame
    let floats = !model.isPageFullscreen && revealed.value > 0 && floating.minX > layout.sidebar.minX
    let sidebarFrame = floats ? floating : layout.sidebar
    sidebar.frame = sidebarFrame
    // A hidden sidebar only moves off the window; hiding the view would also
    // take it out of the accessibility tree (issue #93).
    sidebar.isHidden = model.isPageFullscreen
    revealedPanel.isHidden = !floats
    revealedPanel.frame = floating
    revealedPanel.layer?.shadowPath = CGPath(
      roundedRect: revealedPanel.bounds, cornerWidth: 10, cornerHeight: 10, transform: nil)
    revealedBackground.frame = revealedPanel.bounds
    card.isBare = model.isPageFullscreen
    resizeHandle.isHidden = model.sidebar.isHidden || model.isPageFullscreen
    resizeHandle.frame = CGRect(x: layout.sidebar.maxX - 3, y: 0, width: 6, height: bounds.height)
    trafficLights.place(
      in: window, sidebarOrigin: sidebarFrame.origin, visible: !model.isPageFullscreen && sidebarFrame.maxX > 0)
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
      commandBarHost.frame = CGRect(
        x: bounds.midX - width / 2, y: CommandBarView.top(inWindowHeight: bounds.height), width: width, height: height)
    }
  }

  // MARK: Hover reveal (design D12)

  private var revealTrackingArea: NSTrackingArea?

  /// The area that reveals the hidden sidebar, or hides it again once the
  /// pointer leaves; nil while the sidebar shows.
  private var revealTrackingRect: CGRect? {
    guard model.sidebar.isHidden, !model.isPageFullscreen else { return nil }
    return model.sidebar.isRevealed
      ? WindowLayout.revealedSidebar(size: bounds.size, width: model.sidebar.width, revealed: 1).insetBy(dx: -8, dy: -8)
      : CGRect(x: 0, y: 0, width: Self.revealStripWidth, height: bounds.height)
  }

  /// Replaces the tracking area only when its rect changes: a new area starts
  /// with the pointer outside, so rebuilding it on every layout would lose an
  /// entry already under way.
  private func updateRevealTracking() {
    let rect = revealTrackingRect
    guard rect != revealTrackingArea?.rect else { return }
    if let revealTrackingArea {
      removeTrackingArea(revealTrackingArea)
    }
    revealTrackingArea = nil
    guard let rect else { return }
    let area = NSTrackingArea(rect: rect, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self)
    addTrackingArea(area)
    revealTrackingArea = area
    checkPointer()
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let revealTrackingArea {
      removeTrackingArea(revealTrackingArea)
      self.revealTrackingArea = nil
    }
    updateRevealTracking()
  }

  /// A new tracking area doesn't report a pointer already inside it, so look
  /// where the pointer is: inside the area reveals, outside it conceals.
  private func checkPointer() {
    guard let window, let rect = revealTrackingArea?.rect else { return }
    if rect.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) {
      startReveal()
    } else if model.sidebar.isRevealed {
      startConceal()
    }
  }

  // AppKit can still report an area this view has replaced, such as the
  // strip's exit once the revealed sidebar's area takes over; only the
  // current area counts.
  override func mouseEntered(with event: NSEvent) {
    guard event.trackingArea === revealTrackingArea else { return }
    startReveal()
  }

  override func mouseExited(with event: NSEvent) {
    guard event.trackingArea === revealTrackingArea else { return }
    startConceal()
  }

  /// Reveals the sidebar after a short rest. Asking again while that wait is
  /// under way doesn't restart it: the tracking area is rebuilt whenever the
  /// window lays out, which could otherwise put the reveal off for good.
  private func startReveal() {
    guard model.sidebar.isHidden else { return }
    if revealTask != nil, revealTaskReveals { return }
    revealTask?.cancel()
    revealTask = nil
    guard !model.sidebar.isRevealed else { return }
    revealTaskReveals = true
    revealTask = Task { [weak self] in
      try? await Task.sleep(for: Self.revealDelay)
      guard !Task.isCancelled, let self else { return }
      self.revealTask = nil
      self.model.sidebar.isRevealed = true
    }
  }

  private func startConceal() {
    if revealTask != nil, !revealTaskReveals { return }
    revealTask?.cancel()
    revealTask = nil
    guard model.sidebar.isRevealed else { return }
    revealTaskReveals = false
    revealTask = Task { [weak self] in
      try? await Task.sleep(for: Self.concealDelay)
      guard !Task.isCancelled, let self else { return }
      self.revealTask = nil
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

/// The window controls, in the sidebar (design D4). AppKit puts them back in
/// the title bar's own layout whenever it lays that out again, such as when
/// the window's title changes, so this puts them back where they belong.
@MainActor
final class TrafficLights {
  /// The buttons' leading edges, and their top, from the sidebar's top left.
  /// These read back through accessibility as Arc's 12, 35, 58 and 16, which
  /// report the buttons a point further out than their frames.
  static let xPositions: [CGFloat] = [13, 36, 59]
  static let top: CGFloat = 17
  static let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

  private weak var window: NSWindow?
  private var sidebarOrigin = CGPoint.zero
  private var visible = true
  private var observers: [any NSObjectProtocol] = []
  private var isPlacing = false

  func place(in window: NSWindow?, sidebarOrigin: CGPoint, visible: Bool) {
    guard let window else { return }
    if window !== self.window {
      self.window = window
      observe(window)
    }
    self.sidebarOrigin = sidebarOrigin
    self.visible = visible
    apply()
  }

  private func observe(_ window: NSWindow) {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    let center = NotificationCenter.default
    let reapply: @Sendable (Notification) -> Void = { [weak self] _ in
      MainActor.assumeIsolated { self?.apply() }
    }
    observers = Self.types.compactMap { window.standardWindowButton($0) }.map { button in
      button.postsFrameChangedNotifications = true
      return center.addObserver(forName: NSView.frameDidChangeNotification, object: button, queue: .main, using: reapply)
    }
    // Not every move of the title bar's buttons reports a frame change, such
    // as the one a new title brings; catch the rest after each event.
    observers.append(center.addObserver(forName: NSWindow.didUpdateNotification, object: window, queue: .main, using: reapply))
  }

  private func apply() {
    guard let window, !isPlacing else { return }
    isPlacing = true
    defer { isPlacing = false }
    // The content view is flipped and fills the window, so its top left is
    // the window's.
    let windowHeight = window.contentView?.bounds.height ?? window.frame.height
    for (type, x) in zip(Self.types, Self.xPositions) {
      guard let button = window.standardWindowButton(type), let titlebar = button.superview else { continue }
      button.isHidden = !visible
      // From the window's top left to its base coordinates, then to the
      // title bar's; keep the buttons inside the title bar, which clips them.
      let top = sidebarOrigin.y + Self.top
      let base = NSPoint(x: sidebarOrigin.x + x, y: windowHeight - top - button.frame.height)
      var origin = titlebar.convert(base, from: nil)
      origin.y = min(max(0, origin.y), max(0, titlebar.bounds.height - button.frame.height))
      if button.frame.origin != origin {
        button.setFrameOrigin(origin)
      }
      // The title bar view can sit a point off the window's edge; correct by
      // where the button actually landed.
      let landed = button.convert(button.bounds, to: nil).origin
      let error = CGPoint(x: base.x - landed.x, y: base.y - landed.y)
      if abs(error.x) >= 0.5 || abs(error.y) >= 0.5 {
        var corrected = CGPoint(x: origin.x + error.x, y: origin.y + error.y)
        corrected.y = min(max(0, corrected.y), max(0, titlebar.bounds.height - button.frame.height))
        button.setFrameOrigin(corrected)
      }
    }
  }
}

extension NSHostingView {
  /// A hosting view without the title bar's safe area. The window's content
  /// view is full size and Clair lays its views out over all of it (design
  /// D4), so the sidebar's top row shares the traffic lights' line.
  static func edgeToEdge(rootView: Content) -> NSHostingView<Content> {
    let host = NSHostingView(rootView: rootView)
    host.safeAreaRegions = []
    return host
  }
}
