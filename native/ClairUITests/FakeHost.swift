// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Foundation

@testable import ClairUI

/// A stand-in for a Space snapshot.
final class FakeSpace: NSObject, ClairSpace {
  let spaceID: SpaceID
  let name: String
  let icon: String?

  init(id: SpaceID, name: String, icon: String? = nil) {
    spaceID = id
    self.name = name
    self.icon = icon
  }
}

/// A stand-in for Chromium's implementation of `ClairHost`. It keeps the
/// Spaces and each Space's tab list, as `ClairSpaceStore` and `ClairSpaceTabs`
/// do (add-spaces design D1, D2), and tells its observers at once, in the
/// order the engine guarantees: a Space's list before a window hears of the
/// active tab.
final class FakeHost: NSObject, ClairHost {
  let chromiumVersion: String
  let ungoogledChromiumVersion: String
  var blockers: RelaunchBlockers = []
  private(set) var relaunchCount = 0
  private(set) var updateWillInstallOnQuitCount = 0

  /// The first Space, which a new host has alone.
  static let homeID: SpaceID = "home"

  private(set) var spaces: [any ClairSpace] = [FakeSpace(id: FakeHost.homeID, name: "Home")]
  /// Each Space's tabs, in order, private Spaces of incognito windows
  /// included.
  private var lists: [SpaceID: [FakeTab]] = [:]
  private let observers = NSHashTable<AnyObject>.weakObjects()
  private let browsers = NSHashTable<FakeBrowser>.weakObjects()
  private var nextSpace = 1
  /// The Space last shown, which a new window shows (D3).
  var lastShownSpaceID: SpaceID = FakeHost.homeID
  /// Every Space command ClairUI sent, in order, such as "rename work Work".
  private(set) var commands: [String] = []

  /// The model ClairUI keeps for this host, as `NativeLayer` keeps one.
  private(set) lazy var spacesModel = SpacesModel(host: self)

  init(chromiumVersion: String = "156.0.8078.73", ungoogledChromiumVersion: String = "156.0.8078.73-1") {
    self.chromiumVersion = chromiumVersion
    self.ungoogledChromiumVersion = ungoogledChromiumVersion
  }

  func silentRelaunchBlockers() -> RelaunchBlockers {
    blockers
  }

  func relaunch() {
    relaunchCount += 1
  }

  func updateWillInstallOnQuit() {
    updateWillInstallOnQuitCount += 1
  }

  private(set) var openedURLs: [URL] = []

  func open(_ url: URL) {
    openedURLs.append(url)
  }

  // MARK: Helpers for tests and FakeBrowser

  /// Adds Spaces named `names` after the existing ones and returns their IDs,
  /// as the engine would for -createSpaceNamed:icon:.
  @discardableResult
  func addSpaces(_ names: String...) -> [SpaceID] {
    names.compactMap { createSpace(named: $0, icon: nil) }
  }

  func register(_ browser: FakeBrowser) {
    browsers.add(browser)
    activated(browser)
  }

  // MARK: Tabs shared across windows (share-tabs-across-windows D1 to D4)

  /// Every tab's page view, which moves with it between windows.
  var pageViews: [TabID: NSView] = [:]
  /// Unique across browsers, as Chromium's tab handles are.
  private var nextTabID: TabID = 1
  /// When each tab was last active, as a count.
  private var stamps: [TabID: Int] = [:]
  private var clock = 0
  /// Browsers, most recently active first.
  private var activationOrder: [BrowserID] = []

  func newTabID() -> TabID {
    defer { nextTabID += 1 }
    return nextTabID
  }

  /// A tab became active.
  func stamp(_ tabID: TabID) {
    clock += 1
    stamps[tabID] = clock
  }

  /// When the user last looked at a row or its Peek.
  func lastActive(row: TabID) -> Int {
    let peek = tab(row)?.peekID ?? ClairTabIDNone
    return max(stamps[row] ?? 0, stamps[peek] ?? 0)
  }

