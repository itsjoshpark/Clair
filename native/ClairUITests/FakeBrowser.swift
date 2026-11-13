// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Foundation

@testable import ClairUI

/// A stand-in for Chromium's tab snapshot.
final class FakeTab: NSObject, ClairTab {
  let tabID: TabID
  let title: String
  let url: URL?
  let urlText: String
  let displayHost: String?
  let isNewTabPage: Bool
  let isNotSecure: Bool
  let favicon: NSImage? = nil
  let isLoading: Bool
  let loadProgress: Double
  let canGoBack: Bool
  let canGoForward: Bool
  let isAudible: Bool
  let isMuted: Bool
  let isCrashed: Bool
  let indicators: TabIndicators
  let infobars: [any ClairInfobar]
  let peekParentID: TabID
  let peekID: TabID
  let spaceID: SpaceID
  let browserID: BrowserID

  init(
    id: TabID, title: String = "", url: String? = nil, isLoading: Bool = false, loadProgress: Double = 0,
    canGoBack: Bool = false, canGoForward: Bool = false, isAudible: Bool = false, isMuted: Bool = false, isCrashed: Bool = false,
    indicators: TabIndicators = [], infobars: [any ClairInfobar] = [], isNotSecure: Bool = false,
    peekParentID: TabID = ClairTabIDNone, peekID: TabID = ClairTabIDNone, spaceID: SpaceID = FakeHost.homeID,
    browserID: BrowserID = 0
  ) {
    tabID = id
    self.peekParentID = peekParentID
    self.peekID = peekID
    self.spaceID = spaceID
    self.browserID = browserID
    self.title = title
    self.url = url.flatMap(URL.init(string:))
    urlText = url ?? ""
    displayHost = self.url?.host()
    isNewTabPage = url == "chrome://newtab/"
    self.isNotSecure = isNotSecure
    self.isLoading = isLoading
    self.loadProgress = loadProgress
    self.canGoBack = canGoBack
    self.canGoForward = canGoForward
    self.isAudible = isAudible
    self.isMuted = isMuted
    self.isCrashed = isCrashed
    self.indicators = indicators
    self.infobars = infobars
  }

  /// A copy with some fields changed, as Chromium posts after a change.
  func with(
    title: String? = nil, url: String? = nil, isLoading: Bool? = nil, loadProgress: Double? = nil,
    isAudible: Bool? = nil, isMuted: Bool? = nil, canGoBack: Bool? = nil, canGoForward: Bool? = nil,
    isCrashed: Bool? = nil, indicators: TabIndicators? = nil, isNotSecure: Bool? = nil,
    peekParentID: TabID? = nil, peekID: TabID? = nil, spaceID: SpaceID? = nil, browserID: BrowserID? = nil
  ) -> FakeTab {
    FakeTab(
      id: tabID, title: title ?? self.title, url: url ?? (self.url?.absoluteString),
      isLoading: isLoading ?? self.isLoading, loadProgress: loadProgress ?? self.loadProgress,
      canGoBack: canGoBack ?? self.canGoBack,
      canGoForward: canGoForward ?? self.canGoForward, isAudible: isAudible ?? self.isAudible,
      isMuted: isMuted ?? self.isMuted, isCrashed: isCrashed ?? self.isCrashed,
      indicators: indicators ?? self.indicators, infobars: infobars, isNotSecure: isNotSecure ?? self.isNotSecure,
      peekParentID: peekParentID ?? self.peekParentID, peekID: peekID ?? self.peekID,
      spaceID: spaceID ?? self.spaceID, browserID: browserID ?? self.browserID)
  }
}

/// A stand-in for an infobar snapshot.
final class FakeInfobar: NSObject, ClairInfobar {
  let infobarID: Int
  let message: String
  let linkText: String?
  let okButtonLabel: String?
  let cancelButtonLabel: String?
  var icon: NSImage?

  init(id: Int, message: String, linkText: String? = nil, ok: String? = nil, cancel: String? = nil) {
    infobarID = id
    self.message = message
    self.linkText = linkText
    okButtonLabel = ok
    cancelButtonLabel = cancel
  }
}

/// A stand-in for an autocomplete suggestion.
final class FakeSuggestion: NSObject, ClairSuggestion {
  let suggestionID: Int
  let kind: SuggestionKind
  let contents: String
  let descriptionText: String
  let destination: URL?
  var icon: NSImage?
  let hasTabMatch: Bool
  let keyword: String?
  let keywordName: String?
  let canDelete: Bool

  init(
    id: Int, kind: SuggestionKind = .history, contents: String, description: String = "",
    destination: String? = nil, hasTabMatch: Bool = false, keyword: String? = nil, keywordName: String? = nil,
    canDelete: Bool = false
  ) {
    self.canDelete = canDelete
    suggestionID = id
    self.kind = kind
    self.contents = contents
    descriptionText = description
    self.destination = destination.flatMap(URL.init(string:))
    self.hasTabMatch = hasTabMatch
    self.keyword = keyword
    self.keywordName = keywordName
  }
}

/// A stand-in for an extension confirmation snapshot.
final class FakeExtensionPrompt: NSObject, ClairExtensionPrompt {
  let promptID: Int
  let kind: ExtensionPromptKind
  let extensionName: String
  var icon: NSImage?
  let permissions: [String]
  let title: String
  let permissionsHeading: String
  let acceptLabel: String
  let cancelLabel: String

  init(
    id: Int, kind: ExtensionPromptKind, name: String, permissions: [String] = [], title: String = "",
    heading: String = "", accept: String = "", cancel: String = ""
  ) {
    promptID = id
    self.kind = kind
    extensionName = name
    self.permissions = permissions
    self.title = title
    permissionsHeading = heading
    acceptLabel = accept
    cancelLabel = cancel
  }
}

