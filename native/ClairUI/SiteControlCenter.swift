// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import SwiftUI

/// The Site Control Center's rules (arc-site-control-center design D4, D5).
enum SiteControlCenterLogic {
  static let columns = 4
  static let tileWidth: CGFloat = 48
  static let tileHeight: CGFloat = 32
  static let spacing: CGFloat = 8
  /// The grid scrolls beyond this many rows, so the popover fits a small
  /// display.
  static let maximumVisibleRows = 8

  /// Pinned extensions first, in their pinned order, then the others A to Z.
  static func ordered(_ actions: [any ClairExtensionAction]) -> [any ClairExtensionAction] {
    let others = actions.filter { !$0.isPinned }.sorted {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
    return actions.filter(\.isPinned) + others
  }

  /// Whether Chromium's page info has anything to say about a URL; the same
  /// schemes as `PageInfo::IsFileOrInternalPage`.
  static func showsSiteInfo(url: URL?) -> Bool {
    guard let scheme = url?.scheme?.lowercased() else { return true }
    return !["chrome", "devtools", "view-source", "file"].contains(scheme)
  }

  /// Whether this many tiles need more rows than the grid shows at once.
  static func scrolls(tileCount: Int) -> Bool {
    (tileCount + columns - 1) / columns > maximumVisibleRows
  }

  /// The height of the rows the grid shows at once.
  static var scrollingGridHeight: CGFloat {
    let rows = CGFloat(maximumVisibleRows)
    return rows * tileHeight + (rows - 1) * spacing
  }
}

/// Where the Site Control Center's links go (design D6).
enum SiteControlCenterLink {
  static let webStore = URL(string: "https://chromewebstore.google.com/")!
  static let extensions = URL(string: "chrome://extensions")!
  static let siteSettings = URL(string: "chrome://settings/content")!
}

/// The popover the site-controls button opens: every extension as a tile, and
/// a footer with Chromium's page info and a menu.
struct SiteControlCenter: View {
  let model: BrowserWindowModel
  weak var actions: (any SidebarActions)?
  let dismiss: () -> Void

  @Environment(\.colorScheme) private var colorScheme

  /// A pin badge overhangs its tile by this much, inside the scroll view.
  private static let badgeOverhang: CGFloat = 3

  var body: some View {
    let extensions = SiteControlCenterLogic.ordered(model.extensionActions)
    VStack(alignment: .leading, spacing: 0) {
      Text("Extensions")
        .font(.system(size: 13.5, weight: .bold))
        .frame(height: 17)
        .padding(.bottom, 10)
      grid(extensions)
      Divider().padding(.top, 10).padding(.bottom, 10)
      footer
    }
    .padding(10)
    .frame(width: 236)
  }

  @ViewBuilder
  private func grid(_ extensions: [any ClairExtensionAction]) -> some View {
    if SiteControlCenterLogic.scrolls(tileCount: extensions.count + 1) {
      // The overhang is inside the scroll view, or it would clip the badges.
      ScrollView(.vertical) {
        tiles(extensions).padding(Self.badgeOverhang)
      }
      .frame(height: SiteControlCenterLogic.scrollingGridHeight + 2 * Self.badgeOverhang)
      .padding(-Self.badgeOverhang)
    } else {
      tiles(extensions)
    }
  }

  private func tiles(_ extensions: [any ClairExtensionAction]) -> some View {
    let columns = Array(
      repeating: GridItem(.fixed(SiteControlCenterLogic.tileWidth), spacing: SiteControlCenterLogic.spacing),
      count: SiteControlCenterLogic.columns)
    return LazyVGrid(columns: columns, alignment: .leading, spacing: SiteControlCenterLogic.spacing) {
      ForEach(extensions, id: \.extensionID) { action in
        SiteControlCenterTile(
          action: action,
          contextMenu: { actions?.contextMenu(forExtension: action.extensionID) },
          run: {
            dismiss()
            actions?.runExtension(action.extensionID, pinned: false)
          },
          setPinned: { actions?.setExtension(action.extensionID, pinned: $0) })
      }
      AddExtensionTile {
        dismiss()
        actions?.openInNewTab(SiteControlCenterLink.webStore)
      }
    }
  }

  private var footer: some View {
    HStack(spacing: 0) {
      if SiteControlCenterLogic.showsSiteInfo(url: model.activeTab?.url) {
        SiteInfoPill {
          dismiss()
          actions?.showSiteControls(indicator: [])
        }
      }
      Spacer(minLength: 0)
      // Arc's round button, filled like the tiles.
      IconMenu(help: "More options", cornerRadius: IconButtonSize.regular / 2) {
        Button("Manage Extensions…") { open(SiteControlCenterLink.extensions) }
        Button("Add Extension…") { open(SiteControlCenterLink.webStore) }
        Divider()
        Button("All Site Settings…") { open(SiteControlCenterLink.siteSettings) }
      } label: {
        SymbolGlyph(systemImage: "ellipsis")
          .frame(width: IconButtonSize.regular, height: IconButtonSize.regular)
          .background(tileFill(colorScheme, false), in: .circle)
      }
      .accessibilityIdentifier("clair.siteControlsMore")
    }
    .frame(height: 32)
  }

