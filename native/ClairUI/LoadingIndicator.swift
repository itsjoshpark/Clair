// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import QuartzCore

/// Arc's loading indicator (arc-navigation-feedback design D4): a capsule in
/// the inset above the card that runs on time, not on the load's progress.
/// From the start of a visible load it pulses twice, then widens into a track
/// with a fill sweeping along it until the load ends, when it flashes and
/// shrinks away. Free of AppKit: the caller passes the time.
struct LoadingIndicatorModel: Equatable {
  /// What to draw at one moment. Widths are in points; the fill spans
  /// `fillStart` to `fillEnd`, as fractions of the capsule's width.
  struct Frame: Equatable {
    var width: CGFloat
    var trackOpacity: CGFloat
    var fillStart: CGFloat
    var fillEnd: CGFloat
    var fillOpacity: CGFloat
  }

  // Arc's measurements (design.md, Measurements).
  static let height: CGFloat = 4
  /// From the window's top edge to the capsule's.
  static let topOffset: CGFloat = 3
  static let pulseWidth: CGFloat = 44
  static let pulsePeakWidth: CGFloat = 48
  static let trackWidth: CGFloat = 128
  static let pulseOpacity: CGFloat = 0.76
  static let trackOpacity: CGFloat = 0.23
  static let fillOpacity: CGFloat = 0.8
  /// One pulse: fading in and out over `pulseVisible`, then hidden.
  static let pulseVisible: TimeInterval = 1.4
  static let pulseCycle: TimeInterval = 1.6
  static let pulses = 2
  static let widening: TimeInterval = 0.35
  /// One sweep: the fill grows from the left, its left edge follows, and
  /// the track stays empty for the rest of the cycle.
  static let sweepGrow: TimeInterval = 0.33
  static let sweepRetract: TimeInterval = 0.33
  static let sweepCycle: TimeInterval = 1.07
  static let finish: TimeInterval = 0.25
  /// A load that ends sooner than this draws nothing, as in Arc.
  static let minimumShown: TimeInterval = 0.15

  /// When the current visible load started, while it runs.
  private(set) var loadStart: TimeInterval?
  /// When the finish animation started, and what it starts from.
  private var finishStart: TimeInterval?
  private var finishFrom: Frame?

  /// The active tab's `isLoading` changed, or was posted again.
  mutating func loadingChanged(_ isLoading: Bool, now: TimeInterval) {
    if isLoading {
      if loadStart == nil {
        loadStart = now
        finishStart = nil
        finishFrom = nil
      }
      return
    }
    guard let start = loadStart else { return }
    loadStart = nil
    if now - start < Self.minimumShown {
      return
    }
    finishFrom = Self.runningFrame(elapsed: now - start)
    finishStart = now
  }

  /// Another tab became active: show its state at once, without finishing
  /// the old tab's. A tab that's still loading pulses from the switch, since
  /// its snapshot doesn't say when its load began.
  mutating func tabSwitched(isLoading: Bool, now: TimeInterval) {
    loadStart = isLoading ? now : nil
    finishStart = nil
    finishFrom = nil
  }

  /// Whether anything moves, so the view needs frames.
  func isAnimating(at now: TimeInterval) -> Bool {
    if loadStart != nil { return true }
    if let finishStart { return now - finishStart < Self.finish }
    return false
  }

  /// What to draw at `now`, or nil for nothing.
  func frame(at now: TimeInterval) -> Frame? {
    if let start = loadStart {
      return Self.runningFrame(elapsed: max(0, now - start))
    }
    if let finishStart, let from = finishFrom {
      let t = (now - finishStart) / Self.finish
      guard t < 1 else { return nil }
      // A flash to a full fill, shrinking towards the centre as it fades.
      let eased = CGFloat(t * t)
      return Frame(
        width: from.width * (1 - 0.4 * CGFloat(t)), trackOpacity: 0, fillStart: 0, fillEnd: 1,
        fillOpacity: Self.fillOpacity * (1 - eased))
    }
    return nil
  }

  private static func smooth(_ t: Double) -> CGFloat {
    let x = min(max(t, 0), 1)
    return CGFloat(x * x * (3 - 2 * x))
  }

