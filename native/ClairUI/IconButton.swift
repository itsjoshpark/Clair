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

/// An item in an icon button's menu.
enum IconMenuItem {
  case action(title: String, key: String, modifiers: NSEvent.ModifierFlags, isEnabled: Bool, run: () -> Void)
  case separator

  /// A menu item. `key` is its key equivalent, which the menu shows as its
  /// shortcut; the menu only exists while it's open, so it never takes the
  /// key from the main menu.
  static func button(
    _ title: String, key: String = "", modifiers: NSEvent.ModifierFlags = .command, isEnabled: Bool = true,
    run: @escaping () -> Void
  ) -> IconMenuItem {
    .action(title: title, key: key, modifiers: modifiers, isEnabled: isEnabled, run: run)
  }
}

/// An icon button that opens a native menu against one of its edges: below it,
/// or above it at the bottom of the sidebar. The menu starts clear of the
/// button, so it never covers it. SwiftUI's `Menu` can't be placed: near the
/// bottom of the screen it slides up over its button.
struct IconMenu<Label: View>: View {
  let help: String
  var size: CGFloat = IconButtonSize.regular
  /// The edge of the button the menu opens from.
  var edge: VerticalEdge = .bottom
  /// The menu's items, made as it opens, so they show the current state.
  let items: () -> [IconMenuItem]
  @ViewBuilder let label: () -> Label

  @State private var anchor = MenuAnchor()

  var body: some View {
    IconButton(help: help, size: size, action: { anchor.popUp(items(), from: edge) }, label: label)
      .background(MenuAnchor.Host(anchor: anchor))
  }
}

/// The button's AppKit view, which `NSMenu` positions its menu against.
@MainActor
final class MenuAnchor {
  /// The gap between the button and the menu.
  static let gap: CGFloat = 4

  weak var view: NSView?

  func popUp(_ items: [IconMenuItem], from edge: VerticalEdge) {
    guard let view else { return }
    let menu = NSMenu()
    menu.autoenablesItems = false
    for item in items {
      switch item {
      case .separator:
        menu.addItem(.separator())
      case .action(let title, let key, let modifiers, let isEnabled, let run):
        let action = MenuAction(run: run)
        let menuItem = NSMenuItem(title: title, action: #selector(MenuAction.runAction), keyEquivalent: key)
        menuItem.keyEquivalentModifierMask = modifiers
        menuItem.isEnabled = isEnabled
        menuItem.target = action
        // The item holds its action: an item's target isn't retained.
        menuItem.representedObject = action
        menu.addItem(menuItem)
      }
    }
    // The point is the menu's top-left corner, in the view's coordinates.
    let bounds = view.bounds
    let below = view.isFlipped ? bounds.maxY + Self.gap : bounds.minY - Self.gap
    let above = view.isFlipped ? bounds.minY - Self.gap - menu.size.height : bounds.maxY + Self.gap + menu.size.height
    menu.popUp(positioning: nil, at: NSPoint(x: bounds.minX, y: edge == .bottom ? below : above), in: view)
  }

  /// Sits behind the button and lets every click through to it.
  struct Host: NSViewRepresentable {
    let anchor: MenuAnchor

    func makeNSView(context: Context) -> PassThroughView {
      let view = PassThroughView()
      anchor.view = view
      return view
    }

    func updateNSView(_ view: PassThroughView, context: Context) {
      anchor.view = view
    }
  }

  final class PassThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
  }

  /// A menu item's action, boxed for its target.
  final class MenuAction: NSObject {
    let run: () -> Void

    init(run: @escaping () -> Void) {
      self.run = run
    }

    @objc func runAction() {
      run()
    }
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
