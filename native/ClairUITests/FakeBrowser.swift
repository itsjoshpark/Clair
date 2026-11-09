// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Foundation

/// A stand-in for Chromium's tab snapshot.
final class FakeTab: NSObject, ClairTab {
  let tabID: TabID
  let title: String
  let url: URL?
  let urlText: String
  let displayHost: String?
  let isNewTabPage: Bool
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

  init(
    id: TabID, title: String = "", url: String? = nil, isLoading: Bool = false, loadProgress: Double = 0,
    canGoBack: Bool = false, canGoForward: Bool = false, isAudible: Bool = false, isMuted: Bool = false, isCrashed: Bool = false,
    indicators: TabIndicators = [], infobars: [any ClairInfobar] = []
  ) {
    tabID = id
    self.title = title
    self.url = url.flatMap(URL.init(string:))
    urlText = url ?? ""
    displayHost = self.url?.host()
    isNewTabPage = url == "chrome://newtab/"
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
    isCrashed: Bool? = nil, indicators: TabIndicators? = nil
  ) -> FakeTab {
    FakeTab(
      id: tabID, title: title ?? self.title, url: url ?? (self.url?.absoluteString),
      isLoading: isLoading ?? self.isLoading, loadProgress: loadProgress ?? self.loadProgress,
      canGoBack: canGoBack ?? self.canGoBack,
      canGoForward: canGoForward ?? self.canGoForward, isAudible: isAudible ?? self.isAudible,
      isMuted: isMuted ?? self.isMuted, isCrashed: isCrashed ?? self.isCrashed,
      indicators: indicators ?? self.indicators, infobars: infobars)
  }
}

/// A stand-in for an infobar snapshot.
final class FakeInfobar: NSObject, ClairInfobar {
  let infobarID: Int
  let message: String
  let linkText: String?
  let okButtonLabel: String?
  let cancelButtonLabel: String?
  let icon: NSImage? = nil

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
  let icon: NSImage? = nil
  let hasTabMatch: Bool
  let keyword: String?
  let keywordName: String?

