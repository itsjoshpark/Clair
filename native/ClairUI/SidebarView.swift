// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import SwiftUI

/// What the sidebar asks the window to do.
@MainActor
protocol SidebarActions: AnyObject {
  // Tabs.
  func activate(tab: TabID)
  func close(tab: TabID)
  func closeTabs(below tab: TabID)
  func duplicate(tab: TabID)
  func setMuted(_ muted: Bool, tab: TabID)
  func copyLink(of tab: TabID)
  func move(tab: TabID, to index: Int)
  func newTab()
  // The top row and the URL field.
  func goBack()
  func goForward()
  func reloadOrStop()
  func toggleSidebar()
  func editURL()
  func copyURL()
  func showSiteControls(indicator: TabIndicators)
  // Extensions and downloads.
  func runExtension(_ extensionID: String, pinned: Bool)
  func setExtension(_ extensionID: String, pinned: Bool)
  func openDownload(_ downloadID: String)
  func showDownloadInFinder(_ downloadID: String)
  func cancelDownload(_ downloadID: String)
  func resumeDownload(_ downloadID: String)
  func keepDownload(_ downloadID: String)
  func discardDownload(_ downloadID: String)
  func downloadsListOpened()
  func openDownloadsPage()
  // Where the controls are, for Chromium's bubbles.
  func controlFramesChanged(_ frames: [AnchorControl: CGRect])
}

/// The sidebar's coordinate space, which is its hosting view's.
let sidebarCoordinateSpace = "clair.sidebar"

/// Records a control's frame for `AnchorResolver`.
struct AnchorFramesKey: PreferenceKey {
  static let defaultValue: [AnchorControl: CGRect] = [:]
  static func reduce(value: inout [AnchorControl: CGRect], nextValue: () -> [AnchorControl: CGRect]) {
    value.merge(nextValue()) { $1 }
  }
}

extension View {
  func anchorFrame(_ control: AnchorControl) -> some View {
    background(
      GeometryReader { proxy in
        Color.clear.preference(
          key: AnchorFramesKey.self, value: [control: proxy.frame(in: .named(sidebarCoordinateSpace))])
      })
  }
}

/// The sidebar (design D12): the top row, the URL field, extensions and
/// downloads, then the "New Tab" row and the tab list.
struct SidebarView: View {
  let model: BrowserWindowModel
  weak var actions: (any SidebarActions)?

  /// The URL field's buttons show while the pointer is anywhere over the
  /// sidebar of the key window (design D18).
  @State private var isHovered = false

  var body: some View {
    // Arc's metrics: the top row at y+8, the URL field at y+46, the list
    // from y+90 with rows the sidebar's width less 8 pt each side.
    VStack(alignment: .leading, spacing: 0) {
      TopRow(model: model, actions: actions)
      URLField(model: model, actions: actions, showsButtons: isHovered && model.isWindowKey)
        .padding(.horizontal, 8)
        .padding(.top, 6)
      if !model.extensionActions.isEmpty || !model.downloads.isEmpty {
        ToolsRow(model: model, actions: actions)
          .padding(.horizontal, 8)
          .padding(.top, 6)
      }
      if model.profileKind == .incognito {
        // Arc's row: 37 pt from 8 pt below the URL field.
        IncognitoBadge()
          .padding(.leading, 14)
          .frame(height: 37)
          .padding(.top, 8)
      }
      TabList(model: model, actions: actions)
        .padding(.top, model.profileKind == .incognito ? 0 : 8)
    }
    .padding(.bottom, 8)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    // The sidebar's empty areas move the window, as in Arc (design D18).
    .background {
      Color.clear
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents(true)
    }
    .onHover { hovering in withAnimation(sidebarHoverFade) { isHovered = hovering } }
    .environment(\.isWindowKey, model.isWindowKey)
    .coordinateSpace(name: sidebarCoordinateSpace)
    .onPreferenceChange(AnchorFramesKey.self) { frames in
      MainActor.assumeIsolated { actions?.controlFramesChanged(frames) }
    }
  }
}