/// A stand-in for an extension action snapshot.
final class FakeExtensionAction: NSObject, ClairExtensionAction {
  let extensionID: String
  let name: String
  var icon: NSImage?
  let badgeText: String
  let badgeBackgroundColor: NSColor?
  let badgeTextColor: NSColor?
  let isPinned: Bool
  let isEnabled: Bool
  let hasPopup: Bool

  init(
    id: String, name: String, badge: String = "", badgeBackground: NSColor? = nil, badgeTextColor: NSColor? = nil,
    pinned: Bool = true, enabled: Bool = true, popup: Bool = true
  ) {
    extensionID = id
    self.name = name
    badgeText = badge
    badgeBackgroundColor = badgeBackground
    self.badgeTextColor = badgeTextColor
    isPinned = pinned
    isEnabled = enabled
    hasPopup = popup
  }
}

/// A stand-in for a download snapshot.
final class FakeDownload: NSObject, ClairDownload {
  let downloadID: String
  let fileName: String
  let state: DownloadState
  let receivedBytes: Int64
  let totalBytes: Int64
  let needsDecision: Bool
  let warningText: String?
  let canResume: Bool
  let isSeen: Bool

  init(
    id: String, fileName: String, state: DownloadState = .inProgress, received: Int64 = 0, total: Int64 = 0,
    needsDecision: Bool = false, canResume: Bool = false, seen: Bool = false
  ) {
    downloadID = id
    self.fileName = fileName
    self.state = state
    receivedBytes = received
    totalBytes = total
    self.needsDecision = needsDecision
    warningText = needsDecision ? "This file may be dangerous" : nil
    self.canResume = canResume
    isSeen = seen
  }
}

/// A stand-in for Chromium's autocomplete session. Tests post suggestions to
/// its delegate with `post(_:finished:)`.
final class FakeAutocomplete: NSObject, ClairAutocomplete {
  let mode: CommandBarMode
  weak var delegate: (any ClairAutocompleteDelegate)?
  private(set) var keyword: String?
  private(set) var keywordName: String?
  let keywordIcon: NSImage? = nil

  private(set) var queries: [String] = []
  private(set) var opened: [(suggestionID: Int, disposition: OpenDisposition)] = []
  /// The IDs passed to `delete(suggestion:)` for deletable suggestions.
  private(set) var deleted: [Int] = []
  /// Runs on each deletion, as Chromium sends the shorter list during the call.
  var onDelete: ((Int) -> Void)?
  private(set) var isStopped = false
  /// The suggestions most recently posted.
  private(set) var suggestions: [FakeSuggestion] = []

  init(mode: CommandBarMode, delegate: any ClairAutocompleteDelegate) {
    self.mode = mode
    self.delegate = delegate
  }

  func query(_ text: String) {
    guard !isStopped else { return }
    queries.append(text)
  }

  func acceptKeyword(ofSuggestion suggestionID: Int, text: String) {
    guard !isStopped, let suggestion = suggestions.first(where: { $0.suggestionID == suggestionID }) else {
      return
    }
    keyword = suggestion.keyword
    keywordName = suggestion.keywordName
    queries.append(text)
  }

  func clearKeyword(text: String) {
    guard !isStopped else { return }
    keyword = nil
    keywordName = nil
    queries.append(text)
  }

  func open(suggestion suggestionID: Int, disposition: OpenDisposition) {
    guard !isStopped else { return }
    opened.append((suggestionID, disposition))
  }

  func delete(suggestion suggestionID: Int) {
    guard !isStopped, suggestions.contains(where: { $0.suggestionID == suggestionID && $0.canDelete }) else {
      return
    }
    deleted.append(suggestionID)
    onDelete?(suggestionID)
  }

  func stop() {
    isStopped = true
  }

  /// Sends suggestions to the delegate, as Chromium does when results arrive.
  func post(_ suggestions: [FakeSuggestion], finished: Bool = true) {
    guard !isStopped else { return }
    self.suggestions = suggestions
    delegate?.autocomplete(self, didUpdate: suggestions, finished: finished)
  }
}

/// A stand-in for a history menu item.
final class FakeHistoryItem: NSObject, ClairHistoryItem {
  let itemID: Int
  let kind: HistoryItemKind
  let title: String
  let url: URL?
  let icon: NSImage?

  init(id: Int, title: String, url: String? = nil, icon: NSImage? = nil, kind: HistoryItemKind = .page) {
    itemID = id
    self.kind = kind
    self.title = title
    self.url = url.flatMap(URL.init(string:))
    self.icon = icon
  }

  /// "Show Full History", as Chromium lists it last.
  static func showFullHistory(id: Int) -> FakeHistoryItem {
    FakeHistoryItem(id: id, title: "Show Full History", kind: .showFullHistory)
  }

  func with(icon: NSImage?) -> FakeHistoryItem {
    FakeHistoryItem(id: itemID, title: title, url: url?.absoluteString, icon: icon, kind: kind)
  }
}

/// A stand-in for Chromium's history menu session. Tests post late favicons
/// with `setIcon(_:forItem:)`.
final class FakeHistoryMenu: NSObject, ClairHistoryMenu {
  let direction: HistoryDirection
  weak var delegate: (any ClairHistoryMenuDelegate)?
  private(set) var items: [any ClairHistoryItem]
  private(set) var opened: [(itemID: Int, disposition: OpenDisposition)] = []
  private(set) var isClosed = false