  private func open(_ url: URL) {
    dismiss()
    actions?.openInNewTab(url)
  }
}

/// An extension in the Site Control Center: a 48×32 pt tile, dimmed while its
/// action is off for the tab, with its pin badge at the bottom-trailing corner
/// (solid when pinned, faint under the pointer otherwise).
struct SiteControlCenterTile: View {
  let action: any ClairExtensionAction
  let contextMenu: () -> NSMenu?
  let run: () -> Void
  let setPinned: (Bool) -> Void

  /// Measured in Arc: 14 pt, from a tile's top-leading corner.
  private static let badgeSize: CGFloat = 14
  private static let badgeOrigin = CGPoint(x: 37, y: 21)
  private static let badgeOverhang: CGFloat = 3

  @State private var isHovered = false
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    ZStack(alignment: .topLeading) {
      Button {
        if action.isEnabled { run() }
      } label: {
        ExtensionIcon(action: action, size: PinnedExtensionsGrid.iconSize)
          .opacity(action.isEnabled ? 1 : 0.4)
          .frame(width: SiteControlCenterLogic.tileWidth, height: SiteControlCenterLogic.tileHeight)
          .background(tileFill(colorScheme, isHovered), in: .rect(cornerRadius: 8, style: .continuous))
          .contentShape(Rectangle())
          .contentShape(.focusEffect, .rect(cornerRadius: 8, style: .continuous))
      }
      .buttonStyle(.plain)
      .overlay(RowClickCatcher(onMiddleClick: {}, menuItems: [], menuProvider: contextMenu))
      .tooltip(action.name)
      .accessibilityLabel(action.name)
      .accessibilityIdentifier("clair.siteControlsExtension")

      if action.isPinned || isHovered {
        pinBadge.offset(x: Self.badgeOrigin.x, y: Self.badgeOrigin.y)
      }
    }
    .frame(width: SiteControlCenterLogic.tileWidth, height: SiteControlCenterLogic.tileHeight, alignment: .topLeading)
    // The badge overhangs the tile, so the hover has to reach it too.
    .padding(.trailing, Self.badgeOverhang)
    .padding(.bottom, Self.badgeOverhang)
    .contentShape(Rectangle())
    .onHover { hovering in withAnimation(sidebarHoverFade) { isHovered = hovering } }
    .padding(.trailing, -Self.badgeOverhang)
    .padding(.bottom, -Self.badgeOverhang)
  }

  private var pinBadge: some View {
    let label = action.isPinned ? "Unpin" : "Pin"
    return Button {
      setPinned(!action.isPinned)
    } label: {
      // Arc's pin leans, head up and to the right.
      Image(systemName: "pin.fill")
        .font(.system(size: 8, weight: .semibold))
        .rotationEffect(.degrees(45))
        .foregroundStyle(action.isPinned ? Color.white : Color.secondary)
        .frame(width: Self.badgeSize, height: Self.badgeSize)
        .background(action.isPinned ? Color.accentColor : Color.primary.opacity(0.12), in: .circle)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .tooltip(label)
    .accessibilityLabel(label)
  }
}

/// The tile that ends the grid, which opens the Chrome Web Store.
struct AddExtensionTile: View {
  let action: () -> Void

  @State private var isHovered = false
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Button(action: action) {
      Image(systemName: "plus")
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(width: SiteControlCenterLogic.tileWidth, height: SiteControlCenterLogic.tileHeight)
        .background(tileFill(colorScheme, isHovered), in: .rect(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .contentShape(.focusEffect, .rect(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .onHover { hovering in withAnimation(sidebarHoverFade) { isHovered = hovering } }
    .tooltip("Add Extension")
    .accessibilityLabel("Add Extension")
    .accessibilityIdentifier("clair.addExtension")
  }
}

/// The footer's pill, which opens Chromium's page info.
struct SiteInfoPill: View {
  let action: () -> Void

  @State private var isHovered = false
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Button(action: action) {
      Text("Site Info")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Color.primary.opacity(0.85))
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(tileFill(colorScheme, isHovered), in: .rect(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .contentShape(.focusEffect, .rect(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .onHover { hovering in withAnimation(sidebarHoverFade) { isHovered = hovering } }
    .accessibilityIdentifier("clair.siteInfo")
  }
}

/// The fill of the popover's tiles and pill, darker under the pointer.
private func tileFill(_ scheme: ColorScheme, _ hovered: Bool) -> Color {
  SidebarFill.field(scheme, hovered: hovered)
}
