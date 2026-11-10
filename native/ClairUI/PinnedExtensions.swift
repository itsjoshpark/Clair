// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import SwiftUI

/// How pinned extensions wrap, as in Arc (arc-site-control-center design D1):
/// as few rows as the width allows, then as few columns as those rows allow.
nonisolated struct PinnedExtensionsGrid: Equatable {
  static let spacing: CGFloat = 8
  static let tileHeight: CGFloat = 28
  static let iconSize: CGFloat = 18
  static let minimumTileWidth: CGFloat = 29
  static let maximumColumns: CGFloat = 5

  let columns: Int
  let rows: Int
  let tileWidth: CGFloat

  init(count: Int, width: CGFloat) {
    guard count > 0 else {
      columns = 0
      rows = 0
      tileWidth = 0
      return
    }
    let room = ((width + Self.spacing) / (Self.minimumTileWidth + Self.spacing)).rounded(.down)
    let maxColumns = Int(max(1, min(Self.maximumColumns, room)))
    rows = (count + maxColumns - 1) / maxColumns
    columns = (count + rows - 1) / rows
    tileWidth = (width - Self.spacing * CGFloat(columns - 1)) / CGFloat(columns)
  }

  /// The height of all the rows.
  var height: CGFloat {
    rows == 0 ? 0 : CGFloat(rows) * Self.tileHeight + CGFloat(rows - 1) * Self.spacing
  }
}

/// Lays the pinned tiles out by `PinnedExtensionsGrid`. A shorter last row
/// stays at the leading edge, with tiles of the same width.
struct PinnedExtensionsLayout: Layout {
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.replacingUnspecifiedDimensions().width
    return CGSize(width: width, height: PinnedExtensionsGrid(count: subviews.count, width: width).height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let grid = PinnedExtensionsGrid(count: subviews.count, width: bounds.width)
    let size = ProposedViewSize(width: grid.tileWidth, height: PinnedExtensionsGrid.tileHeight)
    for (index, subview) in subviews.enumerated() {
      let column = CGFloat(index % grid.columns)
      let row = CGFloat(index / grid.columns)
      subview.place(
        at: CGPoint(
          x: bounds.minX + column * (grid.tileWidth + PinnedExtensionsGrid.spacing),
          y: bounds.minY + row * (PinnedExtensionsGrid.tileHeight + PinnedExtensionsGrid.spacing)),
        proposal: size)
    }
  }
}

/// A pinned extension: a tile with the field's fill, which stretches to share
/// the row. It stays dimmed and ignores a left click while its action is off
/// for the tab; its menu still works.
struct PinnedExtensionTile: View {
  let action: any ClairExtensionAction
  let contextMenu: () -> NSMenu?
  let run: () -> Void

  @State private var isHovered = false
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.isWindowKey) private var isWindowKey

  var body: some View {
    Button {
      if action.isEnabled { run() }
    } label: {
      ExtensionIcon(action: action, size: PinnedExtensionsGrid.iconSize)
        .frame(width: PinnedExtensionsGrid.tileHeight, height: PinnedExtensionsGrid.tileHeight)
        .overlay(alignment: .bottomTrailing) {
          if !action.badgeText.isEmpty {
            Text(action.badgeText)
              .font(.system(size: 8, weight: .bold))
              .foregroundStyle(.white)
              .padding(.horizontal, 3)
              .background(Color(nsColor: action.badgeBackgroundColor ?? .systemRed), in: .capsule)
              .accessibilityIdentifier("clair.extensionBadge")
          }
        }
        .opacity(action.isEnabled ? 1 : 0.4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SidebarFill.field(colorScheme, hovered: isHovered), in: .rect(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(IconButtonStyle.grey(isWindowKey: isWindowKey))
    .overlay(RowClickCatcher(onMiddleClick: {}, menuItems: [], menuProvider: contextMenu))
    .onHover { hovering in withAnimation(sidebarHoverFade) { isHovered = hovering } }
    .tooltip(action.name)
    .accessibilityLabel(action.name)
    .accessibilityValue(action.badgeText)
    .accessibilityIdentifier("clair.extensionAction")
  }
}