  init(direction: HistoryDirection, items: [FakeHistoryItem], delegate: any ClairHistoryMenuDelegate) {
    self.direction = direction
    self.items = items
    self.delegate = delegate
  }

  func open(item itemID: Int, disposition: OpenDisposition) {
    guard !isClosed else { return }
    opened.append((itemID, disposition))
    isClosed = true
  }

  func close() {
    isClosed = true
  }

  /// A favicon arrived for an item, as Chromium's favicon service reports.
  func setIcon(_ icon: NSImage, forItem itemID: Int) {
    guard !isClosed else { return }
    items = items.map { item in
      guard item.itemID == itemID, let fake = item as? FakeHistoryItem else { return item }
      return fake.with(icon: icon)
    }
    delegate?.historyMenu(self, itemsDidChange: items)
  }
}

/// A stand-in for `ClairNativeWindow`: records where ClairUI puts the window
/// controls.
final class FakeWindow: NSWindow, ClairWindowControls {
  var windowControlsOrigin = CGPoint.zero
  var windowControlsHidden = false
}


/// A stand-in for Chromium's `ClairBrowser`. Its helpers change the tabs and
/// tell the host's observers and the window through the same calls Chromium
/// makes, and it records the commands ClairUI sends. It keeps the engine's
/// Space rules (add-spaces design D3, D4): the shown Space follows the active
/// tab, a new tab joins the shown Space, and closing the active row shows the
/// row the user came from, or the row above, or the row below. A regular
/// window lists every tab of its Space and takes one another window holds,
/// leaving that window a still (share-tabs-across-windows D1 to D4).
final class FakeBrowser: NSObject, ClairBrowser {
  let host: FakeHost
  let window: NSWindow & ClairWindowControls
  let profileKind: ProfileKind
  let browserID: BrowserID
  private(set) var shownSpaceID: SpaceID
  private(set) var activeTabID: TabID = ClairTabIDNone
  private(set) var devToolsView: NSView?
  private(set) var devToolsLayout = DevToolsLayout(dockSide: .none, pageBounds: .zero, hidesPage: false)
  private(set) var extensionActions: [any ClairExtensionAction] = []
  private(set) var downloads: [any ClairDownload] = []
  private(set) var downloadProgress = DownloadProgress()

  // The still (share-tabs-across-windows D2).
  private(set) var stillTabID: TabID = ClairTabIDNone
  private(set) var stillImage: NSImage?
  /// The hidden placeholder tab under the still, in no Space, or none.
  private(set) var placeholderID: TabID = ClairTabIDNone
  /// The page's copy the next still gets; nil as when the copy fails.
  var nextStillImage: NSImage? = NSImage(size: NSSize(width: 4, height: 4))

  /// The window ClairUI returned for this browser.
  var clairWindow: (any ClairWindow)?
  private static var nextBrowserID: BrowserID = 1

  /// The row the user selected the active tab from (D4), or none.
  private(set) var cameFromID: TabID = ClairTabIDNone
  /// The tab last active in each Space, in this window.
  private var lastActive: [SpaceID: TabID] = [:]
  /// While Clair picks the next tab before a close, which sets no came-from.
  private var isChoosingNext = false

  /// Every command ClairUI sent, in order, such as "activate 2".
  private(set) var commands: [String] = []
  private(set) var autocompleteSessions: [FakeAutocomplete] = []
  private(set) var historyMenus: [FakeHistoryMenu] = []
  /// What a history menu lists in each direction; empty means the active tab
  /// can't go that way, and no session starts.
  var historyItems: [HistoryDirection: [FakeHistoryItem]] = [:]
  private(set) var isClosed = false