  /// Whether a window other than `browser` shows the row.
  func isShown(_ row: TabID, except browser: FakeBrowser) -> Bool {
    guard let tab = tab(row), tab.browserID != browser.browserID, let holder = self.browser(tab.browserID) else {
      return false
    }
    return holder.isActiveRow(row)
  }

  /// A window became the most recently active.
  func activated(_ browser: FakeBrowser) {
    activationOrder.removeAll { $0 == browser.browserID }
    activationOrder.insert(browser.browserID, at: 0)
  }

  /// The most recently active other regular window, open.
  func mostRecentBrowser(except browser: FakeBrowser) -> FakeBrowser? {
    activationOrder.lazy.compactMap { self.browser($0) }.first {
      $0 !== browser && $0.profileKind == .regular && !$0.isClosed
    }
  }

  /// What runs once the current operation is done, as the engine posts it.
  private var posted: [() -> Void] = []
  private var depth = 0

  /// Runs `body` as one operation: what it posts runs once it's done.
  func operation(_ body: () -> Void) {
    depth += 1
    body()
    depth -= 1
    guard depth == 0 else { return }
    while !posted.isEmpty {
      let task = posted.removeFirst()
      depth += 1
      task()
      depth -= 1
    }
  }

  /// D2: `row` stopped showing in its window. Once the current operation is
  /// done, if no window shows it, the most recently active window with a
  /// still of it takes it back, in the Space it shows.
  func giveBack(_ row: TabID) {
    posted.append { [weak self] in self?.giveBackNow(row) }
    if depth == 0 {
      operation {}
    }
  }

  private func giveBackNow(_ row: TabID) {
    guard let tab = tab(row), let holder = browser(tab.browserID), !holder.isActiveRow(row),
      let target = activationOrder.lazy.compactMap({ self.browser($0) }).first(where: {
        $0 !== holder && $0.stillTabID == row
      }), target.shownSpaceID == tab.spaceID
    else { return }
    target.takeBack(row)
  }

  /// A tab closed: a window showing a still of it shows a new tab page.
  func tabClosed(_ tabID: TabID) {
    for browser in allBrowsers where browser.stillTabID == tabID {
      browser.stillTabClosedForHost()
    }
  }

  var allBrowsers: [FakeBrowser] { browsers.allObjects }

  func browser(_ browserID: BrowserID) -> FakeBrowser? {
    browsers.allObjects.first { $0.browserID == browserID }
  }

  func list(_ spaceID: SpaceID) -> [FakeTab] {
    lists[spaceID] ?? []
  }

  func isSpace(_ spaceID: SpaceID) -> Bool {
    spaces.contains { $0.spaceID == spaceID }
  }

  /// The tab with `tabID`, in whichever Space it is.
  func tab(_ tabID: TabID) -> FakeTab? {
    for tabs in lists.values {
      if let tab = tabs.first(where: { $0.tabID == tabID }) {
        return tab
      }
    }
    return nil
  }

  /// Every tab a window holds, in each Space's order, Spaces in order.
  func tabs(ofBrowser browserID: BrowserID) -> [FakeTab] {
    let order = spaces.map(\.spaceID) + lists.keys.filter { !isSpace($0) }.sorted()
    return order.flatMap { list($0).filter { $0.browserID == browserID } }
  }

  /// Replaces a Space's list and tells the observers.
  func setList(_ tabs: [FakeTab], inSpace spaceID: SpaceID) {
    lists[spaceID] = tabs
    for observer in allObservers {
      observer.tabsDidChange(tabs, inSpace: spaceID)
    }
  }

  /// Replaces a tab's snapshot in its list and tells the observers.
  func replace(_ tab: FakeTab) {
    guard var tabs = lists[tab.spaceID], let index = tabs.firstIndex(where: { $0.tabID == tab.tabID }) else {
      return
    }
    tabs[index] = tab
    lists[tab.spaceID] = tabs
    for observer in allObservers {
      observer.tabDidChange(tab)
    }
  }

