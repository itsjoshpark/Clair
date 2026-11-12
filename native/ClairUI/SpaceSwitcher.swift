// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import ClairHost
import SwiftUI
import UniformTypeIdentifiers

/// The footer's Space switcher, as in Arc: one 36×34 pt item per Space, in
/// order, the Space's icon or a dot, the current one darker. Absent with one
/// Space. Clicking an item shows its Space; dragging one onto another moves
/// it there (spaces spec, "Reordering Spaces").
struct SpaceSwitcher: View {
  let items: [SpacesLogic.SwitcherItem]
  /// An extra dot after the items, for the Space the New Space form makes.
  var showsNewSpaceDot = false
  weak var actions: (any SpaceActions)?
  let spaces: [any ClairSpace]

  static let itemWidth: CGFloat = 36
  static let itemHeight: CGFloat = 34
  /// Items narrow down to this as Spaces are added, before the strip clips.
  static let minimumItemWidth: CGFloat = 14
  static let dotSize: CGFloat = 6
  static let iconSize: CGFloat = 15

  @State private var dragged: SpaceID?

  var body: some View {
    HStack(spacing: 0) {
      ForEach(items) { item in
        SpaceSwitcherItem(item: item) { actions?.showSpace(item.spaceID) }
          .frame(minWidth: Self.minimumItemWidth, idealWidth: Self.itemWidth, maxWidth: Self.itemWidth)
          .frame(height: Self.itemHeight)
          .onDrag {
            dragged = item.spaceID
            return NSItemProvider(object: item.spaceID as NSString)
          }
          .onDrop(
            of: [.plainText],
            delegate: SpaceDropDelegate(target: item.spaceID, dragged: $dragged, spaces: spaces, actions: actions))
      }
      if showsNewSpaceDot {
        SpaceSwitcherItem(item: nil, action: {})
          .frame(width: Self.itemWidth, height: Self.itemHeight)
          .allowsHitTesting(false)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("clair.spaceSwitcher")
  }
}

/// One item: the icon or a dot, darker for the current Space.
struct SpaceSwitcherItem: View {
  /// Nil for the New Space form's Space, which has no item yet.
  let item: SpacesLogic.SwitcherItem?
  let action: () -> Void

  @State private var isHovered = false
  @Environment(\.colorScheme) private var colorScheme

  private var isCurrent: Bool { item?.isCurrent ?? true }

  var body: some View {
    Button(action: action) {
      ZStack {
        if isHovered {
          RoundedRectangle(cornerRadius: 8, style: .continuous).fill(SidebarFill.hover(colorScheme))
        }
        if let icon = item?.icon {
          Text(icon)
            .font(.system(size: SpaceSwitcher.iconSize))
            .opacity(isCurrent ? 1 : 0.45)
            .saturation(isCurrent ? 1 : 0.2)
        } else {
          Circle()
            .fill(Color.primary.opacity(isCurrent ? 0.6 : 0.2))
            .frame(width: SpaceSwitcher.dotSize, height: SpaceSwitcher.dotSize)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .help(item?.name ?? "")
    .accessibilityLabel(item?.name ?? "New Space")
    .accessibilityIdentifier(item?.identifier ?? "clair.space.new")
    .accessibilityAddTraits(isCurrent && item != nil ? .isSelected : [])
  }
}

/// Moves the dragged Space to the item it's dropped on.
struct SpaceDropDelegate: DropDelegate {
  let target: SpaceID
  @Binding var dragged: SpaceID?
  let spaces: [any ClairSpace]
  weak var actions: (any SpaceActions)?

  func validateDrop(info: DropInfo) -> Bool {
    dragged != nil
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    DropProposal(operation: .move)
  }

  func performDrop(info: DropInfo) -> Bool {
    defer { dragged = nil }
    guard let dragged, let index = SpacesLogic.dropIndex(moving: dragged, onto: target, in: spaces) else {
      return false
    }
    actions?.moveSpace(dragged, to: index)
    return true
  }
}