/// Arc's incognito badge, where a normal window shows its Space, as measured:
/// a barely lighter 22 pt capsule, a near-white crossed-out eye 17 pt wide
/// and 6.5 pt in, and "Incognito" in dim grey from 27 pt in.
struct IncognitoBadge: View {
  var body: some View {
    HStack(spacing: 3.5) {
      Image(systemName: "eye.slash")
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(Color.primary.opacity(0.94))
        .frame(width: 17)
      Text("Incognito")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color.primary.opacity(0.4))
    }
    .padding(.leading, 6.5)
    .padding(.trailing, 6)
    .frame(height: 22)
    .background(Color.primary.opacity(0.03), in: .capsule)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Incognito")
  }
}

/// The sidebar's fills, from Arc in Light and Dark Mode (design D18).
enum SidebarFill {
  /// The URL field: a flat fill, no border.
  static func field(_ scheme: ColorScheme, hovered: Bool) -> Color {
    scheme == .dark ? Color.white.opacity(hovered ? 0.24 : 0.18) : Color.black.opacity(hovered ? 0.09 : 0.045)
  }

  /// The active tab's pill, lighter and flat while the window isn't key.
  static func activePill(_ scheme: ColorScheme, isWindowKey: Bool) -> Color {
    scheme == .dark
      ? Color.white.opacity(isWindowKey ? 0.24 : 0.16)
      : Color(nsColor: .controlBackgroundColor).opacity(isWindowKey ? 0.9 : 0.7)
  }

  /// A hovered row or button.
  static func hover(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color.white.opacity(0.09) : Color.primary.opacity(0.06)
  }
}

/// Whether the sidebar's window is key; glyphs dim when it isn't, as in Arc.
extension EnvironmentValues {
  @Entry var isWindowKey = true
}

/// How fast the sidebar's hover backgrounds and buttons fade (design D18).
let sidebarHoverFade = Animation.easeOut(duration: 0.15)

/// A square button in the sidebar's style: Arc's grey glyphs, 32 pt square
/// (28 pt in the compact top row).
struct SidebarButton: View {
  let systemImage: String
  let help: String
  var shortcut: [String] = []
  var isEnabled = true
  var size: CGFloat = 32
  let action: () -> Void

  @State private var isHovered = false
  @Environment(\.isWindowKey) private var isWindowKey

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 16, weight: .medium))
        .frame(width: size, height: size)
        .background(Color.primary.opacity(isHovered && isEnabled ? 0.08 : 0), in: .rect(cornerRadius: 6))
        .animation(sidebarHoverFade, value: isHovered)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(isEnabled && isWindowKey ? .secondary : .tertiary)
    .disabled(!isEnabled)
    .tooltip(help, shortcut: shortcut)
    .accessibilityLabel(help)
    .onHover { isHovered = $0 }
  }
}

/// The top row, as in Arc: room for the window controls, hide-sidebar, then
/// back, forward and reload or stop at the trailing edge. A narrow sidebar
/// gets the compact row: back, forward and a menu with reload and Hide
/// Sidebar.
struct TopRow: View {
  let model: BrowserWindowModel
  weak var actions: (any SidebarActions)?

  @State private var isMoreHovered = false

  /// The trailing margin, and the gap between back, forward and reload.
  static let trailing: CGFloat = 6
  static let gap: CGFloat = 2

  /// Where hide-sidebar starts: after the window controls, or up to 3 pt
  /// closer when the sidebar is only just wide enough, as in Arc.
  static func hideSidebarX(width: CGFloat, controls: WindowControlsMetrics) -> CGFloat {
    min(controls.topRowLeading, width - trailing - 3 * (32 + gap) - 32)
  }

