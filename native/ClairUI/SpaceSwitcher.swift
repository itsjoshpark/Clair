// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
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

  /// The item being dragged, and how far (`SpaceReorderDrag`).
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
        // The button is for accessibility and the keyboard; the mouse's
        // click and drag are the catcher's.
        SpaceSwitcherItem(item: item) { actions?.showSpace(item.spaceID) }
          .frame(minWidth: Self.minimumItemWidth, idealWidth: Self.itemWidth, maxWidth: Self.itemWidth)
          .frame(height: Self.itemHeight)
          .spaceReorderDrag(
            for: item.spaceID, in: items.map(\.spaceID), along: .horizontal, pitch: pitch,
            dragged: $dragged, offset: $dragOffset,
            onClick: { [weak actions] in actions?.showSpace(item.spaceID) },
            move: { [weak actions] spaceID, index in actions?.moveSpace(spaceID, to: index) }
          )
          .offset(x: dragged == item.spaceID ? dragOffset : 0)
          .zIndex(dragged == item.spaceID ? 1 : 0)
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
}

/// The click and the drag on a Space, in the switcher and in Manage Spaces: a
/// press that doesn't move is a click; one that moves `SpaceReorderDrag.slop`
/// points drags the Space along `axis`, and moves it to the slot it's dropped
/// on (`SpacesLogic.dragTarget`).
///
/// An AppKit view over the item takes the mouse, as `RowClickCatcher` does for
/// a row's menu: a SwiftUI drag gesture never moved under XCUITest's drags on
/// CI, where AppKit's own mouse tracking does, and SwiftUI's drag and drop
/// never started from a button or in a dialog.
struct SpaceReorderDrag: NSViewRepresentable {
  /// The distance a press moves before it's a drag, as the gesture's was.
  static let slop: CGFloat = 4

  let axis: Axis
  let onClick: () -> Void
  /// The drag moved: how far along the axis, in the direction SwiftUI counts.
  let onChanged: (CGFloat) -> Void
  /// The drag ended, that far along.
  let onEnded: (CGFloat) -> Void

  func makeNSView(context: Context) -> CatcherView {
    let view = CatcherView()
    updateNSView(view, context: context)
    return view
  }

  func updateNSView(_ view: CatcherView, context: Context) {
    view.drag = self
  }

  final class CatcherView: NSView {
    var drag: SpaceReorderDrag?
    private var start: NSPoint?
    private var isDragging = false

    /// Only the left button's press: hovering, scrolling and right clicks go
    /// to the item under it.
    override func hitTest(_ point: NSPoint) -> NSView? {
      guard let event = NSApp.currentEvent, event.type == .leftMouseDown,
        !event.modifierFlags.contains(.control)
      else { return nil }
      return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    /// How far `event` is from the press, along the axis; AppKit counts up
    /// where SwiftUI counts down.
    private func distance(_ event: NSEvent) -> CGFloat {
      guard let start, let drag else { return 0 }
      let point = event.locationInWindow
      return drag.axis == .horizontal ? point.x - start.x : start.y - point.y
    }

    override func mouseDown(with event: NSEvent) {
      start = event.locationInWindow
      isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
      guard start != nil else { return }
      let distance = distance(event)
      if !isDragging, abs(distance) >= SpaceReorderDrag.slop {
        isDragging = true
      }
      if isDragging {
        drag?.onChanged(distance)
      }
    }

    override func mouseUp(with event: NSEvent) {
      guard start != nil else { return }
      let distance = distance(event)
      if isDragging {
        drag?.onEnded(distance)
      } else if bounds.contains(convert(event.locationInWindow, from: nil)) {
        drag?.onClick()
      }
      start = nil
      isDragging = false
    }
  }
}

extension View {
  /// Makes the view, which shows `spaceID`, clickable and draggable among
  /// `order`, laid out `pitch` apart along `axis`. While it's dragged,
  /// `dragged` is its Space and `offset` how far, for the view to follow the
  /// pointer; `move` is called once, at the drop, when it lands on another
  /// slot.
  func spaceReorderDrag(
    for spaceID: SpaceID, in order: [SpaceID], along axis: Axis, pitch: CGFloat,
    dragged: Binding<SpaceID?>, offset: Binding<CGFloat>, onClick: @escaping () -> Void,
    move: @escaping (SpaceID, Int) -> Void
  ) -> some View {
    overlay {
      SpaceReorderDrag(
        axis: axis, onClick: onClick,
        onChanged: { distance in
          dragged.wrappedValue = spaceID
          offset.wrappedValue = distance
        },
        onEnded: { distance in
          if let from = order.firstIndex(of: spaceID) {
            let to = SpacesLogic.dragTarget(from: from, translation: distance, pitch: pitch, count: order.count)
            if to != from {
              move(spaceID, to)
            }
          }
          dragged.wrappedValue = nil
          offset.wrappedValue = 0
        })
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

