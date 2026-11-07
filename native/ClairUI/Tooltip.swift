// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import Observation
import SwiftUI

/// A tooltip in Arc's style (design D18): the label and the shortcut's keys in
/// a capsule below and after the pointer. AppKit's tooltips never show in
/// Chromium's window, so the sidebar draws its own.
struct Tooltip: Equatable {
  var text: String
  var shortcut: [String]
  /// The pointer when the tooltip showed, in the sidebar's coordinates.
  var point: CGPoint
}

/// The window's one tooltip: it shows once the pointer has rested on a
/// control for `delay`, and goes as soon as the pointer leaves it.
@MainActor
@Observable
final class TooltipCenter {
  /// Arc's: about 470 ms.
  static let delay: Duration = .milliseconds(470)

  private(set) var current: Tooltip?
  @ObservationIgnored private var owner: UUID?
  @ObservationIgnored private var pointer: CGPoint = .zero
  @ObservationIgnored private var pending: Task<Void, Never>?

  /// The pointer is over control `id` at `point`.
  func pointerMoved(over id: UUID, text: String, shortcut: [String], at point: CGPoint) {
    pointer = point
    if owner == id {
      // Keep the tooltip where it showed, but follow a changing label, as
      // reload's turning into stop.
      if let current, current.text != text || current.shortcut != shortcut {
        self.current = Tooltip(text: text, shortcut: shortcut, point: current.point)
      }
      return
    }
    owner = id
    current = nil
    pending?.cancel()
    pending = Task { [weak self] in
      try? await Task.sleep(for: Self.delay)
      guard !Task.isCancelled, let self, self.owner == id else { return }
      self.current = Tooltip(text: text, shortcut: shortcut, point: self.pointer)
    }
  }

  /// The pointer left control `id`.
  func pointerLeft(_ id: UUID) {
    guard owner == id else { return }
    dismiss()
  }

  func dismiss() {
    owner = nil
    pending?.cancel()
    pending = nil
    current = nil
  }
}

extension View {
  /// Shows `text`, and the shortcut's keys, in the window's tooltip.
  func tooltip(_ text: String, shortcut: [String] = []) -> some View {
    modifier(TooltipModifier(text: text, shortcut: shortcut))
  }
}

private struct TooltipModifier: ViewModifier {
  let text: String
  let shortcut: [String]

  @Environment(TooltipCenter.self) private var center: TooltipCenter?
  @State private var id = UUID()

  func body(content: Content) -> some View {
    content
      .onContinuousHover(coordinateSpace: .named(sidebarCoordinateSpace)) { phase in
        switch phase {
        case .active(let point):
          center?.pointerMoved(over: id, text: text, shortcut: shortcut, at: point)
        case .ended:
          center?.pointerLeft(id)
        }
      }
      .onDisappear { center?.pointerLeft(id) }
  }
}

/// The tooltip's capsule, measured from Arc: 28 pt high with the label 14 pt
/// in, and 18 pt key caps with a deeper bottom edge. Arc tints it with the
/// Space's colour; Clair, with no Spaces yet, with the accent colour.
struct TooltipView: View {
  let tooltip: Tooltip

  /// Where the capsule's top-leading corner goes from the pointer, as in Arc.
  static let offset = CGSize(width: 10, height: 10)

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
    .background(OverlayStyle.background.mix(with: accent, by: 0.07), in: .capsule)
    .shadow(color: .black.opacity(0.16), radius: 3, y: 1)
    .padding(8)
    .fixedSize()
    .accessibilityHidden(true)
  }
}

/// One key of a shortcut, drawn as a key cap.
private struct KeyCap: View {
  let key: String

  var body: some View {
    let accent = Color.accentColor
    let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
    Text(key)
      .font(.system(size: 11, weight: .bold))
      .foregroundStyle(accent.mix(with: .black, by: 0.15))
      .padding(.horizontal, key.count > 1 ? 4 : 0)
      .frame(minWidth: 18, minHeight: 16.5)
      .background(shape.fill(OverlayStyle.background.mix(with: accent, by: 0.16)))
      .overlay(shape.strokeBorder(accent.opacity(0.45), lineWidth: 1))
      // The key's deeper bottom edge.
      .background(shape.fill(accent.opacity(0.6)).offset(y: 1.5))
      .padding(.bottom, 1.5)
  }
}

/// A hosting view that never takes the pointer, so a tooltip under it doesn't
/// end the hover that showed it.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
  required init(rootView: Content) {
    super.init(rootView: rootView)
    safeAreaRegions = []
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not used")
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }
}
