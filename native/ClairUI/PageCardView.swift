// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost

/// The card that holds the active tab's page (design D5): rounded corners from
/// a masked container, and a soft shadow from the outer layer, since a masked
/// layer can't cast one. Docked DevTools fills the container, with the page on
/// top at the bounds DevTools asks for.
///
/// While a Peek shows (add-peek design D4), the container holds the parent's
/// page, shrunk a little and washed out, under a click catcher that closes
/// the Peek; the Peek's page, with its DevTools, infobars and crashed view,
/// sits in a rounded card of its own over it, with its buttons beside it.
final class PageCardView: NSView {
  static let cornerRadius: CGFloat = 8

  /// Holds the page (and DevTools); Chromium's tab-modal dialogs centre on it.
  let container = FlippedView()

  /// The active tab's page: the Peek's while a Peek shows.
  private(set) weak var pageView: NSView?
  /// The page behind the Peek, while one shows.
  private(set) weak var parentPageView: NSView?
  /// Moves the window from the top of the page (drag-window-from-page-top).
  let dragStrip = PageTopDragStrip()
  /// The faded still of a page another window took, over the hidden
  /// placeholder tab (share-tabs-across-windows D2).
  let stillView = StillView()
  private(set) weak var devToolsView: NSView?

  /// Holds the page, and the parent page while a Peek shows: the page stays
  /// in it when a Peek opens or closes, since moving a page's view blanks it
  /// for a frame. Its layer's sublayer transform shrinks the parent page
  /// behind a Peek without resizing it (add-peek design D4).
  private let pageHolder = FlippedView()

  // The Peek (add-peek design D4).
  /// Holds the card's container; its layer's sublayer transform shrinks the
  /// whole card, corners and wash included, behind a Peek, as in Arc, without
  /// resizing the page.
  private let cardScaler = FlippedView()
  /// Washes the parent page out toward the window's background.
  private let wash = DynamicFillView(color: PeekWash.color)
  /// Covers the parent page; a click on it closes the Peek.
  let peekClickCatcher = ClickCatcherView()
  /// The Peek's card: the shadow outside, the masked container inside.
  private let peekCard = NSView()
  let peekContainer = FlippedView()
  /// The Peek's buttons, beside its top-trailing corner.
  var peekControls: NSView? {
    didSet {
      oldValue?.removeFromSuperview()
      if let peekControls {
        addSubview(peekControls)
        peekControls.isHidden = !isPeeking
      }
      needsLayout = true
    }
  }

  /// Called when the Confirm pill should grow over the Peek (true) or beside
  /// the buttons, as the room beside them changes.
  var onConfirmDirectionChange: ((Bool) -> Void)?
  private var confirmGrowsTowardPeek = false

  /// Whether a Peek shows over its parent.
  var isPeeking: Bool { parentPageView != nil }

  /// The view that holds the active page, its DevTools and infobars, and
  /// where Chromium's tab-modal dialogs centre: the Peek's container while a
  /// Peek shows.
  var activeContainer: FlippedView { isPeeking ? peekContainer : pageHolder }

  /// The Peek's frame in the card, or the card's bounds without a Peek; the
  /// link status shows at its bottom-leading corner (add-peek design D11).
  var activePageFrame: CGRect { isPeeking ? peekCard.frame : bounds }

  /// The tab's infobars, above the page.
  var infobarView: NSView? {
    didSet {
      oldValue?.removeFromSuperview()
      if let infobarView { activeContainer.addSubview(infobarView) }
      needsLayout = true
    }
  }

  /// The crashed-page view, in place of the page.
  var crashedView: NSView? {
    didSet {
      oldValue?.removeFromSuperview()
      if let crashedView { activeContainer.addSubview(crashedView) }
      needsLayout = true
    }
  }
  private var devToolsLayout = DevToolsLayout(dockSide: .none, pageBounds: .zero, hidesPage: false)