  init(
    id: Int, kind: SuggestionKind = .history, contents: String, description: String = "",
    destination: String? = nil, hasTabMatch: Bool = false, keyword: String? = nil, keywordName: String? = nil
  ) {
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
  let icon: NSImage? = nil
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
  let icon: NSImage? = nil
  let badgeText: String
  let badgeBackgroundColor: NSColor? = nil
  let isPinned: Bool
  let isEnabled: Bool
  let hasPopup: Bool

  init(id: String, name: String, badge: String = "", pinned: Bool = true, enabled: Bool = true, popup: Bool = true) {
    extensionID = id
    self.name = name
    badgeText = badge
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
/// tell the window through the same `ClairWindow` calls Chromium makes, and
/// it records the commands ClairUI sends.
final class FakeBrowser: NSObject, ClairBrowser {
  let window: NSWindow & ClairWindowControls
  let profileKind: ProfileKind
  private(set) var tabs: [any ClairTab] = []
  private(set) var activeTabID: TabID = ClairTabIDNone
  private var pageViews: [TabID: NSView] = [:]
  private(set) var devToolsView: NSView?
  private(set) var devToolsLayout = DevToolsLayout(dockSide: .none, pageBounds: .zero, hidesPage: false)
  private(set) var extensionActions: [any ClairExtensionAction] = []
  private(set) var downloads: [any ClairDownload] = []
  private(set) var downloadProgress = DownloadProgress()

  /// The window ClairUI returned for this browser.
  var clairWindow: (any ClairWindow)?
  private var nextTabID: TabID = 1

  /// Every command ClairUI sent, in order, such as "activate 2".
  private(set) var commands: [String] = []
  private(set) var autocompleteSessions: [FakeAutocomplete] = []
  private(set) var historyMenus: [FakeHistoryMenu] = []
  /// What a history menu lists in each direction; empty means the active tab
  /// can't go that way, and no session starts.
  var historyItems: [HistoryDirection: [FakeHistoryItem]] = [:]
  private(set) var isClosed = false

  init(profileKind: ProfileKind = .regular) {
    self.profileKind = profileKind
    window = FakeWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800), styleMask: [.titled, .closable, .resizable],
      backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false
  }

  // MARK: Helpers that change the browser as Chromium would

  /// Adds a tab at `index` (default: the top, as Clair places new tabs) and
  /// returns it. It becomes active if `activate` or if it's the only tab.
  @discardableResult
  func addTab(title: String = "", url: String? = nil, at index: Int = 0, activate: Bool = true) -> FakeTab {
    let tab = FakeTab(id: nextTabID, title: title, url: url)
    nextTabID += 1
    tabs.insert(tab, at: min(index, tabs.count))
    pageViews[tab.tabID] = NSView()
    clairWindow?.tabsDidChange(tabs)
    if activate || tabs.count == 1 {
      setActive(tab.tabID)
    }
    return tab
  }

  /// Replaces a tab's snapshot and posts it.
  func change(_ tab: FakeTab) {
    guard let index = tabs.firstIndex(where: { $0.tabID == tab.tabID }) else { return }
    tabs[index] = tab
    clairWindow?.tabDidChange(tab)
  }

  func moveTab(_ tabID: TabID, to index: Int) {
    guard let from = tabs.firstIndex(where: { $0.tabID == tabID }) else { return }
    let tab = tabs.remove(at: from)
    tabs.insert(tab, at: min(index, tabs.count))
    clairWindow?.tabsDidChange(tabs)
  }

  /// Closes a tab. If it was active, the tab below it becomes active, or the
  /// one above when it was last, as Chromium chooses without an opener.
  func closeTabNow(_ tabID: TabID) {
    guard let index = tabs.firstIndex(where: { $0.tabID == tabID }) else { return }
    tabs.remove(at: index)
    pageViews[tabID] = nil
    clairWindow?.tabsDidChange(tabs)
    if activeTabID == tabID {
      setActive(tabs.isEmpty ? ClairTabIDNone : tabs[min(index, tabs.count - 1)].tabID)
    }
  }

  func setActive(_ tabID: TabID) {
    activeTabID = tabID
    clairWindow?.activeTabDidChange(tabID)
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
    pageViews[tabID]
  }

  func activate(tab tabID: TabID) {
    record("activate \(tabID)")
    if tabs.contains(where: { $0.tabID == tabID }) {
      setActive(tabID)
    }
  }

  func close(tab tabID: TabID) {
    record("close \(tabID)")
    closeTabNow(tabID)
  }

  func closeTabs(below tabID: TabID) {
    record("closeBelow \(tabID)")
    guard let index = tabs.firstIndex(where: { $0.tabID == tabID }) else { return }
    for tab in tabs[(index + 1)...] {
      closeTabNow(tab.tabID)
    }
  }

  func move(tab tabID: TabID, to index: Int) {
    record("move \(tabID) \(index)")
    moveTab(tabID, to: index)
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

  func requestClose() { record("requestClose") }
}

/// A `ClairWindow` test double that records what Chromium tells it.
final class RecordingWindow: NSObject, ClairWindow {
  let pageContainerView = NSView()
  var isSidebarHidden = false
  private(set) var calls: [String] = []
  private(set) var tabs: [any ClairTab] = []
  private(set) var lastTab: (any ClairTab)?

  func tabsDidChange(_ tabs: [any ClairTab]) {
    self.tabs = tabs
    calls.append("tabs \(tabs.map { String($0.tabID) }.joined(separator: ","))")
  }

  func tabDidChange(_ tab: any ClairTab) {
    lastTab = tab
    calls.append("tab \(tab.tabID)")
  }

  func activeTabDidChange(_ tabID: TabID) { calls.append("active \(tabID)") }
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
}
