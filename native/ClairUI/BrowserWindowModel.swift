// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Observation

/// What one native window shows, as Chromium last reported it through
/// `ClairWindow`, plus the window's own state (sidebar, overlays). SwiftUI
/// views observe it; only `BrowserWindowController` changes what came from
/// Chromium.
@Observable
final class BrowserWindowModel {
  let profileKind: ProfileKind

  /// The window's tabs in Chromium's order, which is the sidebar's.
  private(set) var tabs: [any ClairTab] = []
  private(set) var activeTabID: TabID = ClairTabIDNone

  var activeTab: (any ClairTab)? {
    tabs.first { $0.tabID == activeTabID }
  }

  private(set) var extensionActions: [any ClairExtensionAction] = []
  private(set) var downloads: [any ClairDownload] = []

  var pinnedExtensionActions: [any ClairExtensionAction] {
    extensionActions.filter(\.isPinned)
  }

  /// Whether the downloads button shows a finished download the user hasn't
  /// looked at.
  var hasUnseenDownloads: Bool {
    downloads.contains { $0.state == .complete && !$0.isSeen }
  }

  /// The overall progress of running downloads, 0 to 1, or nil when none runs
  /// or none knows its size.
  var downloadProgress: Double? {
    let running = downloads.filter { $0.state == .inProgress && $0.totalBytes > 0 }
    guard !running.isEmpty else { return nil }
    let received = running.reduce(Int64(0)) { $0 + $1.receivedBytes }
    let total = running.reduce(Int64(0)) { $0 + $1.totalBytes }
    return total > 0 ? Double(received) / Double(total) : nil
  }

  // --- the window's own state ---
  var sidebar: SidebarState
  var commandBar: CommandBarModel?
  var find: FindState?
  /// Bumped when Cmd+F asks for the find field again while it shows.
  var findFocusRequest = 0
  var statusText: String?
  var toast: Toast?
  var exclusiveAccessNotice: String?
  /// The popup in the card's top-trailing corner (design D18).
  let notice = NoticeState()
  var isPageFullscreen = false
  var isWindowKey = true
  /// Whether the window is in macOS full screen, where the top row has no
  /// window controls to make room for.
  var isWindowFullscreen = false
  var windowControls = WindowControlsMetrics.macOS27
  /// What the reload button shows (arc-navigation-feedback design D2).
  let reloadStop = ReloadStopState(doubleClickInterval: NSEvent.doubleClickInterval)

  init(profileKind: ProfileKind, sidebar: SidebarState) {
    self.profileKind = profileKind
    self.sidebar = sidebar
  }

  func setTabs(_ tabs: [any ClairTab]) {
    self.tabs = tabs
  }

  /// Replaces the snapshot of one tab; a tab the list doesn't have is ignored,
  /// since the list update that adds it carries its state.
  func updateTab(_ tab: any ClairTab) {
    guard let index = tabs.firstIndex(where: { $0.tabID == tab.tabID }) else {
      return
    }
    tabs[index] = tab
  }

  func setActiveTab(_ tabID: TabID) {
    activeTabID = tabID
  }

  func setExtensionActions(_ actions: [any ClairExtensionAction]) {
    extensionActions = actions
  }

  func setDownloads(_ downloads: [any ClairDownload]) {
    self.downloads = downloads
  }
}

/// A toast at the bottom of the card. Each has its own ID, so the same
/// message twice still shows twice.
struct Toast: Equatable, Identifiable {
  let id = UUID()
  let message: String
}

/// The sidebar's state in one window (design D12).
struct SidebarState: Equatable {
  static let defaultWidth: CGFloat = 228
  /// Arc's limits. The window controls can raise the lower one
  /// (`WindowControlsMetrics.narrowestSidebar`).
  static let widthRange: ClosedRange<CGFloat> = 164...500

  var width: CGFloat
  var isHidden: Bool
  /// Shown as a floating overlay over the page while hidden.
  var isRevealed = false

  init(width: CGFloat = SidebarState.defaultWidth, isHidden: Bool = false) {
    self.width = Self.clamp(width)
    self.isHidden = isHidden
  }

  static func clamp(_ width: CGFloat) -> CGFloat {
    min(max(width, widthRange.lowerBound), widthRange.upperBound)
  }

  /// Whether the sidebar takes its place beside the card, so its controls are
  /// where Chromium's bubbles attach.
  var isShownInPlace: Bool { !isHidden }
}

/// Where the window controls landed, relative to the sidebar's top-leading
/// corner, as accessibility reads them (place-traffic-lights-with-appkit D3b).
/// The top row is laid out from them, so the two line up on any macOS.
struct WindowControlsMetrics: Equatable {
  /// macOS 27's, which match Arc's, until the buttons are first read.
  static let macOS27 = WindowControlsMetrics(centreY: 24, trailingX: 74)
  /// In full screen, where there are no window controls: Arc keeps the top
  /// row where it is and starts hide-sidebar 13 pt in.
  static let fullScreen = WindowControlsMetrics(centreY: 24, trailingX: 13 - topRowGap)

  /// The close button's vertical centre.
  var centreY: CGFloat
  /// The zoom button's trailing edge.
  var trailingX: CGFloat

  /// The gap between the zoom button and the top row's first button: 4 pt
  /// more than Arc's 3, which the owner found too tight.
  static let topRowGap: CGFloat = 7

  /// Where the top row's first button may start. 81 on macOS 27.
  var topRowLeading: CGFloat { trailingX + Self.topRowGap }

  /// Below this sidebar width the top row is compact, as in Arc: back,
  /// forward and a menu holding reload and Hide Sidebar. 218 on macOS 27.
  var compactBelow: CGFloat { topRowLeading + 137 }

  /// The narrowest sidebar, where the compact row's back button (90 pt from
  /// the trailing edge) starts at the zoom button's edge. 164 on macOS 27.
  var narrowestSidebar: CGFloat { max(SidebarState.widthRange.lowerBound, trailingX + 90) }

  func hasCompactTopRow(width: CGFloat) -> Bool { width < compactBelow }

  /// Whether `other` differs by half a point or more.
  func differs(from other: WindowControlsMetrics) -> Bool {
    abs(centreY - other.centreY) >= 0.5 || abs(trailingX - other.trailingX) >= 0.5
  }
}

/// Find in page, while the find field is open.
struct FindState: Equatable {
  var text: String
  var result = FindResult(activeMatch: 0, matchCount: 0, finished: true)

  static func == (lhs: FindState, rhs: FindState) -> Bool {
    lhs.text == rhs.text && lhs.result.activeMatch == rhs.result.activeMatch
      && lhs.result.matchCount == rhs.result.matchCount && lhs.result.finished == rhs.result.finished
  }

  /// "1 of 3", or nothing before there's a result.
  var resultText: String {
    if text.isEmpty { return "" }
    if result.matchCount == 0 { return result.finished ? "0 of 0" : "" }
    return "\(result.activeMatch) of \(result.matchCount)"
  }
}