  init(host: FakeHost = FakeHost(), profileKind: ProfileKind = .regular) {
    self.host = host
    self.profileKind = profileKind
    browserID = Self.nextBrowserID
    Self.nextBrowserID += 1
    // D3: a new window shows the Space last shown; incognito and guest
    // windows have a Space of their own.
    if profileKind == .regular {
      shownSpaceID = host.isSpace(host.lastShownSpaceID) ? host.lastShownSpaceID : host.spaces[0].spaceID
    } else {
      // One Space for the off-the-record profile's windows, which list
      // their own tabs.
      shownSpaceID = "private-\(profileKind.rawValue)"
    }
    window = FakeWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800), styleMask: [.titled, .closable, .resizable],
      backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false
    super.init()
    host.register(self)
  }

  /// The model ClairUI keeps for this host.
  var spaces: SpacesModel { host.spacesModel }

  /// The tabs of the Space the window shows, in the Space's order, Peeks
  /// included: what its sidebar lists. Every window's in a regular window,
  /// its own in an incognito or guest one.
  var tabs: [any ClairTab] { listed(inSpace: shownSpaceID) }

  /// Every tab the window holds, in any Space.
  var allTabs: [FakeTab] { host.tabs(ofBrowser: browserID) }

  private func listed(inSpace spaceID: SpaceID) -> [FakeTab] {
    profileKind == .regular ? host.list(spaceID) : windowTabs(inSpace: spaceID)
  }

  /// The tabs of a Space the window holds, as its tab strip has them.
  private func windowTabs(inSpace spaceID: SpaceID) -> [FakeTab] {
    host.list(spaceID).filter { $0.browserID == browserID }
  }

  /// A tab the window holds.
  private func tab(_ tabID: TabID) -> FakeTab? {
    host.tab(tabID).flatMap { $0.browserID == browserID ? $0 : nil }
  }

  /// A tab the window lists in some Space, whichever window holds it: the
  /// tabs ClairUI's commands may name (D1).
  private func rowTab(_ tabID: TabID) -> FakeTab? {
    guard let tab = host.tab(tabID) else { return nil }
    if tab.browserID == browserID { return tab }
    guard profileKind == .regular, host.isSpace(tab.spaceID), host.browser(tab.browserID)?.profileKind == .regular
    else { return nil }
    return tab
  }

  /// The window holding a tab.
  private func holder(of tab: FakeTab) -> FakeBrowser? {
    tab.browserID == browserID ? self : host.browser(tab.browserID)
  }

  /// Changes a Space's list and tells the observers.
  private func mutate(_ spaceID: SpaceID, _ change: (inout [FakeTab]) -> Void) {
    var list = host.list(spaceID)
    change(&list)
    host.setList(list, inSpace: spaceID)
  }

  /// The index in a Space's list of the window's row at `index`, counting
  /// only the tabs the window lists: before it, or after the last.
  private func spaceIndex(forWindowIndex index: Int, inSpace spaceID: SpaceID) -> Int {
    let list = host.list(spaceID)
    let mine = listed(inSpace: spaceID)
    if index <= 0 { return 0 }
    if index < mine.count, let at = list.firstIndex(where: { $0.tabID == mine[index].tabID }) {
      return at
    }
    if let last = mine.last, let at = list.firstIndex(where: { $0.tabID == last.tabID }) {
      return at + 1
    }
    return list.count
  }

  // MARK: Helpers that change the browser as Chromium would

  /// Adds a tab to the Space the window shows, at `index` among the tabs
  /// the window lists there (default: the top, as Clair places new tabs),
  /// and returns it. It becomes active if `activate` or if it's the window's
  /// only tab.
  @discardableResult
  func addTab(title: String = "", url: String? = nil, at index: Int = 0, activate: Bool = true) -> FakeTab {
    let tab = FakeTab(id: host.newTabID(), title: title, url: url, spaceID: shownSpaceID, browserID: browserID)
    host.pageViews[tab.tabID] = NSView()
    let at = spaceIndex(forWindowIndex: index, inSpace: shownSpaceID)
    mutate(shownSpaceID) { $0.insert(tab, at: min(at, $0.count)) }
    if activate || allTabs.count == 1 {
      setActive(tab.tabID)
    }
    return tab
  }

  /// Replaces a tab's snapshot and posts it.
  func change(_ tab: FakeTab) {
    host.replace(tab)
  }

  /// Moves a tab within its Space's list, alone, as an extension might.
  func moveTab(_ tabID: TabID, to index: Int) {
    guard let tab = tab(tabID) else { return }
    mutate(tab.spaceID) { list in
      list.removeAll { $0.tabID == tabID }
      list.insert(tab, at: max(0, min(index, list.count)))
    }
  }

  /// Closes a tab as Chromium does on its own, as when its page closes
  /// itself. If it was active, Chromium picks the tab after it in the strip,
  /// or before it, which may be in another Space; the window then shows that
  /// tab's Space (D3, D4). A window showing a still of it shows its
  /// placeholder as a new tab page (share-tabs-across-windows D2).
  func closeTabNow(_ tabID: TabID) {
    host.operation {
      guard let tab = tab(tabID) else { return }
      var next = ClairTabIDNone
      if activeTabID == tabID {
        let strip = allTabs
        if let index = strip.firstIndex(where: { $0.tabID == tabID }) {
          let others = windowTabs(inSpace: tab.spaceID).filter { $0.tabID != tabID }
          let inSpaceIndex = windowTabs(inSpace: tab.spaceID).firstIndex { $0.tabID == tabID } ?? 0
          if !others.isEmpty {
            next = others[min(inSpaceIndex, others.count - 1)].tabID
          } else if strip.count > 1 {
            next = strip[index + 1 < strip.count ? index + 1 : index - 1].tabID
          }
        }
      }
      host.pageViews[tabID] = nil
      mutate(tab.spaceID) { $0.removeAll { $0.tabID == tabID } }
      if cameFromID == tabID {
        cameFromID = ClairTabIDNone
      }
      if activeTabID == tabID {
        // A close that changes the active tab clears the came-from (D4).
        cameFromID = ClairTabIDNone
        isChoosingNext = true
        setActive(next)
        isChoosingNext = false
      }
      host.tabClosed(tabID)
    }
  }

  /// Makes a tab active, as Chromium does for any reason. The window shows
  /// the tab's Space (D3), and remembers the row the user came from (D4).
  /// The placeholder leaves both alone; any other tab ends the still.
  func setActive(_ tabID: TabID) {
    host.operation {
      let previous = activeTabID
      activeTabID = tabID
      if tabID != placeholderID, let tab = tab(tabID) {
        host.stamp(tabID)
        if previous != ClairTabIDNone, previous == placeholderID {
          // Taking the still's tab back keeps the came-from; moving on doesn't.
          let row = tab.peekParentID != ClairTabIDNone ? tab.peekParentID : tab.tabID
          if row != stillTabID {
            cameFromID = ClairTabIDNone
          }
        } else if !isChoosingNext, previous != ClairTabIDNone, previous != tabID, let from = self.tab(previous) {
          let row = from.peekParentID != ClairTabIDNone ? from.peekParentID : from.tabID
          if row != tabID && row != tab.peekParentID {
            cameFromID = row
          }
        }
        lastActive[tab.spaceID] = tabID
        if tab.spaceID != shownSpaceID {
          setShown(tab.spaceID)
        }
      }
      if tabID != placeholderID, stillTabID != ClairTabIDNone {
        endStill()
      }
      clairWindow?.activeTabDidChange(tabID)
      // D2: the row shown until now goes back to a window with a still of it,
      // if no window shows it.
      if previous != placeholderID, let from = self.tab(previous) {
        let row = from.peekParentID != ClairTabIDNone ? from.peekParentID : from.tabID
        let newRow = self.tab(tabID).map { $0.peekParentID != ClairTabIDNone ? $0.peekParentID : $0.tabID }
        if row != newRow {
          host.giveBack(row)
        }
      }
    }
  }

  private func setShown(_ spaceID: SpaceID) {
    let previous = shownSpaceID
    shownSpaceID = spaceID
    if profileKind == .regular {
      host.lastShownSpaceID = spaceID
    }
    clairWindow?.shownSpaceDidChange(spaceID, from: previous)
  }

  /// D4: the row to show before the active row `rowID` leaves the Space: the
  /// row the user came from, if it's still listed, or the row above, or the
  /// row below, from every window's rows.
  func nextRow(leaving rowID: TabID) -> TabID? {
    let rows = TabListLogic.rows(tabs).map(\.tabID)
    guard let index = rows.firstIndex(of: rowID) else { return nil }
    if cameFromID != ClairTabIDNone, cameFromID != rowID, rows.contains(cameFromID) {
      return cameFromID
    }
    if index > 0 { return rows[index - 1] }
    if index + 1 < rows.count { return rows[index + 1] }
    return nil
  }

  /// D3: the most recently active row of another Space than `rowID`'s that
  /// no window shows.
  private func rowOfAnotherSpace(than rowID: TabID) -> TabID? {
    guard profileKind == .regular, let tab = host.tab(rowID) else { return nil }
    return host.spaces.map(\.spaceID).filter { $0 != tab.spaceID }
      .flatMap { TabListLogic.rows(host.list($0)).map(\.tabID) }
      .filter { !host.isShown($0, except: self) }
      .max { host.lastActive(row: $0) < host.lastActive(row: $1) }
  }

  /// Shows `row`, or its Peek, taking it from another window if need be.
  private func activateRow(_ row: TabID) {
    guard let tab = host.tab(row) else { return }
    let target = TabListLogic.tabToActivate(forRow: row, in: host.list(tab.spaceID))
    if self.tab(target) != nil {
      setActive(target)
    } else {
      take(target)
    }
  }

  /// Shows `row`, or its Peek, as Clair's choice of the next tab, which sets
  /// no came-from.
  private func choose(_ row: TabID) {
    isChoosingNext = true
    activateRow(row)
    isChoosingNext = false
    cameFromID = ClairTabIDNone
  }

  /// Whether `tabID` is the row the window shows: the active tab, or the
  /// parent of the active Peek.
  func isActiveRow(_ tabID: TabID) -> Bool {
    activeTabID != placeholderID && TabListLogic.highlightedRow(activeTabID: activeTabID, in: tabs) == tabID
  }

  /// Before the active row moves to another Space (D7): shows the next row,
  /// or a new tab page, so the window stays on its Space.
  func leaveBeforeMoving(_ tabID: TabID) {
    guard isActiveRow(tabID) else { return }
    if let next = nextRow(leaving: tabID) {
      choose(next)
    } else {
      isChoosingNext = true
      addTab(url: "chrome://newtab/")
      isChoosingNext = false
      cameFromID = ClairTabIDNone
    }
  }

  /// Closes a tab this window holds as Clair does, first showing the next
  /// tab if it's the active row (D4, share-tabs-across-windows D3).
  fileprivate func closeAsClair(_ tabID: TabID) {
    guard let tab = tab(tabID) else { return }
    if isActiveRow(tabID) {
      if let next = nextRow(leaving: tabID) {
        choose(next)
      } else if tab.peekParentID == ClairTabIDNone, let other = rowOfAnotherSpace(than: tabID) {
        choose(other)
      }
    }
    closeTabNow(tabID)
  }

  // MARK: Tabs shared across windows (share-tabs-across-windows D1, D2, D4)

  /// D1: moves `tabID`, with its Peek, here and activates it. The window
  /// holding it keeps a still if it showed it.
  func take(_ tabID: TabID) {
    guard let tab = rowTab(tabID), tab.browserID != browserID, let holder = holder(of: tab) else { return }
    let row = tab.peekParentID != ClairTabIDNone ? tab.peekParentID : tab.tabID
    if holder.isActiveRow(row) {
      holder.beginStill(of: row)
    }
    moveFamilyHere(row)
    setActive(tabID)
  }

  /// Moves `row` and its Peek into this window, keeping their place.
  fileprivate func moveFamilyHere(_ row: TabID) {
    guard let tab = host.tab(row) else { return }
    let family: Set<TabID> = [row, tab.peekID]
    mutate(tab.spaceID) { list in
      for index in list.indices where family.contains(list[index].tabID) {
        list[index] = list[index].with(browserID: browserID)
      }
    }
  }

  /// D2: another window took `row`, which this window showed.
  fileprivate func beginStill(of row: TabID) {
    stillTabID = row
    stillImage = nextStillImage
    placeholderID = host.newTabID()
    host.pageViews[placeholderID] = NSView()
    clairWindow?.stillDidChange()
    setActive(placeholderID)
  }

  /// D2: another tab became active; the placeholder closes.
  private func endStill() {
    stillTabID = ClairTabIDNone
    stillImage = nil
    if placeholderID != ClairTabIDNone, placeholderID != activeTabID {
      host.pageViews[placeholderID] = nil
      placeholderID = ClairTabIDNone
    }
    clairWindow?.stillDidChange()
  }

  /// D2: the still's tab closed: the placeholder becomes a new tab page at
  /// the top of the shown Space, with the command bar.
  func stillTabClosedForHost() {
    let placeholder = placeholderID
    stillTabID = ClairTabIDNone
    stillImage = nil
    placeholderID = ClairTabIDNone
    clairWindow?.stillDidChange()
    guard placeholder != ClairTabIDNone else { return }
    let tab = FakeTab(id: placeholder, url: "chrome://newtab/", spaceID: shownSpaceID, browserID: browserID)
    mutate(shownSpaceID) { $0.insert(tab, at: 0) }
    lastActive[shownSpaceID] = placeholder
    cameFromID = ClairTabIDNone
    clairWindow?.showCommandBar(mode: .currentTab)
  }

  /// D2: takes back the tab of its still, which no window shows any more,
  /// without becoming key.
  func takeBack(_ row: TabID) {
    guard stillTabID == row else { return }
    activateRow(row)
  }

  /// The window became key, as when the user clicks in it: it becomes the
  /// most recently active, and takes back the tab of its still (D2).
  func becomeKey() {
    host.operation {
      host.activated(self)
      if stillTabID != ClairTabIDNone {
        activateRow(stillTabID)
      }
    }
  }

  /// D4: hands every tab, the placeholder left out, to the most recently
  /// active other regular window. Returns whether there was one.
  private func handTabsToAnotherWindow() -> Bool {
    guard profileKind == .regular, let target = host.mostRecentBrowser(except: self) else { return false }
    let rows = allTabs.filter { $0.peekParentID == ClairTabIDNone }.map(\.tabID)
    for row in rows {
      target.moveFamilyHere(row)
    }
    if target.stillTabID != ClairTabIDNone, target.tab(target.stillTabID) != nil {
      target.activateRow(target.stillTabID)
    }
    return true
  }

  /// Opens a Peek of `parent` right after it in its Space and shows it, as a
  /// Shift+click does in Chromium (add-peek design D1).
  @discardableResult
  func openPeek(of parent: TabID, title: String = "", url: String? = nil) -> FakeTab? {
    guard let parentTab = tab(parent) else { return nil }
    let peek = FakeTab(
      id: host.newTabID(), title: title, url: url, peekParentID: parent, spaceID: parentTab.spaceID,
      browserID: browserID)
    host.pageViews[peek.tabID] = NSView()
    mutate(parentTab.spaceID) { list in
      guard let index = list.firstIndex(where: { $0.tabID == parent }) else { return }
      list[index] = parentTab.with(peekID: peek.tabID)
      list.insert(peek, at: index + 1)
    }
    setActive(peek.tabID)
    return peek
  }

  /// Unlinks a Peek from its parent, as expanding it or Chromium's own moves
  /// do.
  func unlinkPeek(_ peekID: TabID) {
    guard let peek = tab(peekID) else { return }
    mutate(peek.spaceID) { list in
      if let parentIndex = list.firstIndex(where: { $0.tabID == peek.peekParentID }) {
        list[parentIndex] = list[parentIndex].with(peekID: ClairTabIDNone)
      }
      if let index = list.firstIndex(where: { $0.tabID == peekID }) {
        list[index] = peek.with(peekParentID: ClairTabIDNone)
      }
    }
  }

  /// Marks the Peek of `parent` as closing, as the engine does before it
  /// activates the parent: the parent stops reporting it, the Peek keeps its
  /// parent.
  func beginClosingPeek(of parent: TabID) {
    guard let tab = tab(parent) else { return }
    mutate(tab.spaceID) { list in
      if let index = list.firstIndex(where: { $0.tabID == parent }) {
        list[index] = tab.with(peekID: ClairTabIDNone)
      }
    }
  }

  /// Keeps an Esc in the active Peek, as its page does with a dialog open.
  func keepEscape(for duration: TimeInterval = 1) {
    clairWindow?.peekDidKeepEscape(for: duration)
  }

  /// The Peek's ID for a parent or a Peek, or nil.
  private func peek(of tabID: TabID) -> FakeTab? {
    guard let tab = tab(tabID) else { return nil }
    let peekID = tab.peekParentID != ClairTabIDNone ? tab.tabID : tab.peekID
    return self.tab(peekID)
  }

  func setDevTools(_ view: NSView?, layout: DevToolsLayout) {
    devToolsView = view
    devToolsLayout = layout
    clairWindow?.devToolsDidChange()
  }

  /// Asks the window to confirm, as Chromium does.
  func showExtensionPrompt(_ prompt: FakeExtensionPrompt) {
    clairWindow?.showExtensionPrompt(prompt)
  }

  func dismissExtensionPrompt(_ promptID: Int) {
    clairWindow?.dismissExtensionPrompt(promptID)
  }

  func setExtensionActions(_ actions: [FakeExtensionAction]) {
    extensionActions = actions
    clairWindow?.extensionActionsDidChange(actions)
  }

  func setDownloads(_ downloads: [FakeDownload], progress: DownloadProgress = DownloadProgress()) {
    self.downloads = downloads
    downloadProgress = progress
    clairWindow?.downloadsDidChange(downloads, progress: progress)
  }

  /// Closes the window as Chromium does once its tabs have closed.
  func closeWindow() {
    isClosed = true
    clairWindow?.browserDidClose()
  }

  /// The latest command bar session.
  var autocomplete: FakeAutocomplete? { autocompleteSessions.last }

  // MARK: ClairBrowser

  private func record(_ command: String) {
    guard !isClosed else { return }
    commands.append(command)
  }

  func pageView(for tabID: TabID) -> NSView? {
    tabID == placeholderID || tab(tabID) != nil ? host.pageViews[tabID] : nil
  }

  func showSpace(_ spaceID: SpaceID) {
    host.operation {
      record("showSpace \(spaceID)")
      guard profileKind == .regular, host.isSpace(spaceID), spaceID != shownSpaceID else { return }
      // share-tabs-across-windows D3: the tab last active there here unless
      // another window shows it, else the most recently active row no window
      // shows, from any window.
      let list = host.list(spaceID)
      let rows = TabListLogic.rows(list).map(\.tabID).filter { !host.isShown($0, except: self) }
      let last = lastActive[spaceID].flatMap { id -> TabID? in
        guard let tab = list.first(where: { $0.tabID == id }) else { return nil }
        return rows.contains(tab.peekParentID != ClairTabIDNone ? tab.peekParentID : id) ? id : nil
      }
      let recent = rows.max { host.lastActive(row: $0) < host.lastActive(row: $1) }
      setShown(spaceID)
      if let last {
        if tab(last) != nil { setActive(last) } else { take(last) }
      } else if let recent {
        activateRow(recent)
      } else {
        // D3: a Space with no tab to show opens a new tab page with the
        // command bar.
        addTab(url: "chrome://newtab/")
        clairWindow?.showCommandBar(mode: .currentTab)
      }
    }
  }

  func activate(tab tabID: TabID) {
    host.operation {
      record("activate \(tabID)")
      if tab(tabID) != nil {
        setActive(tabID)
      } else if rowTab(tabID) != nil {
        take(tabID)
      }
    }
  }

  func close(tab tabID: TabID) {
    host.operation {
      record("close \(tabID)")
      // D4: Clair picks the next tab before it closes the active row, in the
      // window that holds it.
      guard let tab = rowTab(tabID) else { return }
      holder(of: tab)?.closeAsClair(tabID)
    }
  }

  func closeTabs(below tabID: TabID) {
    host.operation {
      record("closeBelow \(tabID)")
      // As the engine: from the tab's Peek, which stays (ClairPeeks::LastOfFamily),
      // over the rows of its Space, in whichever window holds each.
      guard let tab = rowTab(tabID) else { return }
      let list = listed(inSpace: tab.spaceID)
      let last = tab.peekID != ClairTabIDNone ? tab.peekID : tabID
      guard let index = list.firstIndex(where: { $0.tabID == last }) else { return }
      for below in list[(index + 1)...] {
        if let current = host.tab(below.tabID) {
          holder(of: current)?.closeAsClair(below.tabID)
        }
      }
    }
  }

  func move(tab tabID: TabID, to index: Int) {
    record("move \(tabID) \(index)")
    // As the engine: a tab and its Peek move as one in the Space's list, the
    // tab ending at `index` and its Peek right after it.
    guard let tab = rowTab(tabID) else { return }
    let peek = tab.peekID != ClairTabIDNone ? host.tab(tab.peekID) : nil
    let family = [tab] + (peek.map { [$0] } ?? [])
    mutate(tab.spaceID) { list in
      list.removeAll { candidate in family.contains { $0.tabID == candidate.tabID } }
      list.insert(contentsOf: family, at: max(0, min(index, list.count)))
    }
  }

  func closePeek(of tabID: TabID) {
    record("closePeek \(tabID)")
    if let tab = rowTab(tabID), tab.browserID != browserID {
      holder(of: tab)?.closePeekHere(of: tabID)
      return
    }
    closePeekHere(of: tabID)
  }

  fileprivate func closePeekHere(of tabID: TabID) {
    guard let peek = peek(of: tabID) else { return }
    // As the engine: the parent stops reporting its closing Peek, then
    // becomes active, then the Peek goes once its page has unloaded.
    beginClosingPeek(of: peek.peekParentID)
    if activeTabID == peek.tabID {
      setActive(peek.peekParentID)
    }
    closeTabNow(peek.tabID)
  }

  func expandPeek(of tabID: TabID) {
    record("expandPeek \(tabID)")
    if let tab = rowTab(tabID), tab.browserID != browserID {
      holder(of: tab)?.expandPeekHere(of: tabID)
      return
    }
    expandPeekHere(of: tabID)
  }

  fileprivate func expandPeekHere(of tabID: TabID) {
    guard let peek = peek(of: tabID) else { return }
    unlinkPeek(peek.tabID)
    if activeTabID != peek.tabID {
      setActive(peek.tabID)
    }
  }

  func duplicate(tab tabID: TabID) { record("duplicate \(tabID)") }
  func setMuted(_ muted: Bool, tab tabID: TabID) { record("\(muted ? "mute" : "unmute") \(tabID)") }
  func goBack() { record("back") }
  func goForward() { record("forward") }
  func reload() { record("reload") }
  func stop() { record("stop") }

  func open(_ url: URL, disposition: OpenDisposition) {
    record("open \(url.absoluteString) \(disposition.rawValue)")
  }

  func startAutocomplete(mode: CommandBarMode, delegate: any ClairAutocompleteDelegate) -> any ClairAutocomplete {
    record("autocomplete \(mode.rawValue)")
    let session = FakeAutocomplete(mode: mode, delegate: delegate)
    autocompleteSessions.append(session)
    return session
  }

  func startHistoryMenu(direction: HistoryDirection, delegate: any ClairHistoryMenuDelegate)
    -> (any ClairHistoryMenu)?
  {
    record("historyMenu \(direction.rawValue)")
    guard let items = historyItems[direction], !items.isEmpty else { return nil }
    let menu = FakeHistoryMenu(direction: direction, items: items, delegate: delegate)
    historyMenus.append(menu)
    return menu
  }

  /// The latest history menu session.
  var historyMenu: FakeHistoryMenu? { historyMenus.last }

  func focusPage() { record("focusPage") }
  func find(_ text: String, forward: Bool) { record("find \(text) \(forward ? "forward" : "backward")") }
  func stopFinding() { record("stopFinding") }

  func showPageInfo(at kind: AnchorKind, indicator: TabIndicators) {
    record("pageInfo \(kind.rawValue) \(indicator.rawValue)")
  }

  func runExtensionAction(_ extensionID: String, anchor: AnchorKind) {
    record("runExtension \(extensionID) \(anchor.rawValue)")
  }

  func setExtensionAction(_ extensionID: String, pinned: Bool) {
    record("\(pinned ? "pin" : "unpin") \(extensionID)")
  }

  func extensionPopupDidClose() { record("popupClosed") }

  func contextMenu(forExtension extensionID: String) -> NSMenu? {
    record("extensionMenu \(extensionID)")
    return nil
  }

  func answerExtensionPrompt(_ promptID: Int, accepted: Bool) {
    record("answerPrompt \(promptID) \(accepted)")
  }
  func openDownload(_ downloadID: String) { record("openDownload \(downloadID)") }
  func showDownloadInFinder(_ downloadID: String) { record("showDownload \(downloadID)") }
  func cancelDownload(_ downloadID: String) { record("cancelDownload \(downloadID)") }
  func resumeDownload(_ downloadID: String) { record("resumeDownload \(downloadID)") }
  func keepDownload(_ downloadID: String) { record("keepDownload \(downloadID)") }
  func discardDownload(_ downloadID: String) { record("discardDownload \(downloadID)") }
  func markDownloadsSeen() { record("downloadsSeen") }

  func infobar(_ infobarID: Int, tab tabID: TabID, didChoose action: InfobarAction) {
    record("infobar \(infobarID) \(tabID) \(action.rawValue)")
  }

  func requestClose() {
    host.operation {
      record("requestClose")
      // D4: another regular window keeps the tabs, and this one closes.
      if handTabsToAnotherWindow() {
        closeWindow()
      }
    }
  }
}

