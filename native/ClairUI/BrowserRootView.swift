// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
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

/// A hosting view that asks its superview to lay out again whenever its
/// content's size changes, so an overlay's frame follows its content within
/// the same pass (design D18). Without it, content that grows is centred in
/// the old frame until the next layout, and moves.
class SelfSizingHostingView<Content: View>: NSHostingView<Content> {
  /// A margin around the content, kept for its shadow, that takes no clicks.
  var hitInset: CGFloat = 0

  required init(rootView: Content) {
    super.init(rootView: rootView)
    safeAreaRegions = []
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not used")
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard hitInset > 0 else { return super.hitTest(point) }
    let local = convert(point, from: superview)
    return bounds.insetBy(dx: hitInset, dy: hitInset).contains(local) ? super.hitTest(point) : nil
  }

  override func invalidateIntrinsicContentSize() {
    super.invalidateIntrinsicContentSize()
    superview?.needsLayout = true
  }

  // SwiftUI lays the hosting view out whenever its content changes; a
  // content size that no longer matches the frame lays the window out again
  // in the same pass.
  override func layout() {
    super.layout()
    if abs(fittingSize.height - bounds.height) > 0.5 {
      superview?.needsLayout = true
    }
  }
}

/// The native window's content view (design D4): one translucent material
/// behind everything, the sidebar at the leading edge, the card with the page,
/// and the overlays above it. Laid out in AppKit, so a resize lays out the
/// page directly.
final class BrowserRootView: NSView {
  /// The strip at the leading edge that reveals a hidden sidebar.
  /// The whole inset at the leading edge reveals it (design D18).
  static let revealStripWidth = WindowLayout.hiddenInset
  /// Arc reveals 100–117 ms after the pointer arrives; event delivery adds
  /// about 50 ms to this.
  static let revealDelay: Duration = .milliseconds(70)
  static let concealDelay: Duration = .milliseconds(300)

  let background = NSVisualEffectView()
  /// The window's material again, between the card and the sidebar, for
  /// while the card is under the docked sidebar, as when a revealed sidebar
  /// docks and the card slides out from under it (design D18).
  let sidebarBackdrop = NSVisualEffectView()
  /// The revealed sidebar's panel: a shadow around a lighter material.
  let revealedPanel = NSView()
  let revealedBackground = NSVisualEffectView()
  /// Over the revealed sidebar's material, so it's less translucent than a
  /// popover (design D18).
  let revealedTint = DynamicFillView(color: SidebarTint.revealed)
  /// Arc's near-black in Dark Mode over the window's and the backdrop's
  /// material, which is grey there; clear in Light Mode (design D18).
  let backgroundTint = DynamicFillView(color: SidebarTint.window)
  let backdropTint = DynamicFillView(color: SidebarTint.window)
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

  // The sidebar's motion (design D12): how far the sidebar and the card are
  // shown in place (0 hidden, 1 shown), which differ only while a revealed
  // sidebar docks, and how far the hidden sidebar is revealed over the page.
  private var sidebarShown: SpringValue
  private var cardShown: SpringValue
  private var revealed = SpringValue(0, spring: SpringValue.revealSpring)
  private var animationLink: CADisplayLink?

  private var revealTask: Task<Void, Never>?
  /// Whether `revealTask` reveals (rather than conceals) the sidebar.
  private var revealTaskReveals = false

