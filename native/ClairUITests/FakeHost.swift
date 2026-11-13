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
  let profileID: ProfileID

  init(id: SpaceID, name: String, icon: String? = nil, profile: ProfileID = FakeHost.defaultProfileID) {
    spaceID = id
    self.name = name
    self.icon = icon
    profileID = profile
  }

  /// A copy with some fields changed, as the engine posts after a change.
  func with(name: String? = nil, icon: String?? = nil, profile: ProfileID? = nil) -> FakeSpace {
    FakeSpace(id: spaceID, name: name ?? self.name, icon: icon ?? self.icon, profile: profile ?? profileID)
  }
}

/// A stand-in for a profile snapshot.
final class FakeProfile: NSObject, ClairProfile {
  let profileID: ProfileID
  let name: String

  init(id: ProfileID, name: String) {
    profileID = id
    self.name = name
  }
}

/// A stand-in for Chromium's implementation of `ClairHost`. It keeps the
/// Spaces and each Space's tab list, as `ClairSpaceStore` and `ClairSpaceTabs`
/// do (add-spaces design D1, D2), and the profiles, as `ClairProfiles` does
/// (add-profiles design D1), and tells its observers at once, in the order
/// the engine guarantees: a Space's list before a window hears of the active
/// tab.
///
/// A `FakeBrowser` stands for what the user sees as one window, which in the
/// engine is a group of browsers, one per profile (add-profiles design D3):
/// it shows a Space of any profile. A tab reopened in another profile gets a
/// new ID, as a new tab in Chromium does (D9).
final class FakeHost: NSObject, ClairHost {
  let chromiumVersion: String
  let ungoogledChromiumVersion: String
  var blockers: RelaunchBlockers = []
  private(set) var relaunchCount = 0
  private(set) var updateWillInstallOnQuitCount = 0

  /// The first Space, which a new host has alone.
  static let homeID: SpaceID = "home"
  /// The default profile, which a new host has alone.
  static let defaultProfileID: ProfileID = "Default"

  private(set) var spaces: [any ClairSpace] = [FakeSpace(id: FakeHost.homeID, name: "Home")]
  private(set) var profiles: [any ClairProfile] = [FakeProfile(id: FakeHost.defaultProfileID, name: "Default")]
  private var nextProfile = 1
  /// Whether -createProfile(named:completion:) answers at once, as when the
  /// profile is created quickly; otherwise `finishCreatingProfiles()` does.
  var createsProfilesAtOnce = true
  private var pendingProfileCompletions: [() -> Void] = []
  /// Each profile's download folder and whether it asks where to save.
  private(set) var downloadSettings: [ProfileID: (directory: URL, asks: Bool)] = [:]
  var warnsBeforeQuitting = true
  private(set) var openedURLsInProfiles: [(url: URL, profileID: ProfileID)] = []
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

  /// The profile a Space uses, or nil for an unknown Space.
  func profile(ofSpace spaceID: SpaceID) -> ProfileID? {
    spaces.first { $0.spaceID == spaceID }?.profileID
  }

  /// Adds a profile named `name` and returns its ID, as the engine would for
  /// -createProfileNamed:completion:.
  @discardableResult
  func addProfile(_ name: String) -> ProfileID {
    var created: ProfileID?
    let atOnce = createsProfilesAtOnce
    createsProfilesAtOnce = true
    createProfile(named: name) { created = $0 }
    createsProfilesAtOnce = atOnce
    return created ?? ""
  }