  var body: some View {
    let tab = model.activeTab
    let isLoading = tab?.isLoading == true
    let controls = model.isWindowFullscreen ? WindowControlsMetrics.fullScreen : model.windowControls
    let isCompact = controls.hasCompactTopRow(width: model.sidebar.width)
    let back = SidebarButton(
      systemImage: "arrow.left", help: "Go back", shortcut: ["⌘", "["], isEnabled: tab?.canGoBack ?? false,
      size: isCompact ? 28 : 32
    ) {
      actions?.goBack()
    }
    .accessibilityIdentifier("clair.back")
    let forward = SidebarButton(
      systemImage: "arrow.right", help: "Go forward", shortcut: ["⌘", "]"], isEnabled: tab?.canGoForward ?? false,
      size: isCompact ? 28 : 32
    ) {
      actions?.goForward()
    }
    .accessibilityIdentifier("clair.forward")
    // The row is centred on the window controls (design D3b).
    if isCompact {
      HStack(spacing: 0) {
        Spacer(minLength: 0)
        back
        forward
        Menu {
          Button(isLoading ? "Stop" : "Reload") { actions?.reloadOrStop() }
            .disabled(tab == nil)
          Button("Hide Sidebar") { actions?.toggleSidebar() }
        } label: {
          Image(systemName: "ellipsis")
            .font(.system(size: 16, weight: .medium))
            .frame(width: 28, height: 28)
            .background(Color.primary.opacity(isMoreHovered ? 0.08 : 0), in: .rect(cornerRadius: 6))
            .animation(sidebarHoverFade, value: isMoreHovered)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(model.isWindowKey ? .secondary : .tertiary)
        .onHover { isMoreHovered = $0 }
        .tooltip("More options")
        .accessibilityLabel("More options")
        .accessibilityIdentifier("clair.topRowMenu")
      }
      .padding(.trailing, Self.trailing)
      .frame(height: 28)
      .padding(.top, max(0, controls.centreY - 14))
      .padding(.bottom, 2)
    } else {
      HStack(spacing: 0) {
        // The window controls sit here (design D4).
        Color.clear.frame(width: Self.hideSidebarX(width: model.sidebar.width, controls: controls))
        // Arc's wording: a revealed sidebar's button docks it.
        SidebarButton(
          systemImage: "sidebar.left",
          help: model.sidebar.isHidden && model.sidebar.isRevealed ? "Lock sidebar" : "Hide sidebar",
          shortcut: ["⌘", "S"]
        ) { actions?.toggleSidebar() }
          .accessibilityIdentifier("clair.hideSidebar")
        Spacer(minLength: 0)
        HStack(spacing: Self.gap) {
          back
          forward
          SidebarButton(
            systemImage: isLoading ? "xmark" : "arrow.clockwise",
            help: isLoading ? "Stop loading this page" : "Reload this page",
            shortcut: isLoading ? ["esc"] : ["⌘", "R"], isEnabled: tab != nil
          ) {
            actions?.reloadOrStop()
          }
          .accessibilityIdentifier("clair.reload")
        }
      }
      .padding(.trailing, Self.trailing)
      .frame(height: 32)
      .padding(.top, max(0, controls.centreY - 16))
    }
  }
}

/// The URL field, as in Arc: the host or full URL, or a magnifier and the
/// placeholder on a new tab page; the indicators; and, under the pointer, copy
/// and site-controls buttons at its trailing end. A click opens the command
/// bar on the current URL.
struct URLField: View {
  let model: BrowserWindowModel
  weak var actions: (any SidebarActions)?
  /// Whether the copy and site-controls buttons show: while the pointer is
  /// over the key window's sidebar.
  var showsButtons = false

  @State private var isHovered = false
  @Environment(\.colorScheme) private var colorScheme

  static let height: CGFloat = 36
  static let buttonSize: CGFloat = 30

  static let indicatorSymbols: [(TabIndicators, String, String)] = [
    (.camera, "video.fill", "Camera"),
    (.microphone, "mic.fill", "Microphone"),
    (.location, "location.fill", "Location"),
    (.screenCapture, "rectangle.inset.filled.on.rectangle", "Screen sharing"),
  ]

