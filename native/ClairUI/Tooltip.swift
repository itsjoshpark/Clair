// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import SwiftUI

/// A tooltip in Arc's style (design D18): the label and the shortcut's keys in
/// a capsule below and after the pointer. AppKit's tooltips never show in
/// Chromium's window, so Clair draws its own, in a small window of its own
/// above the one under the pointer.
struct Tooltip: Equatable {
  var text: String
  var shortcut: [String] = []
}

/// The app's one tooltip: it shows once the pointer has rested on a control
/// for the control's delay, and goes as soon as the pointer leaves it. Controls
/// can nest, as a tab's close button in its row; the one entered last, the
/// innermost, owns the tooltip, and leaving it hands it back to the outer one.
@MainActor
final class TooltipCenter {
  static let shared = TooltipCenter()

  /// Arc's: about 470 ms.
  nonisolated static let delay: Duration = .milliseconds(470)

  private struct Entry {
    let id: UUID
    var tooltip: Tooltip
    let delay: Duration
  }

  private(set) var current: Tooltip?
  /// The controls under the pointer, outermost first.
  private var hovered: [Entry] = []
  private var pending: Task<Void, Never>?
  private lazy var window = TooltipWindow()

  /// The pointer is over control `id`.
  func pointerMoved(over id: UUID, tooltip: Tooltip, delay: Duration = TooltipCenter.delay) {
    if let index = hovered.firstIndex(where: { $0.id == id }) {
      hovered[index].tooltip = tooltip
      // Follow a changing label on the owner, as reload's turning into stop.
      if index == hovered.count - 1, current != nil, current != tooltip {
        current = tooltip
        window.show(tooltip, at: nil)
      }
      return
    }
    hovered.append(Entry(id: id, tooltip: tooltip, delay: delay))
    scheduleOwner()
  }

  /// The pointer left control `id`.
  func pointerLeft(_ id: UUID) {
    guard let index = hovered.firstIndex(where: { $0.id == id }) else { return }
    let wasOwner = index == hovered.count - 1
    hovered.remove(at: index)
    if wasOwner {
      scheduleOwner()
    }
  }

  /// Hides the tooltip until the pointer moves to another control.
  func dismiss() {
    hide()
  }

  /// Shows the innermost control's tooltip once its delay has passed.
  private func scheduleOwner() {
    hide()
    guard let owner = hovered.last else { return }
    pending = Task { [weak self] in
      try? await Task.sleep(for: owner.delay)
      guard !Task.isCancelled, let self, let entry = self.hovered.last, entry.id == owner.id else { return }
      self.current = entry.tooltip
      self.window.show(entry.tooltip, at: NSEvent.mouseLocation)
    }
  }

  private func hide() {
    pending?.cancel()
    pending = nil
    current = nil
    window.hide()
  }
}

extension View {
  /// Shows `text`, and the shortcut's keys, in Clair's tooltip once the pointer
  /// has rested on the view for `delay`.
  func tooltip(_ text: String?, shortcut: [String] = [], delay: Duration = TooltipCenter.delay) -> some View {
    modifier(TooltipModifier(tooltip: text.map { Tooltip(text: $0, shortcut: shortcut) }, delay: delay))
  }
}

private struct TooltipModifier: ViewModifier {
  /// Nil while the view has no tooltip.
  let tooltip: Tooltip?
  let delay: Duration

  @State private var id = UUID()

  func body(content: Content) -> some View {
    content
      .onContinuousHover { phase in
        switch phase {
        case .active:
          if let tooltip {
            TooltipCenter.shared.pointerMoved(over: id, tooltip: tooltip, delay: delay)
          } else {
            TooltipCenter.shared.pointerLeft(id)
          }
        case .ended:
          TooltipCenter.shared.pointerLeft(id)
        }
      }
      .onDisappear { TooltipCenter.shared.pointerLeft(id) }
  }
}