  /// The frame `elapsed` seconds into a running load.
  static func runningFrame(elapsed: TimeInterval) -> Frame {
    let pulsing = pulseCycle * Double(pulses)
    if elapsed < pulsing {
      let t = elapsed.truncatingRemainder(dividingBy: pulseCycle)
      guard t < pulseVisible else {
        return Frame(width: pulseWidth, trackOpacity: 0, fillStart: 0, fillEnd: 1, fillOpacity: 0)
      }
      // Straight up to the peak and back down, as Arc's measures.
      let level = CGFloat(1 - abs(2 * t / pulseVisible - 1))
      return Frame(
        width: pulseWidth + (pulsePeakWidth - pulseWidth) * level, trackOpacity: 0, fillStart: 0, fillEnd: 1,
        fillOpacity: pulseOpacity * level)
    }
    let sweeping = elapsed - pulsing
    let widened = smooth(sweeping / widening)
    let width = pulseWidth + (trackWidth - pulseWidth) * widened
    let t = sweeping.truncatingRemainder(dividingBy: sweepCycle)
    var start: CGFloat = 0
    var end: CGFloat = 0
    if t < sweepGrow {
      end = smooth(t / sweepGrow)
    } else if t < sweepGrow + sweepRetract {
      start = smooth((t - sweepGrow) / sweepRetract)
      end = 1
    }
    return Frame(
      width: width, trackOpacity: trackOpacity * widened, fillStart: start, fillEnd: end,
      fillOpacity: end > start ? fillOpacity : 0)
  }
}

/// Draws `LoadingIndicatorModel` in the inset above the card. It takes no
/// mouse events, so the page-top window drag keeps working under it.
final class LoadingIndicatorView: NSView {
  private(set) var model = LoadingIndicatorModel()
  private let track = CALayer()
  private let fill = CALayer()
  private var link: CADisplayLink?

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    for layer in [track, fill] {
      layer.cornerRadius = LoadingIndicatorModel.height / 2
      layer.actions = ["bounds": NSNull(), "position": NSNull(), "opacity": NSNull(), "backgroundColor": NSNull()]
      self.layer?.addSublayer(layer)
    }
    setAccessibilityElement(false)
    updateColors()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not used")
  }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateColors()
  }

  /// White over Arc's dark inset, black over its light one.
  private func updateColors() {
    let color = (effectiveAppearance.isDark ? NSColor.white : NSColor.black).cgColor
    track.backgroundColor = color
    fill.backgroundColor = color
  }

  func loadingChanged(_ isLoading: Bool) {
    model.loadingChanged(isLoading, now: CACurrentMediaTime())
    redraw()
  }

  func tabSwitched(isLoading: Bool) {
    model.tabSwitched(isLoading: isLoading, now: CACurrentMediaTime())
    redraw()
  }

  private func redraw() {
    let now = CACurrentMediaTime()
    draw(model.frame(at: now))
    if model.isAnimating(at: now) {
      if link == nil {
        let link = displayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        self.link = link
      }
    } else {
      link?.invalidate()
      link = nil
    }
  }

  @objc private func step(_ link: CADisplayLink) {
    redraw()
  }

  override func layout() {
    super.layout()
    draw(model.frame(at: CACurrentMediaTime()))
  }

  private func draw(_ frame: LoadingIndicatorModel.Frame?) {
    guard let frame else {
      track.opacity = 0
      fill.opacity = 0
      return
    }
    let height = LoadingIndicatorModel.height
    let x = (bounds.width - frame.width) / 2
    let y = (bounds.height - height) / 2
    track.frame = CGRect(x: x, y: y, width: frame.width, height: height)
    track.opacity = Float(frame.trackOpacity)
    // A sliver of fill is drawn at least as wide as it's tall, inside the track.
    let width = frame.fillEnd > frame.fillStart ? max(height, frame.width * (frame.fillEnd - frame.fillStart)) : 0
    let start = min(x + frame.width * frame.fillStart, x + frame.width - width)
    fill.frame = CGRect(x: start, y: y, width: width, height: height)
    fill.opacity = Float(frame.fillOpacity)
  }
}