  var body: some View {
    let tab = model.activeTab
    let display = URLDisplay.text(for: tab)
    let hasSiteControls = tab != nil && tab?.isNewTabPage != true
    HStack(spacing: 0) {
      if display == nil {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.secondary)
          .frame(width: 24, height: 24)
          .padding(.leading, 6)
          .padding(.trailing, 3)
          .frame(maxHeight: .infinity)
          .contentShape(Rectangle())
          .onTapGesture { actions?.editURL() }
      }
      Text(display ?? URLDisplay.placeholder)
        .font(.system(size: 13))
        .lineLimit(1)
        .truncationMode(.tail)
        .foregroundStyle(display == nil ? Color.secondary : Color.primary.opacity(0.85))
        .padding(.leading, display == nil ? 0 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { actions?.editURL() }
        .accessibilityElement()
        .accessibilityLabel(display ?? URLDisplay.placeholder)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("clair.urlField")

      ForEach(Self.indicatorSymbols, id: \.0.rawValue) { indicator, symbol, label in
        if tab?.indicators.contains(indicator) == true {
          Button {
            actions?.showSiteControls(indicator: indicator)
          } label: {
            Image(systemName: symbol)
              .font(.system(size: 11))
              .foregroundStyle(Color.red)
              .frame(width: 22, height: Self.buttonSize)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .tooltip(label)
          .accessibilityLabel(label)
          .anchorFrame(.indicator(indicator.rawValue))
        }
      }

      if showsButtons, display != nil {
        URLFieldButton(systemImage: "link", help: "Copy URL", shortcut: ["⇧", "⌘", "C"]) { actions?.copyURL() }
          .accessibilityIdentifier("clair.copyURL")
          .padding(.trailing, -2)
          .transition(.opacity)
      }
      if showsButtons, hasSiteControls {
        URLFieldButton(systemImage: "slider.horizontal.3", help: "Site Control Center") {
          actions?.showSiteControls(indicator: [])
        }
        .accessibilityIdentifier("clair.siteControls")
        .transition(.opacity)
      }
    }
    .padding(.trailing, showsButtons || tab?.indicators.isEmpty == false ? 4 : 12)
    .frame(height: Self.height)
    // Chromium's page info attaches where the site-controls button shows on
    // hover, whether or not it shows now.
    .overlay(alignment: .trailing) {
      Color.clear
        .frame(width: Self.buttonSize, height: Self.buttonSize)
        .padding(.trailing, 4)
        .anchorFrame(.siteControls)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    // Arc's flat fill, darker under the pointer (design D18).
    .background(SidebarFill.field(colorScheme, hovered: isHovered), in: .rect(cornerRadius: 10, style: .continuous))
    .onHover { hovering in withAnimation(sidebarHoverFade) { isHovered = hovering } }
    .contextMenu {
      if display != nil {
        Button("Copy URL") { actions?.copyURL() }
      }
    }
  }
}

/// A button at the URL field's trailing end.
struct URLFieldButton: View {
  let systemImage: String
  let help: String
  var shortcut: [String] = []
  let action: () -> Void

  @State private var isHovered = false
  @Environment(\.isWindowKey) private var isWindowKey

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 13, weight: .medium))
        .frame(width: URLField.buttonSize, height: URLField.buttonSize)
        .background(Color.primary.opacity(isHovered ? 0.08 : 0), in: .rect(cornerRadius: 7))
        .animation(sidebarHoverFade, value: isHovered)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(isWindowKey ? .secondary : .tertiary)
    .tooltip(help, shortcut: shortcut)
    .accessibilityLabel(help)
    .onHover { isHovered = $0 }
  }
}

/// Pinned extension actions, the extensions button and the downloads button.
struct ToolsRow: View {
  let model: BrowserWindowModel
  weak var actions: (any SidebarActions)?

  @State private var showsExtensions = false
  @State private var showsDownloads = false