  /// Replaces a tab's snapshot without telling anyone, as when a Peek's
  /// parent changes in the same list update.
  func replaceQuietly(_ tab: FakeTab) {
    guard var tabs = lists[tab.spaceID], let index = tabs.firstIndex(where: { $0.tabID == tab.tabID }) else {
      return
    }
    tabs[index] = tab
    lists[tab.spaceID] = tabs
  }

  private var allObservers: [any ClairSpacesObserver] {
    observers.allObjects.compactMap { $0 as? any ClairSpacesObserver }
  }

  private func spacesChanged() {
    for observer in allObservers {
      observer.spacesDidChange(spaces)
    }
  }

  // MARK: ClairHost: Spaces

  func tabs(inSpace spaceID: SpaceID) -> [any ClairTab] {
    list(spaceID)
  }

  func addObserver(_ observer: any ClairSpacesObserver) {
    observers.add(observer)
  }

  func createSpace(named name: String, icon: String?) -> SpaceID? {
    commands.append("create \(name)")
    guard !name.isEmpty else { return nil }
    let spaceID = "space-\(nextSpace)"
    nextSpace += 1
    spaces.append(FakeSpace(id: spaceID, name: name, icon: icon))
    spacesChanged()
    return spaceID
  }

  private func update(_ spaceID: SpaceID, _ change: (FakeSpace) -> FakeSpace) {
    guard let index = spaces.firstIndex(where: { $0.spaceID == spaceID }), let space = spaces[index] as? FakeSpace
    else { return }
    spaces[index] = change(space)
    spacesChanged()
  }

  func renameSpace(_ spaceID: SpaceID, to name: String) {
    commands.append("rename \(spaceID) \(name)")
    guard !name.isEmpty else { return }
    update(spaceID) { FakeSpace(id: $0.spaceID, name: name, icon: $0.icon) }
  }

  func setIcon(_ icon: String?, forSpace spaceID: SpaceID) {
    commands.append("icon \(spaceID) \(icon ?? "-")")
    update(spaceID) { FakeSpace(id: $0.spaceID, name: $0.name, icon: icon) }
  }

  func moveSpace(_ spaceID: SpaceID, to index: Int) {
    commands.append("moveSpace \(spaceID) \(index)")
    guard let from = spaces.firstIndex(where: { $0.spaceID == spaceID }) else { return }
    let space = spaces.remove(at: from)
    spaces.insert(space, at: max(0, min(index, spaces.count)))
    spacesChanged()
  }

  func deleteSpace(_ spaceID: SpaceID) {
    commands.append("delete \(spaceID)")
    guard spaces.count > 1, let index = spaces.firstIndex(where: { $0.spaceID == spaceID }) else { return }
    // D7: each window showing it shows the Space before it, or after it.
    let neighbour = spaces[index > 0 ? index - 1 : 1].spaceID
    for browser in allBrowsers where browser.shownSpaceID == spaceID {
      browser.showSpace(neighbour)
    }
    for tab in list(spaceID) {
      browser(tab.browserID)?.closeTabNow(tab.tabID)
    }
    spaces.remove(at: index)
    lists[spaceID] = nil
    if lastShownSpaceID == spaceID {
      lastShownSpaceID = neighbour
    }
    spacesChanged()
  }

  func move(tab tabID: TabID, toSpace spaceID: SpaceID) {
    commands.append("moveToSpace \(tabID) \(spaceID)")
    guard isSpace(spaceID), let tab = tab(tabID), tab.spaceID != spaceID, isSpace(tab.spaceID),
      let browser = browser(tab.browserID)
    else { return }
    browser.leaveBeforeMoving(tabID)
    // The tab and its Peek go to the top of the other list (D7).
    let source = tab.spaceID
    let family = list(source).filter { $0.tabID == tabID || ($0.peekParentID == tabID && tab.peekID == $0.tabID) }
    let moved = family.map { $0.with(spaceID: spaceID) }
    setList(list(source).filter { candidate in !family.contains { $0.tabID == candidate.tabID } }, inSpace: source)
    setList(moved + list(spaceID), inSpace: spaceID)
  }
}