  /// Whether the card shows the page alone, as in page full screen: no corners
  /// or shadow.
  var isBare = false {
    didSet { updateAppearance() }
  }

  /// Where and when the last left press in the card was, which a new Peek
  /// grows from (add-peek design D5).
  private var lastPress: (point: CGPoint, time: TimeInterval)?
  nonisolated(unsafe) private var pressMonitor: Any?
  /// Where the shown Peek grew from, which it shrinks back to.
  private var peekOrigin: CGPoint?

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.masksToBounds = false
    container.wantsLayer = true
    container.layer?.masksToBounds = true
    container.layer?.cornerCurve = .continuous
    container.setAccessibilityElement(true)
    container.setAccessibilityRole(.group)
    container.setAccessibilityLabel("Page")
    container.setAccessibilityIdentifier("clair.card")
    pageHolder.wantsLayer = true
    container.addSubview(pageHolder)
    container.addSubview(dragStrip)
    stillView.isHidden = true
    container.addSubview(wash)
    container.addSubview(peekClickCatcher)
    cardScaler.wantsLayer = true
    cardScaler.addSubview(container)
    addSubview(cardScaler)
    peekCard.wantsLayer = true
    peekCard.layer?.masksToBounds = false
    peekCard.layer?.shadowColor = NSColor.black.cgColor
    peekCard.layer?.shadowOpacity = PeekLayout.shadowOpacity
    peekCard.layer?.shadowRadius = PeekLayout.shadowRadius
    peekCard.layer?.shadowOffset = .zero
    peekContainer.wantsLayer = true
    peekContainer.layer?.masksToBounds = true
    peekContainer.layer?.cornerRadius = PeekLayout.cornerRadius
    peekContainer.layer?.cornerCurve = .continuous
    peekContainer.setAccessibilityElement(true)
    peekContainer.setAccessibilityRole(.group)
    peekContainer.setAccessibilityLabel("Peek")
    peekContainer.setAccessibilityIdentifier("clair.peek")
    peekCard.addSubview(peekContainer)
    addSubview(peekCard)
    updatePeekVisibility()
    updateAppearance()
    updatePeekBacking()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not used")
  }

  deinit {
    if let pressMonitor {
      NSEvent.removeMonitor(pressMonitor)
    }
  }

  override var isFlipped: Bool { true }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updatePeekBacking()
  }

  /// The Peek's card is the page's background colour under the page, so in
  /// the frames between Chromium taking a closing Peek's page away and the
  /// card animating it out, it shows a card, not its bare shadow.
  private func updatePeekBacking() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      peekContainer.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
    }
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if let pressMonitor {
      NSEvent.removeMonitor(pressMonitor)
      self.pressMonitor = nil
    }
    guard window != nil else { return }
    // Records where a press lands without taking it from the page.
    pressMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
      MainActor.assumeIsolated { self?.recordPress(event) }
      return event
    }
  }

  private func recordPress(_ event: NSEvent) {
    guard event.window === window else { return }
    let point = convert(event.locationInWindow, from: nil)
    guard bounds.contains(point) else { return }
    lastPress = (point, event.timestamp)
  }

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
    show(page: view, behind: nil)
  }

  /// What the card shows changes from one tab to another, or a Peek opens,
  /// closes or expands (add-peek design D5).
  private enum Transition {
    case none, open, close, expand
  }

  /// Shows `view` as the active page, over `parent` in a Peek when there is
  /// one. Opening and closing a Peek animate; switching tabs doesn't.
  func show(page view: NSView?, behind parent: NSView?) {
    let oldPage = pageView
    let oldParent = parentPageView
    guard view !== oldPage || parent !== oldParent else { return }
    let wasPeeking = oldParent != nil
    let oldPeekFrame = peekCard.frame
    let transition: Transition =
      if parent != nil, !wasPeeking, parent === oldPage, view != nil {
        .open
      } else if parent == nil, wasPeeking, view != nil, view === oldParent {
        .close
      } else if parent == nil, wasPeeking, view != nil, view === oldPage {
        .expand
      } else {
        .none
      }

    if oldPage !== view, oldPage !== parent { oldPage?.removeFromSuperview() }
    if oldParent !== view, oldParent !== parent { oldParent?.removeFromSuperview() }
    pageView = view
    parentPageView = parent
    if let parent, parent.superview !== pageHolder {
      pageHolder.addSubview(parent)
    }
    if let view, view.superview !== activeContainer {
      // Under the infobars and the crashed view, above DevTools. A page
      // already in place stays: adding it again blanks it for a frame.
      let surface = activeContainer
      if let devToolsView, devToolsView.superview === surface {
        surface.addSubview(view, positioned: .above, relativeTo: devToolsView)
      } else {
        surface.addSubview(view, positioned: .below, relativeTo: nil)
      }
    }
    moveSurfaceViews()
    updatePeekVisibility()
    needsLayout = true
    layoutSubtreeIfNeeded()

    switch transition {
    case .open:
      animateOpening()
    case .close:
      animateClosing(from: oldPeekFrame)
    case .expand, .none:
      peekOrigin = isPeeking ? peekOrigin : nil
    }
  }

  /// Puts DevTools, the infobars and the crashed view with the active page,
  /// in the order they stack.
  private func moveSurfaceViews() {
    let surface = activeContainer
    if let devToolsView, devToolsView.superview !== surface {
      surface.addSubview(devToolsView, positioned: .below, relativeTo: nil)
    }
    for view in [infobarView, crashedView].compactMap({ $0 }) where view.superview !== surface {
      surface.addSubview(view)
    }
  }

  private func updatePeekVisibility() {
    let peeking = isPeeking
    wash.isHidden = !peeking
    peekClickCatcher.isHidden = !peeking
    peekCard.isHidden = !peeking
    peekControls?.isHidden = !peeking
    if !peeking {
      cardScaler.layer?.sublayerTransform = CATransform3DIdentity
    }
  }

  /// Shows the faded still, with `image` or as the window's background
  /// alone, or hides it.
  func showStill(_ shows: Bool, image: NSImage?) {
    stillView.image = shows ? image : nil
    stillView.isHidden = !shows
    stillView.setAccessibilityElement(shows)
    // Only in the card while it shows: a hidden view can stay in the
    // accessibility tree. Over the page, under the Peek's wash.
    if shows, stillView.superview == nil {
      container.addSubview(stillView, positioned: .below, relativeTo: wash)
    } else if !shows {
      stillView.removeFromSuperview()
    }
    needsLayout = true
  }

  /// Shows the active tab's docked DevTools, or none.
  func show(devTools view: NSView?, layout: DevToolsLayout) {
    if view !== devToolsView {
      devToolsView?.removeFromSuperview()
      devToolsView = view
      if let view {
        let surface = activeContainer
        if let pageView, pageView.superview === surface {
          surface.addSubview(view, positioned: .below, relativeTo: pageView)
        } else {
          surface.addSubview(view, positioned: .below, relativeTo: nil)
        }
      }
    }
    devToolsLayout = layout
    needsLayout = true
  }

  override func layout() {
    super.layout()
    cardScaler.frame = bounds
    container.frame = cardScaler.bounds
    layer?.shadowPath = isBare ? nil : cardShadowPath(peeking: isPeeking)
    pageHolder.frame = container.bounds
    stillView.frame = container.bounds
    if isPeeking {
      parentPageView?.frame = pageHolder.bounds
      if let scalerLayer = cardScaler.layer {
        scalerLayer.sublayerTransform = PeekLayout.parentTransform(
          size: cardScaler.bounds.size, anchor: scalerLayer.anchorPoint)
      }
      wash.frame = container.bounds
      peekClickCatcher.frame = container.bounds
      let peek = PeekLayout.peekFrame(in: bounds)
      peekCard.frame = peek
      peekContainer.frame = peekCard.bounds
      peekCard.layer?.shadowPath = CGPath(
        roundedRect: peekCard.bounds, cornerWidth: PeekLayout.cornerRadius, cornerHeight: PeekLayout.cornerRadius,
        transform: nil)
      if let peekControls {
        let buttons = PeekLayout.buttonFrames(beside: peek)
        let first = buttons[0]
        // Room for the Confirm pill beside the buttons, or, in a window too
        // narrow for it there, over the Peek.
        let room = bounds.maxX - first.minX
        let towardPeek = room < PeekLayout.confirmWidth
        let height = buttons[buttons.count - 1].maxY - first.minY
        peekControls.frame =
          towardPeek
          ? CGRect(x: first.maxX - PeekLayout.confirmWidth, y: first.minY, width: PeekLayout.confirmWidth, height: height)
          : CGRect(x: first.minX, y: first.minY, width: room, height: height)
        if towardPeek != confirmGrowsTowardPeek {
          confirmGrowsTowardPeek = towardPeek
          onConfirmDirectionChange?(towardPeek)
        }
        if peekControls !== subviews.last {
          addSubview(peekControls)
        }
      }
      dragStrip.isHidden = true
      layoutSurface(in: peekContainer.bounds)
    } else {
      layoutSurface(in: pageHolder.bounds)
      if let pageView, !pageView.isHidden {
        var strip = pageView.frame
        strip.size.height = min(strip.height, PageTopWindowDrag.stripHeight)
        dragStrip.frame = strip
        dragStrip.isHidden = false
      } else {
        dragStrip.isHidden = true
      }
    }
  }

  /// The card's shadow, around the card shrunk behind a Peek or not.
  private func cardShadowPath(peeking: Bool) -> CGPath {
    let rect = peeking ? PeekLayout.parentFrame(in: bounds) : bounds
    return CGPath(roundedRect: rect, cornerWidth: Self.cornerRadius, cornerHeight: Self.cornerRadius, transform: nil)
  }

  /// Lays out the active page, its DevTools, infobars and crashed view in
  /// `bounds` of the active container.
  private func layoutSurface(in bounds: CGRect) {
    var card = bounds
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

  // MARK: Animation (add-peek design D5)

  private var reduceMotion: Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }

  /// The point a new Peek grows from: the last press in the card if it was
  /// recent, as the Shift+click that opened it, or else the card's centre.
  private func growOrigin() -> CGPoint {
    if let lastPress, ProcessInfo.processInfo.systemUptime - lastPress.time < 2 {
      return lastPress.point
    }
    return CGPoint(x: bounds.midX, y: bounds.midY)
  }

  // The grow and shrink transforms take points in this view's own top-left
  // coordinates: AppKit places a flipped view's sublayers in them (checked
  // with a 60 fps recording).

  private func animateOpening() {
    let origin = growOrigin()
    peekOrigin = origin
    let views = [peekCard, peekControls].compactMap { $0 }
    if reduceMotion {
      for view in views { fade(view.layer, from: 0, to: 1, duration: PeekLayout.reducedMotionDuration) }
      fade(wash.layer, from: 0, to: 1, duration: PeekLayout.reducedMotionDuration)
      return
    }
    // The Peek grows from the click with Arc's ease-out: most of the way at
    // once, then settling; it's opaque within a few frames.
    if let layer = peekCard.layer {
      let grow = CABasicAnimation(keyPath: "transform")
      grow.fromValue = PeekLayout.growTransform(
        from: origin, position: layer.position, scale: PeekLayout.startScale)
      grow.toValue = CATransform3DIdentity
      grow.duration = PeekLayout.openDuration
      grow.timingFunction = PeekLayout.timing(PeekLayout.openTiming)
      layer.add(grow, forKey: "peekGrow")
      fade(layer, from: 0, to: 1, duration: 0.05)
    }
    // The buttons ride the Peek's top-trailing corner out, as in Arc.
    if let controls = peekControls?.layer {
      let corner = CGPoint(x: peekCard.frame.maxX, y: peekCard.frame.minY)
      let shift = 1 - PeekLayout.startScale
      let ride = CABasicAnimation(keyPath: "transform")
      ride.fromValue = CATransform3DMakeTranslation(shift * (origin.x - corner.x), shift * (origin.y - corner.y), 0)
      ride.toValue = CATransform3DIdentity
      ride.duration = PeekLayout.openDuration
      ride.timingFunction = PeekLayout.timing(PeekLayout.openTiming)
      controls.add(ride, forKey: "peekRide")
      fade(controls, from: 0, to: 1, duration: PeekLayout.openDuration * 0.6)
    }
    // The parent page shrinks and washes out alongside.
    let parentTiming = PeekLayout.timing(PeekLayout.parentTiming)
    fade(wash.layer, from: 0, to: 1, duration: PeekLayout.parentDuration, timing: parentTiming)
    if let scaler = cardScaler.layer {
      let shrink = CABasicAnimation(keyPath: "sublayerTransform")
      shrink.fromValue = CATransform3DIdentity
      shrink.toValue = scaler.sublayerTransform
      shrink.duration = PeekLayout.parentDuration
      shrink.timingFunction = parentTiming
      scaler.add(shrink, forKey: "peekParentOpen")
      animateShadow(from: cardShadowPath(peeking: false), duration: PeekLayout.parentDuration, timing: parentTiming)
    }
  }

  /// Moves the card's shadow from `path` to where layout put it.
  private func animateShadow(from path: CGPath, duration: TimeInterval, timing: CAMediaTimingFunction) {
    guard let layer, let target = layer.shadowPath else { return }
    let move = CABasicAnimation(keyPath: "shadowPath")
    move.fromValue = path
    move.toValue = target
    move.duration = duration
    move.timingFunction = timing
    layer.add(move, forKey: "peekShadow")
  }

  private func fade(
    _ layer: CALayer?, from: Float, to: Float, duration: TimeInterval,
    timing: CAMediaTimingFunction = CAMediaTimingFunction(name: .linear)
  ) {
    guard let layer else { return }
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = from
    fade.toValue = to
    fade.duration = duration
    fade.timingFunction = timing
    layer.add(fade, forKey: "peekFade")
  }

  /// The Peek's page has gone with its tab, so a plain card in its place
  /// shrinks back toward where it grew from, fading out on the way, while the
  /// parent page returns, as in Arc.
  private func animateClosing(from frame: CGRect) {
    let origin = peekOrigin ?? CGPoint(x: frame.midX, y: frame.midY)
    peekOrigin = nil
    guard !frame.isEmpty else { return }
    let ghost = NSView(frame: frame)
    ghost.wantsLayer = true
    ghost.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
    ghost.layer?.cornerRadius = PeekLayout.cornerRadius
    ghost.layer?.cornerCurve = .continuous
    ghost.layer?.shadowColor = NSColor.black.cgColor
    ghost.layer?.shadowOpacity = PeekLayout.shadowOpacity
    ghost.layer?.shadowRadius = PeekLayout.shadowRadius
    ghost.layer?.shadowOffset = .zero
    addSubview(ghost)
    let wash = DynamicFillView(color: PeekWash.color)
    wash.frame = bounds
    addSubview(wash, positioned: .below, relativeTo: ghost)
    let parentDuration = reduceMotion ? PeekLayout.reducedMotionDuration : PeekLayout.parentDuration
    let parentTiming = PeekLayout.timing(PeekLayout.parentTiming)
    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak ghost, weak wash] in
      MainActor.assumeIsolated {
        ghost?.removeFromSuperview()
        wash?.removeFromSuperview()
      }
    }
    if let layer = ghost.layer {
      layer.opacity = 0
      if reduceMotion {
        fade(layer, from: 1, to: 0, duration: PeekLayout.reducedMotionDuration)
      } else {
        // Opaque for the first third, gone by two thirds of the way.
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, 0.33, 0.66]
        fade.duration = PeekLayout.closeDuration
        layer.add(fade, forKey: "peekFade")
        let shrink = CABasicAnimation(keyPath: "transform")
        shrink.fromValue = CATransform3DIdentity
        shrink.toValue = PeekLayout.growTransform(
          from: origin, position: layer.position, scale: PeekLayout.startScale)
        shrink.duration = PeekLayout.closeDuration
        shrink.timingFunction = PeekLayout.timing(PeekLayout.openTiming)
        layer.transform = shrink.toValue as? CATransform3D ?? CATransform3DIdentity
        layer.add(shrink, forKey: "peekShrink")
      }
    }
    if let layer = wash.layer {
      layer.opacity = 0
      fade(layer, from: 1, to: 0, duration: parentDuration, timing: parentTiming)
    }
    if !reduceMotion, let scaler = cardScaler.layer {
      // The card grows back to its size.
      let grow = CABasicAnimation(keyPath: "sublayerTransform")
      grow.fromValue = PeekLayout.parentTransform(size: cardScaler.bounds.size, anchor: scaler.anchorPoint)
      grow.toValue = CATransform3DIdentity
      grow.duration = parentDuration
      grow.timingFunction = parentTiming
      scaler.add(grow, forKey: "peekParentClose")
      if !isBare {
        animateShadow(from: cardShadowPath(peeking: true), duration: parentDuration, timing: parentTiming)
      }
    }
    CATransaction.commit()
  }
}