  var body: some View {
    HStack(spacing: 2) {
      ForEach(model.pinnedExtensionActions, id: \.extensionID) { action in
        ExtensionButton(action: action) { actions?.runExtension(action.extensionID, pinned: true) }
          .anchorFrame(.extensionAction(action.extensionID))
      }
      if !model.extensionActions.isEmpty {
        SidebarButton(systemImage: "puzzlepiece.extension", help: "Extensions") { showsExtensions.toggle() }
          .accessibilityIdentifier("clair.extensions")
          .anchorFrame(.extensionsButton)
          .popover(isPresented: $showsExtensions, arrowEdge: .trailing) {
            ExtensionsList(model: model, actions: actions) { showsExtensions = false }
          }
      }
      Spacer(minLength: 0)
      if !model.downloads.isEmpty {
        DownloadsButton(progress: model.downloadProgress, hasUnseen: model.hasUnseenDownloads) {
          showsDownloads.toggle()
          if showsDownloads { actions?.downloadsListOpened() }
        }
        .anchorFrame(.downloads)
        .popover(isPresented: $showsDownloads, arrowEdge: .trailing) {
          DownloadsList(model: model, actions: actions)
        }
      }
    }
    .frame(height: 30)
  }
}

struct ExtensionIcon: View {
  let action: any ClairExtensionAction

  var body: some View {
    if let icon = action.icon {
      Image(nsImage: icon).resizable().interpolation(.high).frame(width: 16, height: 16)
    } else {
      Image(systemName: "puzzlepiece").frame(width: 16, height: 16)
    }
  }
}

struct ExtensionButton: View {
  let action: any ClairExtensionAction
  let run: () -> Void

  var body: some View {
    Button(action: run) {
      ExtensionIcon(action: action)
        .frame(width: 28, height: 28)
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
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .tooltip(action.name)
    .accessibilityLabel(action.name)
    .accessibilityValue(action.badgeText)
    .accessibilityIdentifier("clair.extensionAction")
  }
}

/// The extensions button's list: every extension with an action.
struct ExtensionsList: View {
  let model: BrowserWindowModel
  weak var actions: (any SidebarActions)?
  let dismiss: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(model.extensionActions, id: \.extensionID) { action in
        HStack {
          Button {
            dismiss()
            actions?.runExtension(action.extensionID, pinned: false)
          } label: {
            HStack {
              ExtensionIcon(action: action)
              Text(action.name).lineLimit(1)
              Spacer()
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          Button {
            actions?.setExtension(action.extensionID, pinned: !action.isPinned)
          } label: {
            Image(systemName: action.isPinned ? "pin.fill" : "pin")
          }
          .buttonStyle(.plain)
          .tooltip(action.isPinned ? "Unpin" : "Pin")
          .accessibilityLabel(action.isPinned ? "Unpin" : "Pin")
        }
        .padding(.vertical, 4)
      }
    }
    .padding(10)
    .frame(width: 260)
  }
}

struct DownloadsButton: View {
  let progress: Double?
  let hasUnseen: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      ZStack {
        if let progress {
          Circle().stroke(Color.primary.opacity(0.15), lineWidth: 2)
          Circle().trim(from: 0, to: progress).stroke(Color.accentColor, lineWidth: 2).rotationEffect(.degrees(-90))
        }
        Image(systemName: "arrow.down")
          .font(.system(size: 11, weight: .semibold))
      }
      .frame(width: 20, height: 20)
      .frame(width: 28, height: 28)
      .overlay(alignment: .topTrailing) {
        if hasUnseen {
          Circle().fill(Color.accentColor).frame(width: 7, height: 7)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .tooltip("Downloads")
    .accessibilityLabel("Downloads")
    .accessibilityValue(progress.map { "\(Int($0 * 100))%" } ?? (hasUnseen ? "New" : ""))
    .accessibilityIdentifier("clair.downloads")
  }
}

/// Recent downloads, with their actions.
struct DownloadsList: View {
  let model: BrowserWindowModel
  weak var actions: (any SidebarActions)?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(model.downloads.prefix(8), id: \.downloadID) { download in
        DownloadRow(download: download, actions: actions)
      }
      Divider()
      Button("Show All Downloads") { actions?.openDownloadsPage() }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }
    .padding(12)
    .frame(width: 300)
  }
}

struct DownloadRow: View {
  let download: any ClairDownload
  weak var actions: (any SidebarActions)?

