// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import ClairHost
import Foundation
import Observation

/// What a window hears from `SpacesModel` (add-spaces design D10).
@MainActor
protocol SpacesModelListener: AnyObject {
  /// A Space's tab list changed.
  func spaceTabsDidChange(_ spaceID: SpaceID)
  /// One tab's state changed.
  func spaceTabDidChange(_ tab: any ClairTab)
  /// Spaces were added, removed, renamed, given an icon or reordered.
  func spacesDidChange()
}

/// Every Space and each Space's tabs, as the host's `ClairSpacesObserver`
/// reports them (add-spaces design D10). One per host, app-wide. Views observe
/// `spaces`; windows hear about tab lists as listeners and copy their own rows
/// into their `BrowserWindowModel`, so a tab loading in one window doesn't
/// redraw every sidebar.
@Observable
final class SpacesModel: NSObject, ClairSpacesObserver {
  /// The host it reports and changes, or nil for a model that never changes.
  @ObservationIgnored private let host: (any ClairHost)?

  /// Every Space, in the user's order.
  private(set) var spaces: [any ClairSpace] = []

  /// Each Space's tabs, in its order, as last reported.
  @ObservationIgnored private var tabsBySpace: [SpaceID: [any ClairTab]] = [:]
  @ObservationIgnored private let listeners = NSHashTable<AnyObject>.weakObjects()

  init(host: (any ClairHost)?) {
    self.host = host
    super.init()
    guard let host else { return }
    spaces = host.spaces
    host.addObserver(self)
  }

  /// A model with no host and no Spaces, for a window opened before the
  /// native layer started.
  static let detached = SpacesModel(host: nil)

  func addListener(_ listener: any SpacesModelListener) {
    listeners.add(listener)
  }

  func removeListener(_ listener: any SpacesModelListener) {
    listeners.remove(listener)
  }

  private var allListeners: [any SpacesModelListener] {
    listeners.allObjects.compactMap { $0 as? any SpacesModelListener }
  }

  // MARK: Reading

  /// The tabs of a Space, in its order, across every window.
  func tabs(inSpace spaceID: SpaceID) -> [any ClairTab] {
    if let tabs = tabsBySpace[spaceID] {
      return tabs
    }
    let tabs = host?.tabs(inSpace: spaceID) ?? []
    tabsBySpace[spaceID] = tabs
    return tabs
  }

  /// The tabs of a Space that a window holds, in the Space's order.
  func tabs(inSpace spaceID: SpaceID, browser browserID: BrowserID) -> [any ClairTab] {
    tabs(inSpace: spaceID).filter { $0.browserID == browserID }
  }

  func space(_ spaceID: SpaceID) -> (any ClairSpace)? {
    spaces.first { $0.spaceID == spaceID }
  }

  func index(of spaceID: SpaceID) -> Int? {
    spaces.firstIndex { $0.spaceID == spaceID }
  }

  /// The number of rows a Space has, Peeks left out, in every window.
  func rowCount(inSpace spaceID: SpaceID) -> Int {
    TabListLogic.rowCount(tabs(inSpace: spaceID))
  }

  // MARK: Changing

  // Every change to the Spaces goes through here, so the sidebar, the menu
  // bar and Manage Spaces follow the same rules.

  /// Creates a Space after the last, named `name` without the spaces around
  /// it. Nil when the name is empty.
  @discardableResult
  func createSpace(named name: String, icon: String?) -> SpaceID? {
    host?.createSpace(named: SpacesLogic.cleanName(name), icon: icon)
  }

  /// Renames a Space to `name` without the spaces around it. An empty name,
  /// or the one it has, changes nothing.
  func renameSpace(_ spaceID: SpaceID, to name: String) {
    let name = SpacesLogic.cleanName(name)
    guard !name.isEmpty, let space = space(spaceID), space.name != name else { return }
    host?.renameSpace(spaceID, to: name)
  }

  func setIcon(_ icon: String?, forSpace spaceID: SpaceID) {
    host?.setIcon(icon, forSpace: spaceID)
  }

  func moveSpace(_ spaceID: SpaceID, to index: Int) {
    host?.moveSpace(spaceID, to: index)
  }

  func moveTab(_ tab: TabID, toSpace spaceID: SpaceID) {
    host?.move(tab: tab, toSpace: spaceID)
  }

  /// What deleting a Space takes.
  struct Deletion {
    let space: any ClairSpace
    /// Its rows, in every window.
    let tabCount: Int
    /// Whether to ask first (spaces spec, "Deleting a Space").
    var needsConfirmation: Bool { SpacesLogic.deletionNeedsConfirmation(tabCount: tabCount) }
  }

  /// What deleting `spaceID` takes, or nil when it can't be deleted: the only
  /// Space, or one that's gone.
  func deletion(of spaceID: SpaceID) -> Deletion? {
    guard spaces.count > 1, let space = space(spaceID) else { return nil }
    return Deletion(space: space, tabCount: rowCount(inSpace: spaceID))
  }

  /// Deletes a Space and closes its tabs, without asking; the caller asks
  /// where `deletion(of:)` says to.
  func deleteSpace(_ spaceID: SpaceID) {
    guard deletion(of: spaceID) != nil else { return }
    host?.deleteSpace(spaceID)
  }

  // MARK: ClairSpacesObserver

  func spacesDidChange(_ spaces: [any ClairSpace]) {
    let known = Set(spaces.map(\.spaceID))
    // A deleted Space's list goes, whatever it still holds: the engine tells
    // of the Space before its tabs' closing, and pushes no list for a Space
    // that's gone. Private Spaces of incognito windows were never in `spaces`
    // and stay.
    for space in self.spaces where !known.contains(space.spaceID) {
      tabsBySpace[space.spaceID] = nil
    }
    self.spaces = spaces
    for listener in allListeners {
      listener.spacesDidChange()
    }
  }

  func tabsDidChange(_ tabs: [any ClairTab], inSpace spaceID: SpaceID) {
    tabsBySpace[spaceID] = tabs
    for listener in allListeners {
      listener.spaceTabsDidChange(spaceID)
    }
  }

  func tabDidChange(_ tab: any ClairTab) {
    // A tab that no list has yet arrives with the list that adds it.
    if var tabs = tabsBySpace[tab.spaceID], let index = tabs.firstIndex(where: { $0.tabID == tab.tabID }) {
      tabs[index] = tab
      tabsBySpace[tab.spaceID] = tabs
    }
    for listener in allListeners {
      listener.spaceTabDidChange(tab)
    }
  }
}
