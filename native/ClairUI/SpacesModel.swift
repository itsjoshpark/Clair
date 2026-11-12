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
  /// The host it reports, or nil for a model that never changes.
  @ObservationIgnored let host: (any ClairHost)?

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

  // MARK: ClairSpacesObserver

  func spacesDidChange(_ spaces: [any ClairSpace]) {
    self.spaces = spaces
    let known = Set(spaces.map(\.spaceID))
    // A deleted Space's list goes; private Spaces of incognito windows stay.
    for (spaceID, tabs) in tabsBySpace where tabs.isEmpty && !known.contains(spaceID) {
      tabsBySpace[spaceID] = nil
    }
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