  var status: String {
    switch download.state {
    case .inProgress:
      if download.totalBytes > 0 {
        let format = ByteCountFormatter()
        return "\(format.string(fromByteCount: download.receivedBytes)) of \(format.string(fromByteCount: download.totalBytes))"
      }
      return "Downloading…"
    case .paused: return "Paused"
    case .complete: return ByteCountFormatter.string(fromByteCount: download.totalBytes, countStyle: .file)
    case .cancelled: return "Cancelled"
    case .interrupted: return "Failed"
    @unknown default: return ""
    }
  }

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: download.needsDecision ? "exclamationmark.triangle.fill" : "doc")
        .foregroundStyle(download.needsDecision ? Color.orange : Color.secondary)
      VStack(alignment: .leading, spacing: 2) {
        Text(download.fileName).lineLimit(1).truncationMode(.middle)
        Text(download.warningText ?? status).font(.caption).foregroundStyle(.secondary)
        if download.state == .inProgress, download.totalBytes > 0 {
          ProgressView(value: Double(download.receivedBytes), total: Double(download.totalBytes))
        }
      }
      Spacer(minLength: 0)
      if download.needsDecision {
        Button("Keep") { actions?.keepDownload(download.downloadID) }
        Button("Delete") { actions?.discardDownload(download.downloadID) }
      } else {
        switch download.state {
        case .inProgress, .paused:
          Button { actions?.cancelDownload(download.downloadID) } label: { Image(systemName: "xmark.circle") }
            .buttonStyle(.plain).tooltip("Cancel")
        case .interrupted where download.canResume:
          Button { actions?.resumeDownload(download.downloadID) } label: { Image(systemName: "arrow.clockwise") }
            .buttonStyle(.plain).tooltip("Retry")
        case .complete:
          Button { actions?.showDownloadInFinder(download.downloadID) } label: { Image(systemName: "magnifyingglass") }
            .buttonStyle(.plain).tooltip("Show in Finder")
        default:
          EmptyView()
        }
      }
    }
    .contentShape(Rectangle())
    .onTapGesture {
      if download.state == .complete {
        actions?.openDownload(download.downloadID)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("clair.downloadRow")
  }
}

/// The "New Tab" row and the tab list, in Chromium's tab order.
struct TabList: View {
  let model: BrowserWindowModel
  weak var actions: (any SidebarActions)?

  /// Room beyond the rows, so a list that fits never scrolls.
  static let slack: CGFloat = 8

  var body: some View {
    List {
      NewTabRow(isHighlighted: model.commandBar?.mode == .newTab) { actions?.newTab() }
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: -1))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .moveDisabled(true)
      ForEach(model.tabs, id: \.tabID) { tab in
        TabRow(
          tab: tab, isActive: tab.tabID == model.activeTabID, isWindowKey: model.isWindowKey,
          isIncognito: model.profileKind == .incognito, actions: actions)
          .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: -1))
          .listRowSeparator(.hidden)
          .listRowBackground(Color.clear)
      }
      .onMove { source, destination in
        // The offsets count the tabs only, not the "New Tab" row.
        guard let from = source.first,
          let target = TabListLogic.moveTarget(from: from, to: destination, count: model.tabs.count)
        else { return }
        actions?.move(tab: model.tabs[from].tabID, to: target)
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .environment(\.defaultMinListRowHeight, 1)
    // No taller than its rows, so the space below the last tab is the
    // sidebar's, which moves the window (design D18); the list scrolls once
    // the rows don't fit.
    .frame(maxHeight: TabRow.pitch * CGFloat(model.tabs.count + 1) + Self.slack)
    .accessibilityIdentifier("clair.tabList")
  }
}

struct NewTabRow: View {
  let isHighlighted: Bool
  let action: () -> Void

  @State private var isHovered = false
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Button(action: action) {
      HStack(spacing: TabRow.titleGap) {
        Image(systemName: "plus")
          .font(.system(size: 15, weight: .regular))
          .frame(width: TabRow.iconSize, height: TabRow.iconSize)
        Text("New Tab").font(TabRow.titleFont)
        Spacer(minLength: 0)
      }
      .foregroundStyle(.secondary)
      .padding(.horizontal, TabRow.horizontalPadding)
      .frame(height: TabRow.pillHeight)
      .background(
        isHighlighted ? Color.accentColor.opacity(0.18) : (isHovered ? SidebarFill.hover(colorScheme) : .clear),
        in: .rect(cornerRadius: TabRow.cornerRadius, style: .continuous)
      )
      .padding(.top, TabRow.pillInset)
      .padding(.bottom, TabRow.pillInset + TabRow.spacing)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .accessibilityIdentifier("clair.newTabRow")
  }
}