  /// Answers the -createProfile calls waiting, as Chromium does once the
  /// profiles exist.
  func finishCreatingProfiles() {
    let completions = pendingProfileCompletions
    pendingProfileCompletions = []
    for completion in completions {
      completion()
    }
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

  private func profilesChanged() {
    for observer in allObservers {
      observer.profilesDidChange(profiles)
    }
  }

  // MARK: ClairHost: Spaces

  func tabs(inSpace spaceID: SpaceID) -> [any ClairTab] {
    list(spaceID)
  }

  func addObserver(_ observer: any ClairSpacesObserver) {
    observers.add(observer)
  }

  func createSpace(named name: String, icon: String?, profile profileID: ProfileID) -> SpaceID? {
    commands.append(profileID == Self.defaultProfileID ? "create \(name)" : "create \(name) \(profileID)")
    guard !name.isEmpty, isProfile(profileID) else { return nil }
    let spaceID = "space-\(nextSpace)"
    nextSpace += 1
    spaces.append(FakeSpace(id: spaceID, name: name, icon: icon, profile: profileID))
    spacesChanged()
    return spaceID
  }

  /// Creates a Space on the default profile, as the tests that predate
  /// profiles do.
  func createSpace(named name: String, icon: String?) -> SpaceID? {
    createSpace(named: name, icon: icon, profile: Self.defaultProfileID)
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
    update(spaceID) { $0.with(name: name) }
  }

  func setIcon(_ icon: String?, forSpace spaceID: SpaceID) {
    commands.append("icon \(spaceID) \(icon ?? "-")")
    update(spaceID) { $0.with(icon: .some(icon)) }
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
    guard isSpace(spaceID), var tab = tab(tabID), isSpace(tab.spaceID), let browser = browser(tab.browserID)
    else { return }
    // A Peek moves with its parent.
    if tab.peekParentID != ClairTabIDNone, let parent = self.tab(tab.peekParentID) {
      tab = parent
    }
    guard tab.spaceID != spaceID else { return }
    operation {
      let wasActive = browser.isActiveRow(tab.tabID)
      if profile(ofSpace: tab.spaceID) != profile(ofSpace: spaceID) {
        // add-profiles D9: a page can't change profile; it reopens at its URL
        // at the top of the other Space, without its Peek.
        let reopened = reopen(tab, inSpace: spaceID, at: 0, by: browser)
        if wasActive {
          browser.setActive(reopened.tabID)
        }
        browser.closeReopened(tab.tabID)
      } else {
        // The tab and its Peek go to the top of the other list (add-spaces D7).
        let source = tab.spaceID
        let family = list(source).filter { $0.tabID == tab.tabID || ($0.peekParentID == tab.tabID && tab.peekID == $0.tabID) }
        let moved = family.map { $0.with(spaceID: spaceID) }
        setList(list(source).filter { candidate in !family.contains { $0.tabID == candidate.tabID } }, inSpace: source)
        setList(moved + list(spaceID), inSpace: spaceID)
        // add-profiles D9: the window follows its active tab; a window with a
        // still of it picks its next tab, as if it had closed there.
        if wasActive {
          browser.followActiveTab()
        }
        tabClosed(tab.tabID)
      }
    }
  }

  /// D9: opens `tab`'s URL as a new tab of `spaceID` at `index` in its list,
  /// in the window holding it, and returns it.
  private func reopen(_ tab: FakeTab, inSpace spaceID: SpaceID, at index: Int, by browser: FakeBrowser) -> FakeTab {
    let reopened = FakeTab(
      id: newTabID(), title: tab.title, url: tab.url?.absoluteString, spaceID: spaceID, browserID: browser.browserID)
    pageViews[reopened.tabID] = NSView()
    var tabs = list(spaceID)
    tabs.insert(reopened, at: min(index, tabs.count))
    setList(tabs, inSpace: spaceID)
    return reopened
  }

  // MARK: ClairHost: Profiles (add-profiles design D1, D9, D11)

  func isProfile(_ profileID: ProfileID) -> Bool {
    profiles.contains { $0.profileID == profileID }
  }

  func createProfile(named name: String, completion: @escaping (ProfileID?) -> Void) {
    commands.append("createProfile \(name)")
    let name = SpacesLogic.cleanName(name)
    guard !name.isEmpty else {
      completion(nil)
      return
    }
    let create = { [weak self] in
      guard let self else { return }
      let profileID = "Profile \(nextProfile)"
      nextProfile += 1
      profiles.append(FakeProfile(id: profileID, name: name))
      profilesChanged()
      completion(profileID)
    }
    if createsProfilesAtOnce {
      create()
    } else {
      pendingProfileCompletions.append(create)
    }
  }

  func renameProfile(_ profileID: ProfileID, to name: String) {
    commands.append("renameProfile \(profileID) \(name)")
    let name = SpacesLogic.cleanName(name)
    guard !name.isEmpty, let index = profiles.firstIndex(where: { $0.profileID == profileID }) else { return }
    profiles[index] = FakeProfile(id: profileID, name: name)
    profilesChanged()
  }

  func deleteProfile(_ profileID: ProfileID) {
    commands.append("deleteProfile \(profileID)")
    // D7: only a profile no Space uses.
    guard !spaces.contains(where: { $0.profileID == profileID }) else { return }
    profiles.removeAll { $0.profileID == profileID }
    downloadSettings[profileID] = nil
    profilesChanged()
  }

  func setProfile(_ profileID: ProfileID, forSpace spaceID: SpaceID) {
    commands.append("setProfile \(spaceID) \(profileID)")
    guard isProfile(profileID), let current = profile(ofSpace: spaceID), current != profileID else { return }
    operation {
      update(spaceID) { $0.with(profile: profileID) }
      // D9: each tab reopens at its URL, in order, without its Peek; the tab
      // reopened from a window's active row becomes its active tab.
      let rows = TabListLogic.rows(list(spaceID)).compactMap { tab($0.tabID) }
      for (index, row) in rows.enumerated() {
        guard let browser = browser(row.browserID) else { continue }
        let wasActive = browser.isActiveRow(row.tabID)
        let reopened = reopen(row, inSpace: spaceID, at: index, by: browser)
        if wasActive {
          browser.setActive(reopened.tabID)
        }
        browser.closeReopened(row.tabID)
      }
    }
  }

  private static let downloadsFolder = URL(fileURLWithPath: "/Users/test/Downloads", isDirectory: true)

  func downloadSettings(forProfile profileID: ProfileID, completion: @escaping (URL?, Bool) -> Void) {
    guard isProfile(profileID) else {
      completion(nil, false)
      return
    }
    let settings = downloadSettings[profileID] ?? (Self.downloadsFolder, false)
    completion(settings.directory, settings.asks)
  }

  func setDownloadDirectory(_ directory: URL, forProfile profileID: ProfileID) {
    commands.append("downloadDirectory \(profileID) \(directory.path)")
    guard isProfile(profileID) else { return }
    downloadSettings[profileID] = (directory, false)
  }

  func setAsksWhereToSave(_ asks: Bool, forProfile profileID: ProfileID) {
    commands.append("asksWhereToSave \(profileID) \(asks)")
    guard isProfile(profileID) else { return }
    let directory = downloadSettings[profileID]?.directory ?? Self.downloadsFolder
    downloadSettings[profileID] = (directory, asks)
  }

  func open(_ url: URL, inProfile profileID: ProfileID) {
    openedURLsInProfiles.append((url, profileID))
  }
}
