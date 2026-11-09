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
  /// Starts the back or forward history menu, or nil when the tab can't go
  /// that way (arc-navigation-feedback design D3).
  func historyMenu(_ direction: HistoryDirection) -> HistoryMenuBuilder?
  func reloadOrStop()
  func reloadButtonHovered(_ hovering: Bool)
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
  /// The tab list's height, as laid out.
  @State private var tabListHeight: CGFloat = 0
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    // Arc's metrics: the top row at y+8, the URL field at y+46, the list
    // from y+90 with rows the sidebar's width less 8 pt each side.
    VStack(alignment: .leading, spacing: 0) {
      TopRow(model: model, actions: actions)
      URLField(model: model, actions: actions, showsButtons: isHovered && model.isWindowKey)
        .padding(.horizontal, 8)
        .padding(.top, 6)
      if !model.extensionActions.isEmpty {
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
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tabListHeight = $0 }
        .padding(.top, tabListTopPadding)
        // Ahead of the spacer, which would otherwise take half the room.
        .layoutPriority(1)
      // The footer stays at the bottom however short the list is; the space
      // between moves the window like the rest of the sidebar.
      Spacer(minLength: 0)
      SidebarFooter(model: model, actions: actions)
        .overlay(alignment: .top) {
          // Arc's line between a list that scrolls and the footer: 1 pt
          // across the sidebar, about 4% black in Light Mode and 8% white
          // in Dark Mode, as measured.
          if TabList.overflows(height: tabListHeight, tabCount: model.tabs.count) {
            Rectangle().fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04)).frame(height: 1)
          }
        }
    }
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

  /// 8 pt under the URL field. Under the tools row, whose buttons have no
  /// visible edge, 4 pt, so the "New Tab" pill sits 6 pt below the row as the
  /// row sits 6 pt below the URL field.
  private var tabListTopPadding: CGFloat {
    if model.profileKind == .incognito { return 0 }
    return model.extensionActions.isEmpty ? 8 : 4
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
    scheme == .dark ? Color.white.opacity(hovered ? 0.2 : 0.15) : Color.black.opacity(hovered ? 0.09 : 0.045)
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

/// The top row, as in Arc: room for the window controls, hide-sidebar, then
/// back, forward and reload or stop at the trailing edge. A narrow sidebar
/// gets the compact row: back, forward and a menu with reload and Hide
/// Sidebar.
struct TopRow: View {
  let model: BrowserWindowModel
  weak var actions: (any SidebarActions)?

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
    // The button's own state, which holds stop under the pointer (design D2);
    // the tab rows' spinners read the tab's `isLoading`.
    let reloadStop = model.reloadStop.mode
    let isLoading = reloadStop.visible == .stop
    let controls = model.isWindowFullscreen ? WindowControlsMetrics.fullScreen : model.windowControls
    let isCompact = controls.hasCompactTopRow(width: model.sidebar.width)
    let size = isCompact ? IconButtonSize.small : IconButtonSize.regular
    let back = IconButton(
      systemImage: "arrow.left", help: "Go back", shortcut: ["⌘", "["], isEnabled: tab?.canGoBack ?? false, size: size
    ) {
      actions?.goBack()
    }
    .overlay(
      HistoryButtonCatcher(
        isEnabled: tab?.canGoBack ?? false, makeMenu: { actions?.historyMenu(.back) }))
    .accessibilityIdentifier("clair.back")
    let forward = IconButton(
      systemImage: "arrow.right", help: "Go forward", shortcut: ["⌘", "]"], isEnabled: tab?.canGoForward ?? false,
      size: size
    ) {
      actions?.goForward()
    }
    .overlay(
      HistoryButtonCatcher(
        isEnabled: tab?.canGoForward ?? false, makeMenu: { actions?.historyMenu(.forward) }))
    .accessibilityIdentifier("clair.forward")
    // The row is centred on the window controls (design D3b).
    if isCompact {
      HStack(spacing: 0) {
        Spacer(minLength: 0)
        back
        forward
        IconMenu(help: "More options", size: IconButtonSize.small) {
          Group {
            if isLoading {
              Button("Stop") { actions?.reloadOrStop() }.keyboardShortcut(.escape, modifiers: [])
            } else {
              Button("Reload") { actions?.reloadOrStop() }.keyboardShortcut("r", modifiers: .command)
            }
          }
          .disabled(tab == nil || !reloadStop.isEnabled)
          Button("Hide Sidebar") { actions?.toggleSidebar() }.keyboardShortcut("s", modifiers: .command)
        } label: {
          SymbolGlyph(systemImage: "ellipsis")
        }
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
        IconButton(
          systemImage: "sidebar.left",
          help: model.sidebar.isHidden && model.sidebar.isRevealed ? "Lock sidebar" : "Hide sidebar",
          shortcut: ["⌘", "S"]
        ) { actions?.toggleSidebar() }
          .accessibilityIdentifier("clair.hideSidebar")
        Spacer(minLength: 0)
        HStack(spacing: Self.gap) {
          back
          forward
          IconButton(
            systemImage: isLoading ? "xmark" : "arrow.clockwise",
            help: isLoading ? "Stop loading this page" : "Reload this page",
            shortcut: isLoading ? ["esc"] : ["⌘", "R"], isEnabled: tab != nil && reloadStop.isEnabled
          ) {
            actions?.reloadOrStop()
          }
          .onHover { actions?.reloadButtonHovered($0) }
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
  /// Arc's URL-field buttons: 28 pt, side by side.
  static let buttonSize = IconButtonSize.small

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
    .padding(.trailing, showsButtons || tab?.indicators.isEmpty == false ? 5 : 12)
    .frame(height: Self.height)
    // Chromium's page info attaches where the site-controls button shows on
    // hover, whether or not it shows now.
    .overlay(alignment: .trailing) {
      Color.clear
        .frame(width: Self.buttonSize, height: Self.buttonSize)
        .padding(.trailing, 5)
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

  var body: some View {
    IconButton(
      systemImage: systemImage, help: help, shortcut: shortcut, size: URLField.buttonSize, cornerRadius: 7,
      glyphSize: 13, action: action)
  }
}

/// Pinned extension actions and the extensions button, shown while there are
/// extensions with an action.
struct ToolsRow: View {
  let model: BrowserWindowModel
  weak var actions: (any SidebarActions)?

  @State private var showsExtensions = false

  var body: some View {
    HStack(spacing: 2) {
      ForEach(model.pinnedExtensionActions, id: \.extensionID) { action in
        ExtensionButton(action: action) { actions?.runExtension(action.extensionID, pinned: true) }
          .anchorFrame(.extensionAction(action.extensionID))
      }
      IconButton(systemImage: "puzzlepiece.extension", help: "Extensions") {
        showsExtensions.toggle()
      }
      .accessibilityIdentifier("clair.extensions")
      .anchorFrame(.extensionsButton)
      .popover(isPresented: $showsExtensions, arrowEdge: .trailing) {
        ExtensionsList(model: model, actions: actions) { showsExtensions = false }
      }
      Spacer(minLength: 0)
    }
    .frame(height: IconButtonSize.regular)
  }
}

/// The sidebar's footer, as in Arc: a 50 pt band at the bottom of the sidebar,
/// with the downloads button always where Arc has its library button and the
/// plus menu at the other end, each 8 pt in from the side and 9 pt from the
/// bottom.
struct SidebarFooter: View {
  let model: BrowserWindowModel
  weak var actions: (any SidebarActions)?

  static let height: CGFloat = 50
  /// The footer's glyphs: medium weight like Arc's footer symbols (17 pt
  /// medium), 18 pt, so a circled symbol is 18 pt across. The grey is the
  /// buttons' `.secondary`, which matches Arc's.
  static let glyphSize: CGFloat = 18
  static let glyphWeight: Font.Weight = .medium

  @State private var showsDownloads = false

  var body: some View {
    HStack(spacing: 0) {
      DownloadsButton(progress: model.downloadProgress, hasUnseen: model.hasUnseenDownloads) {
        showsDownloads.toggle()
        if showsDownloads { actions?.downloadsListOpened() }
      }
      .anchorFrame(.downloads)
      .popover(isPresented: $showsDownloads, arrowEdge: .trailing) {
        DownloadsList(model: model, actions: actions)
      }
      Spacer(minLength: 0)
      // Arc's plus offers new Spaces and folders; Clair has only tabs so far.
      IconMenu(help: "New") {
        Button("New Tab") { actions?.newTab() }.keyboardShortcut("t", modifiers: .command)
      } label: {
        SymbolGlyph(systemImage: "plus", size: Self.glyphSize, weight: Self.glyphWeight)
      }
      .accessibilityIdentifier("clair.footerNew")
    }
    .padding(.horizontal, 8)
    .frame(height: Self.height)
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
    IconButton(help: action.name, size: IconButtonSize.regular, action: run) {
      ExtensionIcon(action: action)
        .frame(width: IconButtonSize.regular, height: IconButtonSize.regular)
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
    }
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

/// The downloads button, 32 pt as in Arc's footer, with the running
/// downloads' progress on the glyph's circle and a dot for unseen downloads.
struct DownloadsButton: View {
  let progress: Double?
  let hasUnseen: Bool
  let action: () -> Void

  @Environment(\.isWindowKey) private var isWindowKey

  var body: some View {
    IconButton(help: "Downloads", action: action) {
      glyph
        .frame(width: IconButtonSize.regular, height: IconButtonSize.regular)
      .overlay(alignment: .topTrailing) {
        if hasUnseen {
          Circle().fill(Color.accentColor).frame(width: 7, height: 7).padding(2)
        }
      }
    }
    .accessibilityValue(progress.map { "\(Int($0 * 100))%" } ?? (hasUnseen ? "New" : ""))
    .accessibilityIdentifier("clair.downloads")
  }

  @ViewBuilder private var glyph: some View {
    if let progress {
      if #available(macOS 26, *) {
        // The symbol draws its own ring up to the progress (Variable Draw):
        // the arrow in the button's grey, the ring in the accent colour.
        Image(systemName: "arrow.down.circle", variableValue: progress)
          .symbolRenderingMode(.palette)
          .symbolVariableValueMode(.draw)
          .font(.system(size: SidebarFooter.glyphSize, weight: SidebarFooter.glyphWeight))
          .foregroundStyle(arrowColor, Color.accentColor)
      } else {
        // Variable Draw needs macOS 26, and the symbol has no variable
        // layers before it, so macOS 15 draws the progress over the ring:
        // 18 pt across with a stroke of about 1.75 pt.
        footerGlyph
          .overlay {
            Circle()
              .trim(from: 0, to: progress)
              .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
              .rotationEffect(.degrees(-90))
              .frame(width: SidebarFooter.glyphSize - 1.75, height: SidebarFooter.glyphSize - 1.75)
          }
      }
    } else {
      footerGlyph
    }
  }

  private var footerGlyph: SymbolGlyph {
    SymbolGlyph(systemImage: "arrow.down.circle", size: SidebarFooter.glyphSize, weight: SidebarFooter.glyphWeight)
  }

  /// The palette replaces the button's grey, so the arrow dims itself.
  private var arrowColor: Color {
    Color(nsColor: isWindowKey ? .secondaryLabelColor : .tertiaryLabelColor)
  }
}

/// Recent downloads, with their actions.
struct DownloadsList: View {
  let model: BrowserWindowModel
  weak var actions: (any SidebarActions)?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if model.downloads.isEmpty {
        Text("No recent downloads")
          .foregroundStyle(.secondary)
      } else {
        ForEach(model.downloads.prefix(8), id: \.downloadID) { download in
          DownloadRow(download: download, actions: actions)
        }
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

  /// The height of the "New Tab" row and the tabs, which the list grows to.
  static func contentHeight(tabCount: Int) -> CGFloat {
    TabRow.pitch * CGFloat(tabCount + 1) + slack
  }

  /// Whether a list this tall is shorter than its rows, so it scrolls. It
  /// follows the number of tabs as well as the height: a list capped at the
  /// room left keeps its height while tabs come and go.
  static func overflows(height: CGFloat, tabCount: Int) -> Bool {
    height > 0 && height + 0.5 < contentHeight(tabCount: tabCount)
  }

  var body: some View {
    List {
      NewTabRow(isHighlighted: model.commandBar?.mode == .newTab) { actions?.newTab() }
        // From inside a row, where it can reach the list's scroll view.
        .background(ScrollerControlSize(size: .small))
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
    .frame(maxHeight: Self.contentHeight(tabCount: model.tabs.count))
    .accessibilityIdentifier("clair.tabList")
  }
}

/// Sets the scrollers of the scroll view around it to a control size, for a
/// thinner scroll bar: SwiftUI has no way to, but a `List` scrolls in an
/// AppKit scroll view.
struct ScrollerControlSize: NSViewRepresentable {
  let size: NSControl.ControlSize

  func makeNSView(context: Context) -> SizingView {
    let view = SizingView()
    view.size = size
    return view
  }

  func updateNSView(_ view: SizingView, context: Context) {
    view.size = size
    view.apply()
  }

  final class SizingView: NSView {
    var size: NSControl.ControlSize = .regular

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      apply()
    }

    // Clicks go to the row.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func apply() {
      enclosingScrollView?.verticalScroller?.controlSize = size
    }
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
          .font(.system(size: 15, weight: .medium))
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
  @State private var showsSpeaker = false
  @Environment(\.colorScheme) private var colorScheme

  /// How long the pointer rests on a row before its full title shows.
  static let titleTooltipDelay: Duration = .seconds(2)

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
  static let closeSize = IconButtonSize.tab
  static let speakerLeading: CGFloat = 4.5
  static let speakerTrailing: CGFloat = 5.5
  static let closeTrailing: CGFloat = 5
  static let titleGap: CGFloat = 8
  static let cornerRadius: CGFloat = 10
  static let titleFont = Font.system(size: 14)

  var body: some View {
    HStack(spacing: Self.titleGap) {
      // The favicon, the speaker and the title, with their own gaps: the
      // speaker sits between the other two, as in Arc, and collapses to
      // nothing while there's no sound.
      HStack(spacing: 0) {
        Group {
          if tab.isLoading && tab.favicon == nil {
            ProgressView().controlSize(.small)
          } else if isIncognito && tab.isNewTabPage {
            // Chromium gives the incognito new tab its goggles as a favicon. Show the
            // crossed-out eye instead, near-white like the header's badge, as in Arc.
            Image(systemName: "eye.slash").foregroundStyle(Color.primary.opacity(0.94))
          } else if let favicon = tab.favicon {
            Image(nsImage: favicon).resizable().interpolation(.high)
              .frame(width: Self.faviconSize, height: Self.faviconSize)
          } else {
            Image(systemName: "globe").foregroundStyle(.secondary)
          }
        }
        .frame(width: Self.iconSize, height: Self.iconSize)
        .accessibilityElement()
        .accessibilityIdentifier("clair.tabFavicon")
        // The speaker's glyph keeps the same visible gap from the favicon and
        // from the title as the title has from the favicon without it (10 pt
        // drawn to drawn): its 26 pt button pads the glyph by about 4 pt, and
        // the drawn favicon sits 1 pt inside its frame. It stays in the row,
        // collapsed, so it grows and fades in and out; the list's rows don't
        // animate an inserted view.
        TabSpeakerButton(isMuted: tab.isMuted) { muted in actions?.setMuted(muted, tab: tab.tabID) }
          .scaleEffect(showsSpeaker ? 1 : 0.5)
          .opacity(showsSpeaker ? 1 : 0)
          .frame(width: showsSpeaker ? TabRow.closeSize : 0)
          .padding(.leading, showsSpeaker ? Self.speakerLeading : 0)
          .padding(.trailing, showsSpeaker ? Self.speakerTrailing : Self.titleGap)
          .allowsHitTesting(showsSpeaker)
          .accessibilityHidden(!showsSpeaker)
        Text(tab.title).font(Self.titleFont).lineLimit(1)
          .accessibilityIdentifier("clair.tabTitle")
      }
      Spacer(minLength: 0)
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
    // The hover background and the close button come and go at once.
    .onHover { isHovered = $0 }
    // The full title, once the pointer has rested on the row (design D18).
    .tooltip(tab.title.isEmpty ? nil : tab.title, delay: Self.titleTooltipDelay)
    // The speaker comes and goes with the sound, the title making room. The
    // list's rows ignore implicit animations, so the row animates its own
    // state.
    .onAppear { showsSpeaker = tab.isAudible || tab.isMuted }
    .onChange(of: tab.isAudible || tab.isMuted) { _, shows in
      withAnimation(.snappy(duration: 0.25)) { showsSpeaker = shows }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(tab.title)
    .accessibilityIdentifier("clair.tabRow")
    .accessibilityAddTraits(isActive ? .isSelected : [])
  }
}

/// The tab's speaker, as in Arc: the outline speaker with three waves, or
/// crossed out while muted, 17.5 pt wide in mid-grey on a 26 pt button
/// with a hover background. SF Symbols animates the change.
struct TabSpeakerButton: View {
  let isMuted: Bool
  /// Asks for the tab to be muted (true) or unmuted.
  let setMuted: (Bool) -> Void

  /// What Chromium last reported, kept here so the change animates: the
  /// list's rows ignore implicit animations. The button only ever shows what
  /// Chromium reports, so it can't fall out of step with the tab.
  @State private var shownMuted: Bool?

  var body: some View {
    let muted = shownMuted ?? isMuted
    // Arc's grey, which measures about 125 on the light pill.
    IconButton(
      help: muted ? "Unmute this tab" : "Mute this tab", size: TabRow.closeSize, dimsWhenInactive: false,
      foreground: Color.primary.opacity(0.68)
    ) {
      setMuted(!isMuted)
    } label: {
      Image(systemName: muted ? "speaker.slash" : "speaker.wave.3")
        .font(.system(size: 13.5, weight: .medium))
        .contentTransition(.symbolEffect(.replace.magic(fallback: .replace), options: .speed(1.5)))
    }
    .onChange(of: isMuted) { _, reported in
      withAnimation(.snappy(duration: 0.2)) { shownMuted = reported }
    }
    .accessibilityIdentifier("clair.tabSpeaker")
  }
}

/// The tab's close button, as in Arc: 26 pt with a 10 pt glyph and its own
/// hover background.
struct TabCloseButton: View {
  let action: () -> Void

  var body: some View {
    IconButton(
      systemImage: "xmark", help: "Close tab", shortcut: ["⌘", "W"], size: TabRow.closeSize, glyphSize: 12,
      glyphWeight: .bold, dimsWhenInactive: false, action: action
    )
    .accessibilityIdentifier("clair.tabClose")
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