/// One tab: favicon, title, the speaker while it plays or is muted, and the
/// close button on hover.
struct TabRow: View {
  let tab: any ClairTab
  let isActive: Bool
  let isWindowKey: Bool
  var isIncognito = false
  weak var actions: (any SidebarActions)?

  @State private var isHovered = false
  @Environment(\.colorScheme) private var colorScheme

  /// How long the pointer rests on a row before its full title shows.
  static let titleTooltipDelay: Duration = .seconds(3)

  // Arc's metrics: 40 pt rows on a 41 pt pitch, an 18 pt favicon frame 9 pt
  // into the pill with the favicon drawn at 16 pt, the title 8 pt after it,
  // and a 36 pt pill. The close button is 26 pt, 5 pt from the pill's end.
  static let pillHeight: CGFloat = 36
  static let pillInset: CGFloat = 2
  static let spacing: CGFloat = 1
  static let pitch = pillHeight + 2 * pillInset + spacing
  static let horizontalPadding: CGFloat = 9
  static let iconSize: CGFloat = 18
  static let faviconSize: CGFloat = 16
  static let closeSize: CGFloat = 26
  static let closeTrailing: CGFloat = 5
  static let titleGap: CGFloat = 8
  static let cornerRadius: CGFloat = 10
  static let titleFont = Font.system(size: 14)

  var body: some View {
    HStack(spacing: Self.titleGap) {
      Group {
        if tab.isLoading && tab.favicon == nil {
          ProgressView().controlSize(.small)
        } else if isIncognito && tab.isNewTabPage {
          // In place of Chromium's incognito goggles, as in the header.
          Image(systemName: "eye.slash").foregroundStyle(.secondary)
        } else if let favicon = tab.favicon {
          Image(nsImage: favicon).resizable().interpolation(.high)
            .frame(width: Self.faviconSize, height: Self.faviconSize)
        } else {
          Image(systemName: "globe").foregroundStyle(.secondary)
        }
      }
      .frame(width: Self.iconSize, height: Self.iconSize)
      Text(tab.title).font(Self.titleFont).lineLimit(1)
      Spacer(minLength: 0)
      if tab.isAudible || tab.isMuted {
        Button {
          actions?.setMuted(!tab.isMuted, tab: tab.tabID)
        } label: {
          Image(systemName: tab.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            .font(.system(size: 11))
        }
        .buttonStyle(.plain)
        .tooltip(tab.isMuted ? "Unmute tab" : "Mute tab")
        .accessibilityIdentifier("clair.tabSpeaker")
      }
      if isHovered {
        TabCloseButton { actions?.close(tab: tab.tabID) }
          .padding(.trailing, Self.closeTrailing - Self.horizontalPadding)
      }
    }
    .padding(.horizontal, Self.horizontalPadding)
    .frame(height: Self.pillHeight)
    .background {
      if isActive {
        // Lighter and flat while the window isn't key, as in Arc.
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
          .fill(SidebarFill.activePill(colorScheme, isWindowKey: isWindowKey))
          .shadow(color: .black.opacity(isWindowKey ? 0.12 : 0), radius: 2, y: 1)
      } else if isHovered {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous).fill(SidebarFill.hover(colorScheme))
      }
    }
    .padding(.top, Self.pillInset)
    .padding(.bottom, Self.pillInset + Self.spacing)
    .contentShape(Rectangle())
    .onTapGesture { actions?.activate(tab: tab.tabID) }
    // AppKit's context menu rather than SwiftUI's, which makes the list draw
    // a selection ring around the row (design D18).
    .overlay(RowClickCatcher(onMiddleClick: { actions?.close(tab: tab.tabID) }, menuItems: menuItems))
    .onHover { hovering in withAnimation(sidebarHoverFade) { isHovered = hovering } }
    // The full title, once the pointer has rested on the row (design D18).
    .tooltip(tab.title.isEmpty ? nil : tab.title, delay: Self.titleTooltipDelay)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(tab.title)
    .accessibilityIdentifier("clair.tabRow")
    .accessibilityAddTraits(isActive ? .isSelected : [])
  }
}