  init(model: BrowserWindowModel, sidebar: NSView) {
    self.model = model
    self.sidebar = sidebar
    sidebarShown = SpringValue(model.sidebar.isHidden ? 0 : 1)
    cardShown = SpringValue(model.sidebar.isHidden ? 0 : 1)
    super.init(frame: .zero)
    wantsLayer = true
    background.material = .sidebar
    background.blendingMode = .behindWindow
    background.state = .followsWindowActiveState
    sidebarBackdrop.material = .sidebar
    sidebarBackdrop.blendingMode = .behindWindow
    sidebarBackdrop.state = .followsWindowActiveState
    sidebarBackdrop.isHidden = true
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
    revealedBackground.addSubview(revealedTint)
    revealedPanel.isHidden = true
    addSubview(background)
    // Above the materials, not inside them, where they'd blend it.
    addSubview(backgroundTint)
    addSubview(card)
    addSubview(sidebarBackdrop)
    addSubview(backdropTint)
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

  /// Edit > Copy URL (Shift+Cmd+C), which reaches the window through the
  /// responder chain (design D18).
  var onCopyURL: (() -> Void)?
  var canCopyURL: () -> Bool = { false }

  @objc func copyCurrentURL(_ sender: Any?) {
    onCopyURL?()
  }

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
      _ = model.notice.notice
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
      sidebarShown.jump(to: shownTarget)
      cardShown.jump(to: shownTarget)
      revealed.jump(to: revealedTarget)
      return
    }
    // Showing a revealed sidebar docks it where it is: it takes the docked
    // place at once (5 pt from where it floats), and only the card moves.
    if shownTarget == 1, sidebarShown.target == 0, revealed.value > 0.5 {
      sidebarShown.jump(to: 1)
      revealed.jump(to: 0)
    }
    let now = CACurrentMediaTime()
    sidebarShown.animate(to: shownTarget, at: now)
    cardShown.animate(to: shownTarget, at: now)
    revealed.animate(to: revealedTarget, at: now)
    if sidebarShown.isMoving || cardShown.isMoving || revealed.isMoving {
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
    let moving = [sidebarShown.step(at: now), cardShown.step(at: now), revealed.step(at: now)].contains(true)
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
    return WindowLayout.blended(
      size: bounds.size, width: model.sidebar.width, sidebarShown: sidebarShown.value, cardShown: cardShown.value)
  }

  /// Where the hidden sidebar is while it floats over the page.
  var revealedSidebarFrame: CGRect {
    WindowLayout.revealedSidebar(size: bounds.size, width: model.sidebar.width, revealed: revealed.value)
  }