/// The wash over the parent page behind a Peek: the window's background
/// colour, light grey in Light Mode and dark grey in Dark Mode, part
/// transparent (add-peek design D4).
enum PeekWash {
  static let color = NSColor(name: "clair.peekWash") { appearance in
    appearance.isDark
      ? NSColor(white: 0.13, alpha: 0.55)
      : NSColor(white: 0.93, alpha: 0.55)
  }
}

/// An NSView whose origin is at the top left, as Chromium's and DevTools'
/// coordinates are.
/// A still of a page, faded, as Arc shows a tab another window took: the
/// image fills the card from its top, partly see-through over the window's
/// background colour.
final class StillView: NSView {
  /// The image's opacity. Arc's still takes the page's #2B6FD6 to about
  /// #80A4E2 over its light background, which is 60% (measured with
  /// tests/probe/).
  static let imageOpacity: Float = 0.6

  private let imageLayer = CALayer()

  var image: NSImage? {
    didSet {
      imageLayer.contents = image
      imageLayer.isHidden = image == nil
    }
  }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    imageLayer.contentsGravity = .resizeAspectFill
    imageLayer.masksToBounds = true
    imageLayer.isHidden = true
    imageLayer.opacity = Self.imageOpacity
    layer?.addSublayer(imageLayer)
    // An accessibility element only while it shows (PageCardView.showStill).
    setAccessibilityElement(false)
    setAccessibilityRole(.image)
    setAccessibilityLabel("Open in another window")
    setAccessibilityIdentifier("clair.still")
    updateBackground()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not used")
  }

  override var isFlipped: Bool { true }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateBackground()
  }

  private func updateBackground() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
  }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    // The page's top stays at the card's top when the window's size changed
    // since the copy.
    if let image, image.size.width > 0, bounds.width > 0 {
      let height = bounds.width * image.size.height / image.size.width
      imageLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: max(height, bounds.height))
    } else {
      imageLayer.frame = bounds
    }
    CATransaction.commit()
  }

  // The still stands for the page: a click goes nowhere else.
  override func hitTest(_ point: NSPoint) -> NSView? {
    isHidden ? nil : super.hitTest(point)
  }
}

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