/// The tooltip's window: borderless, never key, never under the pointer's
/// clicks, and a child of the window under the pointer, so it shows over that
/// window in full screen too.
private final class TooltipWindow: NSPanel {
  /// Where the capsule's top-leading corner goes from the pointer, as in Arc.
  static let offset = CGSize(width: 10, height: 10)

  private let host = NSHostingView(rootView: TooltipView(tooltip: Tooltip(text: "")))
  private var origin: NSPoint?

  init() {
    super.init(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    ignoresMouseEvents = true
    isReleasedWhenClosed = false
    collectionBehavior = [.fullScreenAuxiliary, .transient, .ignoresCycle]
    host.sizingOptions = [.intrinsicContentSize]
    contentView = host
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  /// Shows `tooltip` below and after `pointer` (screen coordinates), or where
  /// it already is when `pointer` is nil.
  func show(_ tooltip: Tooltip, at pointer: NSPoint?) {
    host.rootView = TooltipView(tooltip: tooltip)
    let size = host.fittingSize
    if let pointer {
      origin = pointer
    }
    guard let origin else { return }
    // The view keeps a margin around the capsule for its shadow.
    var frame = NSRect(
      x: origin.x + Self.offset.width - TooltipView.margin,
      y: origin.y - Self.offset.height + TooltipView.margin - size.height,
      width: size.width, height: size.height)
    if let screen = NSScreen.screens.first(where: { $0.frame.contains(origin) }) {
      let visible = screen.visibleFrame
      frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
      frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
    }
    // Whole points, so the text stays sharp.
    frame.origin.x = frame.origin.x.rounded()
    frame.origin.y = frame.origin.y.rounded()
    setFrame(frame, display: true)
    if parent == nil, let parent = Self.window(under: origin) {
      parent.addChildWindow(self, ordered: .above)
    }
    if !isVisible {
      alphaValue = 0
      orderFront(nil)
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.1
        animator().alphaValue = 1
      }
    }
  }

  func hide() {
    origin = nil
    parent?.removeChildWindow(self)
    orderOut(nil)
  }

  private static func window(under point: NSPoint) -> NSWindow? {
    let number = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
    return NSApp.window(withWindowNumber: number)
  }
}

/// The tooltip's capsule, measured from Arc: 28 pt high with the label 14 pt
/// in, and 18 pt key caps. Arc tints it with the Space's colour; Clair, with
/// no Spaces yet, with the accent colour.
struct TooltipView: View {
  let tooltip: Tooltip

  /// Room around the capsule for its shadow.
  static let margin: CGFloat = 8

  var body: some View {
    let accent = Color.accentColor
    HStack(spacing: 6) {
      Text(tooltip.text)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Color.primary.mix(with: accent, by: 0.3))
        .lineLimit(1)
      if !tooltip.shortcut.isEmpty {
        HStack(spacing: 3) {
          ForEach(Array(tooltip.shortcut.enumerated()), id: \.offset) { _, key in
            KeyCap(key: key)
          }
        }
      }
    }
    .padding(.leading, 14)
    .padding(.trailing, tooltip.shortcut.isEmpty ? 14 : 10)
    .frame(height: 28)
    // The shadow belongs to the capsule alone; on the whole view it would
    // blur the text and shade the key caps.
    .background {
      Capsule()
        .fill(OverlayStyle.background.mix(with: accent, by: 0.07))
        .shadow(color: .black.opacity(0.16), radius: 3, y: 1)
    }
    .padding(Self.margin)
    .fixedSize()
    .accessibilityHidden(true)
  }
}

/// One key of a shortcut, drawn as a flat key cap.
private struct KeyCap: View {
  let key: String

  var body: some View {
    let accent = Color.accentColor
    let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
    Text(key)
      .font(.system(size: 11, weight: .bold))
      .foregroundStyle(accent.mix(with: .black, by: 0.15))
      .padding(.horizontal, key.count > 1 ? 4 : 0)
      .frame(minWidth: 18, minHeight: 18)
      .background(shape.fill(OverlayStyle.background.mix(with: accent, by: 0.16)))
      .overlay(shape.strokeBorder(accent.opacity(0.45), lineWidth: 1))
  }
}
