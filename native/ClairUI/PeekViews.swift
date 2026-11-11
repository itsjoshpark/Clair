// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import SwiftUI

/// Where a Peek and its parent sit in the page card (add-peek design D4), as
/// measured in Arc at a 1723×1030 pt card.
enum PeekLayout {
  /// The Peek's width over the card's: Arc's 1386 pt at a 1723 pt card.
  static let widthFraction: CGFloat = 1386.0 / 1723.0
  /// Between the Peek and the card's top and bottom edges.
  static let verticalInset: CGFloat = 2
  /// How far the parent page shrinks on each side behind the Peek: 9 pt in
  /// Arc at any window size.
  static let parentInset: CGFloat = 9
  static let cornerRadius: CGFloat = 10
  /// The card's shadow: tight and even on every side, as in Arc, about 15%
  /// darker at the card's edge and gone 7.5 pt out.
  static let shadowOpacity: Float = 0.3
  static let shadowRadius: CGFloat = 4
  /// The round buttons beside the Peek's top-trailing corner.
  static let buttonSize = CGSize(width: 34.5, height: 33.5)
  /// From the Peek's trailing edge to the buttons.
  static let buttonGap: CGFloat = 13
  /// From the Peek's top to the first button's.
  static let buttonTop: CGFloat = 7.5
  /// From one button's top to the next one's.
  static let buttonPitch: CGFloat = 43.5

  /// The Peek's frame in a card with `bounds` (top-left origin), in whole
  /// points.
  static func peekFrame(in bounds: CGRect) -> CGRect {
    let width = (bounds.width * widthFraction).rounded()
    let height = max(0, bounds.height - 2 * verticalInset)
    return CGRect(
      x: (bounds.midX - width / 2).rounded(), y: bounds.minY + verticalInset, width: width, height: height)
  }

  /// The parent page's frame behind the Peek: the card less `parentInset` on
  /// each side.
  static func parentFrame(in bounds: CGRect) -> CGRect {
    bounds.insetBy(dx: min(parentInset, bounds.width / 2), dy: min(parentInset, bounds.height / 2))
  }

  /// The buttons' frames beside a Peek at `peek`, top first: Close, then
  /// Expand.
  static func buttonFrames(beside peek: CGRect, count: Int = 2) -> [CGRect] {
    (0..<count).map { index in
      CGRect(
        x: peek.maxX + buttonGap, y: peek.minY + buttonTop + CGFloat(index) * buttonPitch,
        width: buttonSize.width, height: buttonSize.height)
    }
  }

  /// The transform that shrinks a page of `size` into `parentFrame`, for a
  /// layer whose anchor point is `anchor`: a scale about the page's centre.
  static func parentTransform(size: CGSize, anchor: CGPoint) -> CATransform3D {
    guard size.width > 0, size.height > 0 else { return CATransform3DIdentity }
    let target = parentFrame(in: CGRect(origin: .zero, size: size))
    let scaleX = target.width / size.width
    let scaleY = target.height / size.height
    // p' = s·p + d about the layer's origin; the layer applies the transform
    // about its anchor point, so the translation makes up the difference.
    let pivot = CGPoint(x: anchor.x * size.width, y: anchor.y * size.height)
    let dx = target.minX - (1 - scaleX) * pivot.x
    let dy = target.minY - (1 - scaleY) * pivot.y
    return CATransform3DConcat(CATransform3DMakeScale(scaleX, scaleY, 1), CATransform3DMakeTranslation(dx, dy, 0))
  }

  /// The transform that shrinks a layer at `frame` towards `point` (both in
  /// its superlayer's coordinates) to `scale`, for a layer whose `position`
  /// is `position`: what the Peek grows from and shrinks back to.
  static func growTransform(from point: CGPoint, position: CGPoint, scale: CGFloat) -> CATransform3D {
    let dx = (1 - scale) * (point.x - position.x)
    let dy = (1 - scale) * (point.y - position.y)
    return CATransform3DConcat(CATransform3DMakeScale(scale, scale, 1), CATransform3DMakeTranslation(dx, dy, 0))
  }

  // The animations, from 60 fps recordings of Arc (add-peek design D5).
  /// How long the Peek takes to grow: it covers two thirds of the way in the
  /// first quarter, then settles.
  static let openDuration: TimeInterval = 0.19
  static let openTiming = (0.3, 1.0, 0.75, 1.0)
  /// How long the parent page and the wash take to shrink and fade in, or
  /// back.
  static let parentDuration: TimeInterval = 0.16
  static let parentTiming = (0.25, 0.8, 0.5, 1.0)
  /// How long the closing Peek takes to shrink back; it fades out in the
  /// middle of it.
  static let closeDuration: TimeInterval = 0.15
  /// The fades that replace them with Reduce Motion on.
  static let reducedMotionDuration: TimeInterval = 0.15
  /// Room the Confirm pill grows into beside the column.
  static let confirmWidth: CGFloat = 110
  /// How small the Peek starts: about a link's size in Arc, which grows it
  /// from the link.
  static let startScale: CGFloat = 0.1
  /// The glyphs' point sizes: 12 pt and 14 pt across in Arc.
  static let closeGlyphSize: CGFloat = 15
  static let expandGlyphSize: CGFloat = 14.5

