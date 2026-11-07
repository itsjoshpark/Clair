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

  // --- the window's own state ---
  var sidebar: SidebarState
  var commandBar: CommandBarMode?
  var find: FindState?
  var statusText: String?
  var toast: String?
  var exclusiveAccessNotice: String?
  var isPageFullscreen = false

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

/// The sidebar's state in one window (design D12).
struct SidebarState: Equatable {
  static let defaultWidth: CGFloat = 228
  static let widthRange: ClosedRange<CGFloat> = 180...400

  var width: CGFloat
  var isHidden: Bool
  /// Shown as a floating overlay over the page while hidden.
  var isRevealed = false

  init(width: CGFloat = SidebarState.defaultWidth, isHidden: Bool = false) {
    self.width = min(max(width, Self.widthRange.lowerBound), Self.widthRange.upperBound)
    self.isHidden = isHidden
  }

  /// Whether the sidebar takes its place beside the card, so its controls are
  /// where Chromium's bubbles attach.
  var isShownInPlace: Bool { !isHidden }
}

/// Find in page, while the find field is open.
struct FindState: Equatable {
  var text: String
  var result = FindResult(activeMatch: 0, matchCount: 0, finished: true)

  static func == (lhs: FindState, rhs: FindState) -> Bool {
    lhs.text == rhs.text && lhs.result.activeMatch == rhs.result.activeMatch
      && lhs.result.matchCount == rhs.result.matchCount && lhs.result.finished == rhs.result.finished
  }
}
