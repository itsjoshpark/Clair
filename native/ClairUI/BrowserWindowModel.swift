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
  /// The window's ID, which its tabs carry.
  let browserID: BrowserID
  /// Every Space and its tabs, app-wide (add-spaces design D10).
  let spaces: SpacesModel

  /// The Space the window shows (add-spaces design D3).
  private(set) var shownSpaceID: SpaceID

  /// The tabs of the Space the window shows, in the Space's order, which is
  /// the sidebar's, Peeks included: every window's in a regular window
  /// (share-tabs-across-windows D1), its own in an incognito or guest one.
  private(set) var tabs: [any ClairTab] = []
  private(set) var activeTabID: TabID = ClairTabIDNone

  /// The tab another window took, whose dimmed still the card shows, or none
  /// (share-tabs-across-windows D2). Its row stays highlighted.
  private(set) var stillTabID: TabID = ClairTabIDNone
  /// The page as it was when it left, or nil when the copy failed: the card
  /// then dims its background alone.
  private(set) var stillImage: NSImage?

  /// Whether the card shows a still over the hidden placeholder tab.
  var isShowingStill: Bool { stillTabID != ClairTabIDNone }

  /// The Space the window shows, or nil in an incognito or guest window,
  /// whose Space isn't one of the user's.
  var shownSpace: (any ClairSpace)? {
    spaces.space(shownSpaceID)
  }

  /// Whether the window shows the user's Spaces: not in incognito and guest
  /// windows.
  var showsSpaces: Bool {
    profileKind == .regular
  }

  /// The tab whose page the card shows, which the URL field and the
  /// navigation buttons follow: none while the card shows a still.
  var activeTab: (any ClairTab)? {
    isShowingStill ? nil : tabs.first { $0.tabID == activeTabID }
  }

  /// The row highlighted in `tabs`: the still's while there's one, else the
  /// active tab's, or its parent's while a Peek shows.
  func highlightedRow(in tabs: [any ClairTab]) -> TabID {
    isShowingStill ? stillTabID : TabListLogic.highlightedRow(activeTabID: activeTabID, in: tabs)
  }

  /// Each row's Peek, whose favicon the row shows as a badge; the still's
  /// row shows none, as the still shows the page without its Peek.
  func rowPeeks(in tabs: [any ClairTab]) -> [TabID: any ClairTab] {
    var peeks = TabListLogic.peeksByRow(tabs)
    if isShowingStill {
      peeks[stillTabID] = nil
    }
    return peeks
  }

  /// What the URL field shows, or nil for its placeholder.
  var urlFieldText: String? { URLDisplay.text(for: activeTab) }
  /// Whether back, forward and reload can act on the page the card shows.
  var canGoBack: Bool { activeTab?.canGoBack ?? false }
  var canGoForward: Bool { activeTab?.canGoForward ?? false }
  var canReload: Bool { activeTab != nil }

  private(set) var extensionActions: [any ClairExtensionAction] = []
  private(set) var downloads: [any ClairDownload] = []
  /// The whole app's download progress, as the Dock shows it.
  private(set) var appDownloadProgress = DownloadProgress()

  var pinnedExtensionActions: [any ClairExtensionAction] {
    extensionActions.filter(\.isPinned)
  }

  /// Whether the downloads button shows a finished download the user hasn't
  /// looked at.
  var hasUnseenDownloads: Bool {
    downloads.contains { $0.state == .complete && !$0.isSeen }
  }

  /// The progress ring's value, 0 to 1, as the Dock shows it: every
  /// profile's running downloads, and no ring when none runs or any has an
  /// unknown size.
  var downloadProgress: Double? {
    let progress = appDownloadProgress
    guard progress.count > 0, !progress.isIndeterminate else { return nil }
    return min(max(progress.fraction, 0), 1)
  }

  // --- the window's own state ---
  /// What the Space header is editing (add-spaces D10).
  var spaceHeaderEdit: SpaceHeaderEdit?
  /// The New Space form, while it shows in place of the header and list.
  var newSpaceForm: NewSpaceFormState?
  /// The slide from the Space shown before, while it runs.
  var spaceSlide: SpaceSlide?
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
  /// Confirm on the Peek's Close button (add-peek design D6).
  let peekConfirm = PeekConfirmState()
  var isPageFullscreen = false
  var isSiteControlCenterOpen = false
  var isDownloadsListOpen = false
  /// A revealed sidebar stays revealed while one of its popovers is open
  /// (arc-site-control-center design D8).
  var isSidebarPopoverOpen: Bool { isSiteControlCenterOpen || isDownloadsListOpen }
  var isWindowKey = true
  /// Whether the window is in macOS full screen, where the top row has no
  /// window controls to make room for.
  var isWindowFullscreen = false
  var windowControls = WindowControlsMetrics.macOS27
  /// What the reload button shows (arc-navigation-feedback design D2).
  let reloadStop = ReloadStopState(doubleClickInterval: NSEvent.doubleClickInterval)

  init(
    profileKind: ProfileKind, sidebar: SidebarState, browserID: BrowserID = 0, shownSpaceID: SpaceID = "",
    spaces: SpacesModel = .detached
  ) {
    self.profileKind = profileKind
    self.sidebar = sidebar
    self.browserID = browserID
    self.shownSpaceID = shownSpaceID
    self.spaces = spaces
  }

  /// Shows another Space's rows, read from `spaces`.
  func setShownSpace(_ spaceID: SpaceID) {
    shownSpaceID = spaceID
    reloadTabs()
  }

  /// Whether the window lists only the tabs it holds: an incognito or guest
  /// window, whose tabs never leave it.
  var listsOwnTabsOnly: Bool { profileKind != .regular }

  /// Reads the window's rows of its Space again from `spaces`.
  func reloadTabs() {
    tabs =
      listsOwnTabsOnly
      ? spaces.tabs(inSpace: shownSpaceID, browser: browserID) : spaces.tabs(inSpace: shownSpaceID)
  }

  /// The window shows a still of `tabID`, with `image`, or none.
  func setStill(_ tabID: TabID, image: NSImage?) {
    stillTabID = tabID
    stillImage = tabID == ClairTabIDNone ? nil : image
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

  func setDownloads(_ downloads: [any ClairDownload], progress: DownloadProgress) {
    self.downloads = downloads
    setDownloadProgress(progress)
  }

  /// Takes the app-wide progress, leaving the model alone when nothing
  /// changed, so the sidebar doesn't redraw for nothing.
  func setDownloadProgress(_ progress: DownloadProgress) {
    let current = appDownloadProgress
    guard
      progress.count != current.count || progress.isIndeterminate != current.isIndeterminate
        || progress.fraction != current.fraction
    else { return }
    appDownloadProgress = progress
  }
}

/// A slide from one Space to another (add-spaces D10): the earlier Space's
/// header and rows, as they were, slide out while the new Space's slide in.
struct SpaceSlide: Identifiable {
  let id = UUID()
  let fromSpace: (any ClairSpace)?
  let fromTabs: [any ClairTab]
  /// Whether the new Space comes in from the trailing side, being later in
  /// the order.
  let fromTrailing: Bool
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