  static func timing(_ points: (Double, Double, Double, Double)) -> CAMediaTimingFunction {
    CAMediaTimingFunction(
      controlPoints: Float(points.0), Float(points.1), Float(points.2), Float(points.3))
  }
}

/// What the Peek's buttons do.
@MainActor
protocol PeekActions: AnyObject {
  func closePeek()
  func expandPeek()
}

/// The column of round buttons beside the Peek (add-peek design D4, D6):
/// Close, which turns into a red Confirm pill while an Esc the page kept
/// arms the next one, and Expand.
struct PeekControlsView: View {
  let confirm: PeekConfirmState
  weak var actions: (any PeekActions)?

  var body: some View {
    let towardPeek = confirm.growsTowardPeek
    VStack(alignment: towardPeek ? .trailing : .leading, spacing: PeekLayout.buttonPitch - PeekLayout.buttonSize.height) {
      // Confirm grows from the ×, to the trailing side or, without room
      // there, over the Peek, without moving the column.
      PeekCloseButton(isConfirming: confirm.isShowing) { actions?.closePeek() }
        .fixedSize()
        .frame(
          width: PeekLayout.buttonSize.width, height: PeekLayout.buttonSize.height,
          alignment: towardPeek ? .trailing : .leading)
      PeekRoundButton(
        systemImage: "arrow.up.left.and.arrow.down.right", glyphSize: PeekLayout.expandGlyphSize, tooltip: "Expand",
        shortcut: ["⌘", "O"],
        label: "Expand Peek into a tab",
        identifier: "clair.peekExpand"
      ) { actions?.expandPeek() }
    }
    .fixedSize()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: towardPeek ? .topTrailing : .topLeading)
  }
}

/// A round button beside the Peek: a translucent disc with a shadow, darker
/// under the pointer.
struct PeekRoundButton: View {
  let systemImage: String
  let glyphSize: CGFloat
  /// Arc's tooltip, read by hovering its buttons.
  let tooltip: String
  var shortcut: [String] = []
  /// What VoiceOver reads.
  let label: String
  let identifier: String
  let action: () -> Void

  @State private var isHovered = false
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: glyphSize, weight: .semibold))
        .foregroundStyle(PeekButtonBackground.glyph)
        .frame(width: PeekLayout.buttonSize.width, height: PeekLayout.buttonSize.height)
        .background(PeekButtonBackground(isHovered: isHovered, colorScheme: colorScheme))
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .tooltip(tooltip, shortcut: shortcut)
    .accessibilityLabel(label)
    .accessibilityIdentifier(identifier)
  }
}

/// The Close button, which grows into "× Confirm" in red while another Esc
/// closes the Peek.
struct PeekCloseButton: View {
  let isConfirming: Bool
  let action: () -> Void

  @State private var isHovered = false
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  static let help = "Close Peek"

  var body: some View {
    Button(action: action) {
      HStack(spacing: 5) {
        Image(systemName: "xmark")
          .font(.system(size: PeekLayout.closeGlyphSize, weight: .semibold))
        if isConfirming {
          Text("Confirm")
            .font(.system(size: 13, weight: .semibold))
            .fixedSize()
            .transition(.opacity)
        }
      }
      .foregroundStyle(isConfirming ? Color.white : PeekButtonBackground.glyph)
      .padding(.horizontal, isConfirming ? 12 : 0)
      .frame(minWidth: PeekLayout.buttonSize.width, minHeight: PeekLayout.buttonSize.height)
      .background {
        if isConfirming {
          Capsule().fill(Color(nsColor: .systemRed).opacity(isHovered ? 0.85 : 1))
            .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
        } else {
          PeekButtonBackground(isHovered: isHovered, colorScheme: colorScheme)
        }
      }
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    // Grows from the × in about 100 ms and shrinks back as fast, as in Arc.
    .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: isConfirming)
    // Arc's tooltip, read by hovering its button.
    .tooltip(isConfirming ? nil : "Close", shortcut: ["⌘", "W"])
    .accessibilityLabel(isConfirming ? "Confirm close Peek" : Self.help)
    .accessibilityIdentifier("clair.peekClose")
  }
}

/// The buttons' disc, as in Arc: white (dark grey in Dark Mode) with a soft
/// shadow, and the glyph in the accent colour.
struct PeekButtonBackground: View {
  let isHovered: Bool
  let colorScheme: ColorScheme

  static let glyph = Color.accentColor

  var body: some View {
    Capsule()
      .fill(colorScheme == .dark ? Color(white: 0.22) : Color.white)
      .overlay(Capsule().fill(Color.primary.opacity(isHovered ? 0.08 : 0)))
      .overlay(Capsule().strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06), lineWidth: 0.5))
      .shadow(color: .black.opacity(0.16), radius: 3, y: 1)
  }
}