/// The tab's close button, as in Arc: 26 pt with a 10 pt glyph and its own
/// hover background.
struct TabCloseButton: View {
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      Image(systemName: "xmark")
        .font(.system(size: 12, weight: .bold))
        .frame(width: TabRow.closeSize, height: TabRow.closeSize)
        .background(Color.primary.opacity(isHovered ? 0.08 : 0), in: .rect(cornerRadius: 6))
        .animation(sidebarHoverFade, value: isHovered)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(.secondary)
    .tooltip("Close tab", shortcut: ["⌘", "W"])
    .accessibilityIdentifier("clair.tabClose")
    .onHover { isHovered = $0 }
  }
}

extension TabRow {
  /// The row's context menu.
  var menuItems: [RowClickCatcher.Item] {
    let tabID = tab.tabID, isMuted = tab.isMuted
    return [
      .action("Copy Link") { actions?.copyLink(of: tabID) },
      .action("Duplicate") { actions?.duplicate(tab: tabID) },
      .action(isMuted ? "Unmute" : "Mute") { actions?.setMuted(!isMuted, tab: tabID) },
      .separator,
      .action("Close Tab") { actions?.close(tab: tabID) },
      .action("Close Tabs Below") { actions?.closeTabs(below: tabID) },
    ]
  }
}

/// Catches middle clicks and context-menu clicks (a right click or a
/// Control-click), and lets every other click through. Opening the menu here
/// keeps the press from the list, which would otherwise ring the row.
struct RowClickCatcher: NSViewRepresentable {
  enum Item {
    case action(String, () -> Void)
    case separator
  }

  let onMiddleClick: () -> Void
  let menuItems: [Item]

  func makeNSView(context: Context) -> CatcherView {
    let view = CatcherView()
    updateNSView(view, context: context)
    return view
  }

  func updateNSView(_ view: CatcherView, context: Context) {
    view.onMiddleClick = onMiddleClick
    view.menuItems = menuItems
  }

  final class CatcherView: NSView {
    var onMiddleClick: (() -> Void)?
    var menuItems: [Item] = []

    override func hitTest(_ point: NSPoint) -> NSView? {
      guard let event = NSApp.currentEvent else { return nil }
      switch event.type {
      case .otherMouseDown, .otherMouseUp, .rightMouseDown, .rightMouseUp:
        return super.hitTest(point)
      case .leftMouseDown where event.modifierFlags.contains(.control):
        return super.hitTest(point)
      default:
        return nil
      }
    }

    override func otherMouseUp(with event: NSEvent) {
      if event.buttonNumber == 2 {
        onMiddleClick?()
      }
    }

    override func mouseDown(with event: NSEvent) {
      // Only a Control-click gets here.
      NSMenu.popUpContextMenu(makeMenu(), with: event, for: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
      makeMenu()
    }

    private func makeMenu() -> NSMenu {
      let menu = NSMenu()
      for item in menuItems {
        switch item {
        case .separator:
          menu.addItem(.separator())
        case .action(let title, let action):
          let menuItem = NSMenuItem(title: title, action: #selector(runItem(_:)), keyEquivalent: "")
          menuItem.target = self
          menuItem.representedObject = ItemAction(run: action)
          menu.addItem(menuItem)
        }
      }
      return menu
    }

    @objc private func runItem(_ sender: NSMenuItem) {
      (sender.representedObject as? ItemAction)?.run()
    }
  }

  /// A menu item's action, boxed for `representedObject`.
  final class ItemAction: NSObject {
    let run: () -> Void

    init(run: @escaping () -> Void) {
      self.run = run
    }
  }
}