  override func layout() {
    super.layout()
    // Catch up with a model change whose observation hasn't run yet; a target
    // the springs already have changes nothing.
    updateSidebarTargets()
    background.frame = bounds
    backgroundTint.frame = bounds
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
    let cardUnderSidebar = !floats && !model.isPageFullscreen && layout.sidebar.maxX > 0
      && layout.card.minX < layout.sidebar.maxX
    sidebarBackdrop.isHidden = !cardUnderSidebar
    sidebarBackdrop.frame = layout.sidebar
    backdropTint.frame = layout.sidebar
    backdropTint.isHidden = sidebarBackdrop.isHidden
    revealedPanel.frame = floating
    revealedPanel.layer?.shadowPath = CGPath(
      roundedRect: revealedPanel.bounds, cornerWidth: 10, cornerHeight: 10, transform: nil)
    revealedBackground.frame = revealedPanel.bounds
    revealedTint.frame = revealedBackground.bounds
    card.isBare = model.isPageFullscreen
    resizeHandle.isHidden = model.sidebar.isHidden || model.isPageFullscreen
    resizeHandle.frame = CGRect(x: layout.sidebar.maxX - 3, y: 0, width: 6, height: bounds.height)
    if let controls = window as? any ClairWindowControls {
      WindowControlsPlacement(sidebar: sidebarFrame, isPageFullscreen: model.isPageFullscreen).apply(to: controls)
      readWindowControls(sidebar: sidebarFrame)
    }
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
      // 8 pt inside the card's top-trailing corner, as in Arc; the view has a
      // margin around the popup for its shadow.
      let size = noticeHost.fittingSize
      let margin = NoticePopupView.margin
      noticeHost.frame = CGRect(
        x: card.maxX - 8 + margin - size.width, y: card.minY + 8 - margin, width: size.width, height: size.height)
      if noticeHost !== subviews.last {
        addSubview(noticeHost)
      }
    }
    if let commandBarHost {
      commandBarScrim.frame = bounds
      let width = min(CommandBarView.width, bounds.width - 40)
      commandBarHost.frame.size.width = width
      let height = commandBarHost.fittingSize.height
      // Whole points, so its hairline border stays one crisp pixel.
      commandBarHost.frame = CGRect(
        x: (bounds.midX - width / 2).rounded(), y: CommandBarView.top(inWindowHeight: bounds.height),
        width: width.rounded(), height: height)
    }
  }

  // MARK: Window controls (place-traffic-lights-with-appkit D3b)

  /// Reads where AppKit put the close and zoom buttons, as accessibility
  /// reports them, so the top row lines up with them. Re-tiling is
  /// synchronous, so they're already at the place just set; hidden ones are
  /// left alone until they show.
  private func readWindowControls(sidebar: CGRect) {
    // In full screen the buttons live in the title bar's own window, so
    // their frames say nothing about this one.
    guard let window, !model.isPageFullscreen, !window.styleMask.contains(.fullScreen),
      let close = window.standardWindowButton(.closeButton),
      let zoom = window.standardWindowButton(.zoomButton),
      !close.isHidden, !zoom.isHidden
    else { return }
    func topLeft(_ screenRect: CGRect) -> CGRect {
      let rect = window.convertFromScreen(screenRect)
      return CGRect(x: rect.minX, y: window.frame.height - rect.maxY, width: rect.width, height: rect.height)
    }
    let closeFrame = topLeft(close.accessibilityFrame())
    let zoomFrame = topLeft(zoom.accessibilityFrame())
    guard closeFrame.width > 0, zoomFrame.width > 0 else { return }
    let read = WindowControlsMetrics(
      centreY: closeFrame.midY - sidebar.minY, trailingX: zoomFrame.maxX - sidebar.minX)
    if read.differs(from: model.windowControls) {
      model.windowControls = read
      if model.sidebar.width < read.narrowestSidebar {
        model.sidebar.width = read.narrowestSidebar
      }
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

/// Where the window controls go (design D4; place-traffic-lights-with-appkit
/// D3): at Arc's offsets from the sidebar's top-leading corner, wherever the
/// sidebar is, and hidden once it's off the window or a page is in full
/// screen. The window's own title bar layout puts them there.
struct WindowControlsPlacement: Equatable {
  /// The close button's top-leading corner, from the sidebar's. Accessibility
  /// reports the buttons a point up and left of their frames, so this reads
  /// back as Arc's 12, 35 and 58 across and 16 down.
  static let offset = CGPoint(x: 13, y: 17)

  var origin: CGPoint
  var isHidden: Bool

  init(sidebar: CGRect, isPageFullscreen: Bool) {
    origin = CGPoint(x: sidebar.minX + Self.offset.x, y: sidebar.minY + Self.offset.y)
    isHidden = isPageFullscreen || sidebar.maxX <= 0
  }

  /// Sets what changed, so an unchanged place doesn't lay the title bar out.
  func apply(to controls: any ClairWindowControls) {
    if controls.windowControlsOrigin != origin {
      controls.windowControlsOrigin = origin
    }
    if controls.windowControlsHidden != isHidden {
      controls.windowControlsHidden = isHidden
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

/// A view filled with a colour that follows the appearance, such as a
/// translucent window background over a material.
final class DynamicFillView: NSView {
  private let color: NSColor

  init(color: NSColor) {
    self.color = color
    super.init(frame: .zero)
    wantsLayer = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not used")
  }

  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      layer?.backgroundColor = color.cgColor
    }
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }
}

/// The fills over the sidebar's materials (design D18).
enum SidebarTint {
  /// Arc's dark sidebar, which measures (16, 19, 25) in a window capture.
  /// Opaque: any translucency lets the desktop behind the window lighten it.
  /// The window draws a colour about a quarter lighter than it's given, so
  /// these values measure as Arc's.
  static let dark = NSColor(srgbRed: 13 / 255, green: 14 / 255, blue: 19 / 255, alpha: 1)

  /// Over the window's material: nothing in Light Mode, Arc's near-black in
  /// Dark Mode, including incognito windows.
  static let window = NSColor(name: nil) { appearance in
    appearance.isDark ? dark : .clear
  }

  /// Over the revealed sidebar's lighter material, so it's less see-through.
  static let revealed = NSColor(name: nil) { appearance in
    appearance.isDark ? dark : NSColor.windowBackgroundColor.withAlphaComponent(0.55)
  }
}

extension NSAppearance {
  var isDark: Bool {
    bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark]).map { [.darkAqua, .vibrantDark].contains($0) } ?? false
  }
}

extension BrowserRootView: NSMenuItemValidation {
  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    menuItem.action == #selector(copyCurrentURL(_:)) ? canCopyURL() : true
  }
}
