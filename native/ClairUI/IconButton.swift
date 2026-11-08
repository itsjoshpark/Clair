// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import SwiftUI

/// The sizes of the sidebar's icon buttons, as measured in Arc.
enum IconButtonSize {
  /// The top row's buttons, pinned extensions, the extensions button and the
  /// downloads button.
  static let regular: CGFloat = 32
  /// The compact top row and the URL field's buttons.
  static let small: CGFloat = 28
  /// The tab row's speaker and close buttons.
  static let tab: CGFloat = 26
}

/// The hover background every sidebar icon button draws: a rounded fill that
/// fades in under the pointer (design D18), and none while disabled. A `Menu`
/// label uses it directly, since a menu can't be an `IconButton`.
struct IconButtonChrome: ViewModifier {
  var size: CGFloat
  var cornerRadius: CGFloat = 6

  @State private var isHovered = false
  @Environment(\.isEnabled) private var isEnabled

  func body(content: Content) -> some View {
    content
      .frame(width: size, height: size)
      .background(Color.primary.opacity(isHovered && isEnabled ? 0.08 : 0), in: .rect(cornerRadius: cornerRadius))
      .animation(sidebarHoverFade, value: isHovered)
      .contentShape(Rectangle())
      .onHover { isHovered = $0 }
  }
}

/// A square button in the sidebar's style, as in Arc: a grey glyph, a hover
/// background, Clair's tooltip, and dimmed while disabled or while the window
/// isn't key.
struct IconButton<Label: View>: View {
  let help: String
  var shortcut: [String]
  var isEnabled: Bool
  var size: CGFloat
  var cornerRadius: CGFloat
  /// Whether the glyph dims while the window isn't key. The tab row's buttons
  /// don't: the row has its own inactive styling.
  var dimsWhenInactive: Bool
  /// A fixed colour in place of the dimming greys.
  var foreground: Color?
  let action: () -> Void
  let label: Label

  @Environment(\.isWindowKey) private var isWindowKey

  init(
    help: String, shortcut: [String] = [], isEnabled: Bool = true, size: CGFloat = IconButtonSize.regular,
    cornerRadius: CGFloat = 6, dimsWhenInactive: Bool = true, foreground: Color? = nil,
    action: @escaping () -> Void, @ViewBuilder label: () -> Label
  ) {
    self.help = help
    self.shortcut = shortcut
    self.isEnabled = isEnabled
    self.size = size
    self.cornerRadius = cornerRadius
    self.dimsWhenInactive = dimsWhenInactive
    self.foreground = foreground
    self.action = action
    self.label = label()
  }

  var body: some View {
    Button(action: action) {
      label.modifier(IconButtonChrome(size: size, cornerRadius: cornerRadius))
    }
    .buttonStyle(.plain)
    .foregroundStyle(style)
    .disabled(!isEnabled)
    .tooltip(help, shortcut: shortcut)
    .accessibilityLabel(help)
  }

  private var style: AnyShapeStyle {
    if let foreground { return AnyShapeStyle(foreground) }
    return isEnabled && (isWindowKey || !dimsWhenInactive) ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary)
  }
}

/// A pull-down menu in the icon buttons' style: the same hover background,
/// grey and dimming, with a native menu under it.
struct IconMenu<Content: View, Label: View>: View {
  let help: String
  var size: CGFloat = IconButtonSize.regular
  @ViewBuilder let content: () -> Content
  @ViewBuilder let label: () -> Label

  @Environment(\.isWindowKey) private var isWindowKey

  var body: some View {
    Menu {
      content()
    } label: {
      label().modifier(IconButtonChrome(size: size))
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .foregroundStyle(isWindowKey ? .secondary : .tertiary)
    .tooltip(help)
    .accessibilityLabel(help)
  }
}

/// An SF Symbol at an icon button's glyph size.
struct SymbolGlyph: View {
  let systemImage: String
  var size: CGFloat = 16
  var weight: Font.Weight = .medium

  var body: some View {
    Image(systemName: systemImage).font(.system(size: size, weight: weight))
  }
}

extension IconButton where Label == SymbolGlyph {
  init(
    systemImage: String, help: String, shortcut: [String] = [], isEnabled: Bool = true,
    size: CGFloat = IconButtonSize.regular, cornerRadius: CGFloat = 6, glyphSize: CGFloat = 16,
    glyphWeight: Font.Weight = .medium, dimsWhenInactive: Bool = true, action: @escaping () -> Void
  ) {
    self.init(
      help: help, shortcut: shortcut, isEnabled: isEnabled, size: size, cornerRadius: cornerRadius,
      dimsWhenInactive: dimsWhenInactive, action: action
    ) {
      SymbolGlyph(systemImage: systemImage, size: glyphSize, weight: glyphWeight)
    }
  }
}
