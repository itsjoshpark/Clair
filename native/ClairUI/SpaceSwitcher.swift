// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import ClairHost
import SwiftUI

/// The footer's Space switcher, as in Arc: one 36×34 pt item per Space, in
/// order, the Space's icon or a dot, the current one darker. Absent with one
/// Space. Clicking an item shows its Space; dragging one onto another moves
/// it there (spaces spec, "Reordering Spaces").
struct SpaceSwitcher: View {
  let items: [SpacesLogic.SwitcherItem]
  /// An extra dot after the items, for the Space the New Space form makes.
  var showsNewSpaceDot = false
  weak var actions: (any SpaceActions)?

  static let itemWidth: CGFloat = 36
  static let itemHeight: CGFloat = 34
  /// Arc's items overlap by 2 pt: a 34 pt pitch, narrowing with every Space
  /// once they no longer fit.
  static let spacing: CGFloat = -2
  /// Items narrow down to this as Spaces are added, before the strip clips.
  static let minimumItemWidth: CGFloat = 14
  static let dotSize: CGFloat = 8
  static let iconSize: CGFloat = 15

  /// The item being dragged, and how far. A drag gesture rather than
  /// SwiftUI's drag and drop, which a button's own tracking never lets start.
  @State private var dragged: SpaceID?
  @State private var dragOffset: CGFloat = 0
  @State private var stripWidth: CGFloat = 0

  /// The distance between the items' centres, as laid out.
  private var pitch: CGFloat {
    let count = CGFloat(max(items.count, 1))
    let width = min(Self.itemWidth, (stripWidth - Self.spacing * (count - 1)) / count)
    return max(width, Self.minimumItemWidth) + Self.spacing
  }

  var body: some View {
    HStack(spacing: Self.spacing) {
      ForEach(items) { item in
        SpaceSwitcherItem(item: item) { actions?.showSpace(item.spaceID) }
          .frame(minWidth: Self.minimumItemWidth, idealWidth: Self.itemWidth, maxWidth: Self.itemWidth)
          .frame(height: Self.itemHeight)
          .offset(x: dragged == item.spaceID ? dragOffset : 0)
          .zIndex(dragged == item.spaceID ? 1 : 0)
          .highPriorityGesture(drag(item))
      }
      if showsNewSpaceDot {
        SpaceSwitcherItem(item: nil, action: {})
          .frame(width: Self.itemWidth, height: Self.itemHeight)
          .allowsHitTesting(false)
      }
    }
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { stripWidth = $0 }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("clair.spaceSwitcher")
  }

  /// Dragging an item along the strip moves its Space to the slot it's
  /// dropped on (spaces spec, "Reordering Spaces"). A press that doesn't move
  /// is the button's click.
  private func drag(_ item: SpacesLogic.SwitcherItem) -> some Gesture {
    DragGesture(minimumDistance: 4)
      .onChanged { value in
        dragged = item.spaceID
        dragOffset = value.translation.width
      }
      .onEnded { value in
        if let from = items.firstIndex(where: { $0.spaceID == item.spaceID }) {
          let to = SpacesLogic.dragTarget(
            from: from, translation: value.translation.width, pitch: pitch, count: items.count)
          if to != from {
            actions?.moveSpace(item.spaceID, to: to)
          }
        }
        dragged = nil
        dragOffset = 0
      }
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
            .fill(Color.primary.opacity(isCurrent ? 0.6 : 0.3))
            .frame(width: SpaceSwitcher.dotSize, height: SpaceSwitcher.dotSize)
        }
      }
      // The whole item is the button, not just its dot.
      .frame(maxWidth: .infinity, maxHeight: .infinity)
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