/// A `ClairWindow` test double that records what Chromium tells it.
final class RecordingWindow: NSObject, ClairWindow {
  let pageContainerView = NSView()
  var isSidebarHidden = false
  var opensPeekOnShiftClick = true
  private(set) var calls: [String] = []

  func shownSpaceDidChange(_ spaceID: SpaceID, from previousSpaceID: SpaceID?) {
    calls.append("space \(spaceID) from \(previousSpaceID ?? "-")")
  }

  func activeTabDidChange(_ tabID: TabID) { calls.append("active \(tabID)") }
  func stillDidChange() { calls.append("still") }
  func devToolsDidChange() { calls.append("devtools") }
  func showCommandBar(mode: CommandBarMode) { calls.append("commandBar \(mode.rawValue)") }
  func toggleSidebar() { isSidebarHidden.toggle() }
  func showFind(text: String) { calls.append("find \(text)") }
  func hideFind() { calls.append("hideFind") }
  func findResultDidChange(_ result: FindResult) { calls.append("findResult \(result.activeMatch)/\(result.matchCount)") }
  func statusTextDidChange(_ text: String?) { calls.append("status \(text ?? "-")") }
  func showToast(_ message: String) { calls.append("toast \(message)") }
  func pageFullscreenDidChange(_ fullscreen: Bool) { calls.append("pageFullscreen \(fullscreen)") }
  func showExclusiveAccessNotice(_ text: String?) { calls.append("notice \(text ?? "-")") }

  func anchor(for kind: AnchorKind, indicator: TabIndicators, extensionID: String?) -> BubbleAnchor {
    BubbleAnchor(rect: .zero, edge: .bottom)
  }

  func extensionActionsDidChange(_ actions: [any ClairExtensionAction]) {
    calls.append("extensions \(actions.count)")
  }

  func showExtensionPopup(_ view: NSView, size: NSSize, extension extensionID: String, anchor: AnchorKind) {
    calls.append("popup \(extensionID)")
  }

  func extensionPopupDidResize(_ size: NSSize) { calls.append("popupResize") }
  func closeExtensionPopup() { calls.append("closePopup") }
  func showExtensionPrompt(_ prompt: any ClairExtensionPrompt) { calls.append("prompt \(prompt.promptID)") }
  func dismissExtensionPrompt(_ promptID: Int) { calls.append("dismissPrompt \(promptID)") }
  func downloadsDidChange(_ downloads: [any ClairDownload], progress: DownloadProgress) {
    calls.append("downloads \(downloads.count)")
  }
  func downloadProgressDidChange(_ progress: DownloadProgress) { calls.append("progress \(progress.count)") }
  func browserDidClose() { calls.append("closed") }
  func peekDidKeepEscape(for duration: TimeInterval) { calls.append("keptEscape \(duration)") }
}

/// A `ClairSpacesObserver` test double that records what the host tells it.
final class RecordingSpacesObserver: NSObject, ClairSpacesObserver {
  private(set) var calls: [String] = []
  private(set) var lastTab: (any ClairTab)?
  private(set) var lists: [SpaceID: [any ClairTab]] = [:]

  func spacesDidChange(_ spaces: [any ClairSpace]) {
    calls.append("spaces \(spaces.map(\.name).joined(separator: ","))")
  }

  func tabsDidChange(_ tabs: [any ClairTab], inSpace spaceID: SpaceID) {
    lists[spaceID] = tabs
    calls.append("tabs \(spaceID) \(tabs.map { String($0.tabID) }.joined(separator: ","))")
  }

  func tabDidChange(_ tab: any ClairTab) {
    lastTab = tab
    calls.append("tab \(tab.tabID)")
  }
}
