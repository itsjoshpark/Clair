// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Foundation
import Testing

@testable import ClairUI

/// A window on a fake host with Spaces, as ClairUI sees one (add-spaces D10).
@MainActor
func spacesWindow(
  _ names: [String] = [], tabs: Int = 1, suite: String = #function
) -> (FakeHost, FakeBrowser, BrowserWindowController) {
  let host = FakeHost()
  host.addSpaces(names)
  let browser = FakeBrowser(host: host)
  for index in 0..<tabs {
    browser.addTab(title: "Tab \(index)", url: "https://\(index).example/", at: index, activate: index == 0)
  }
  let controller = BrowserWindowController(
    browser: browser, spaces: browser.spaces, preferences: SidebarPreferences(defaults: UserDefaults(suiteName: suite)!))
  browser.clairWindow = controller
  return (host, browser, controller)
}

/// An incognito window on a fake host, as `spacesWindow` makes a regular one.
@MainActor
func incognitoWindow(tabs: Int = 1, suite: String = #function) -> (FakeHost, FakeBrowser, BrowserWindowController) {
  let host = FakeHost()
  let browser = FakeBrowser(host: host, profileKind: .incognito)
  for index in 0..<tabs {
    browser.addTab(title: "Tab \(index)", url: "https://\(index).example/", at: index, activate: index == 0)
  }
  let controller = BrowserWindowController(
    browser: browser, spaces: browser.spaces, preferences: SidebarPreferences(defaults: UserDefaults(suiteName: suite)!))
  browser.clairWindow = controller
  return (host, browser, controller)
}

extension FakeHost {
  @discardableResult
  func addSpaces(_ names: [String]) -> [SpaceID] {
    names.compactMap { createSpace(named: $0, icon: nil) }
  }
}

@MainActor
struct SpacesLogicTests {
  let spaces: [any ClairSpace] = [
    FakeSpace(id: "a", name: "Home"), FakeSpace(id: "b", name: "Work", icon: "💼"), FakeSpace(id: "c", name: "Travel"),
  ]

  @Test func nextAndPreviousWrapAround() {
    #expect(SpacesLogic.neighbour(of: "c", by: 1, in: spaces) == "a")
    #expect(SpacesLogic.neighbour(of: "a", by: -1, in: spaces) == "c")
    #expect(SpacesLogic.neighbour(of: "a", by: 1, in: spaces) == "b")
    #expect(SpacesLogic.neighbour(of: "a", by: 1, in: [spaces[0]]) == nil)
  }

  @Test func controlNumberCountsFromOne() {
    #expect(SpacesLogic.space(number: 1, in: spaces) == "a")
    #expect(SpacesLogic.space(number: 3, in: spaces) == "c")
    #expect(SpacesLogic.space(number: 4, in: spaces) == nil)
    #expect(SpacesLogic.space(number: 0, in: spaces) == nil)
  }

  @Test func aLaterSpaceSlidesInFromTheTrailingSide() {
    #expect(SpacesLogic.slidesFromTrailing(to: "b", from: "a", in: spaces))
    #expect(!SpacesLogic.slidesFromTrailing(to: "a", from: "c", in: spaces))
  }

  // MARK: The switcher (spaces spec, "Sidebar footer")

  @Test func oneSpaceHasNoSwitcher() {
    #expect(SpacesLogic.switcherItems([spaces[0]], shown: "a").isEmpty)
  }

  @Test func twoSpacesHaveTwoItemsTheShownOneCurrent() {
    let items = SpacesLogic.switcherItems(Array(spaces.prefix(2)), shown: "a")
    #expect(items.map(\.spaceID) == ["a", "b"])
    #expect(items.map(\.isCurrent) == [true, false])
    #expect(items.map(\.icon) == [nil, "💼"])
    #expect(items.map(\.identifier) == ["clair.space.1", "clair.space.2"])
  }

  @Test func tenSpacesHaveTenItemsInOrder() {
    let ten: [any ClairSpace] = (1...10).map { FakeSpace(id: "s\($0)", name: "Space \($0)") }
    let items = SpacesLogic.switcherItems(ten, shown: "s7")
    #expect(items.count == 10)
    #expect(items.map(\.spaceID) == ten.map(\.spaceID))
    #expect(items.filter(\.isCurrent).map(\.spaceID) == ["s7"])
    #expect(items.last?.identifier == "clair.space.10")
  }

  @Test func aDraggedSpaceLandsInTheNearestSlot() {
    // Five items 34 pt apart: half a pitch or more moves one slot.
    #expect(SpacesLogic.dragTarget(from: 4, translation: -136, pitch: 34, count: 5) == 0)
    #expect(SpacesLogic.dragTarget(from: 0, translation: 18, pitch: 34, count: 5) == 1)
    #expect(SpacesLogic.dragTarget(from: 0, translation: 16, pitch: 34, count: 5) == 0)
    #expect(SpacesLogic.dragTarget(from: 2, translation: 500, pitch: 34, count: 5) == 4)
    #expect(SpacesLogic.dragTarget(from: 2, translation: -500, pitch: 34, count: 5) == 0)
  }

  // MARK: The header's menu (spaces spec, "Space header", "Deleting a Space")

  @Test func headerMenuOffersArcsItems() {
    let titles = SpacesLogic.headerMenu(spaceCount: 2).map { $0?.title }
    #expect(
      titles == ["Change Space Icon…", "Rename Space…", "Set Profile", nil, "Manage Spaces…", nil, "Delete Space"])
  }

  @Test func deleteSpaceIsOffForTheOnlySpace() {
    let delete = { (count: Int) in SpacesLogic.headerMenu(spaceCount: count).compactMap { $0 }.first { $0.command == .delete } }
    #expect(delete(1)?.isEnabled == false)
    #expect(delete(2)?.isEnabled == true)
    let others = SpacesLogic.headerMenu(spaceCount: 1).compactMap { $0 }.filter { $0.command != .delete }
    #expect(others.allSatisfy { $0.isEnabled })
  }

  // MARK: Move to Space (add-spaces D7)

  @Test func moveToSpaceListsEveryOtherSpace() {
    #expect(SpacesLogic.moveTargets(from: "b", in: spaces).map(\.spaceID) == ["a", "c"])
    #expect(SpacesLogic.moveTargets(from: "a", in: [spaces[0]]).isEmpty)
    #expect(SpacesLogic.label(of: spaces[1]) == "💼 Work")
    #expect(SpacesLogic.label(of: spaces[0]) == "Home")
  }

  @Test func tabRowMenuHasMoveToSpaceWithOtherSpaces() {
    let row = TabRow(
      tab: FakeTab(id: 1, title: "One"), isActive: false, isWindowKey: true,
      moveTargets: SpacesLogic.moveTargets(from: "a", in: spaces))
    let move = row.menuItems.first { $0.title == "Move to Space" }
    guard case .submenu(_, let items) = move else {
      Issue.record("The row's menu has no Move to Space")
      return
    }
    #expect(items.map(\.title) == ["💼 Work", "Travel"])
  }

  @Test func tabRowMenuHasNoMoveToSpaceWithOneSpace() {
    let row = TabRow(tab: FakeTab(id: 1, title: "One"), isActive: false, isWindowKey: true, moveTargets: [])
    #expect(!row.menuItems.contains { $0.title == "Move to Space" })
    #expect(row.menuItems.compactMap(\.title) == ["Copy Link", "Duplicate", "Mute", "Close Tab", "Close Tabs Below"])
  }

  // MARK: Names and the form

  @Test func newSpaceFormNeedsAName() {
    var form = NewSpaceFormState()
    #expect(!form.canCreate)
    form.name = "   "
    #expect(!form.canCreate)
    form.name = " Work "
    #expect(form.canCreate)
    #expect(SpacesLogic.cleanName(form.name) == "Work")
  }

  @Test func deletingAsksOnlyForASpaceWithTabs() {
    #expect(!SpacesLogic.deletionNeedsConfirmation(tabCount: 0))
    #expect(SpacesLogic.deletionNeedsConfirmation(tabCount: 1))
    #expect(SpacesLogic.deletionMessage(tabCount: 1) == "Its tab will close.")
    #expect(SpacesLogic.deletionMessage(tabCount: 3) == "Its 3 tabs will close.")
  }
}

/// The icon field's helper (add-spaces D10).
struct SpaceIconTests {
  @Test func keepsTheFirstEmojiOfMixedText() {
    #expect(SpaceIcon.edit(for: "ab📚cd✈️") == .set("📚"))
    #expect(SpaceIcon.edit(for: "📚✈️") == .set("📚"))
  }

  @Test func keepsSkinTonesAndJoinedSequences() {
    #expect(SpaceIcon.edit(for: "👍🏽") == .set("👍🏽"))
    #expect(SpaceIcon.edit(for: "x👩‍💻") == .set("👩‍💻"))
    #expect(SpaceIcon.edit(for: "✈️") == .set("✈️"))
    #expect(SpaceIcon.edit(for: "🏳️‍🌈!") == .set("🏳️‍🌈"))
  }

  @Test func textWithNoEmojiChangesNothing() {
    #expect(SpaceIcon.edit(for: "a") == .unchanged)
    #expect(SpaceIcon.edit(for: "123 #") == .unchanged)
  }

  @Test func emptyClears() {
    #expect(SpaceIcon.edit(for: "") == .clear)
  }

  /// A Space that has an icon keeps its field, and its coordinator, between
  /// edits: each edit ends once, also one that changes nothing.
  @MainActor
  @Test func everyEditEndsOnce() {
    var ends = 0
    let field = SpaceIconField(icon: "📚", isEditing: true, onChange: { _ in }, onEnd: { ends += 1 })
    let coordinator = field.makeCoordinator()
    let ended = Notification(name: NSControl.textDidEndEditingNotification)
    coordinator.begin()
    coordinator.controlTextDidEndEditing(ended)
    coordinator.controlTextDidEndEditing(ended)
    #expect(ends == 1)
    coordinator.begin()
    coordinator.controlTextDidEndEditing(ended)
    #expect(ends == 2)
  }
}

/// The Spaces' one model and its changes (add-spaces D10).
@MainActor
struct SpacesModelTests {
  @Test func renamingCleansTheNameAndSkipsItsOwn() {
    let host = FakeHost()
    let model = SpacesModel(host: host)
    model.renameSpace(FakeHost.homeID, to: "  ")
    model.renameSpace(FakeHost.homeID, to: " Home ")
    #expect(!host.commands.contains { $0.hasPrefix("rename") })
    model.renameSpace(FakeHost.homeID, to: " Research ")
    #expect(host.spaces[0].name == "Research")
    #expect(model.spaces[0].name == "Research")
  }

  @Test func creatingCleansTheName() {
    let host = FakeHost()
    let model = SpacesModel(host: host)
    #expect(model.createSpace(named: "   ", icon: nil, profile: FakeHost.defaultProfileID) == nil)
    let work = model.createSpace(named: " Work ", icon: "💼", profile: FakeHost.defaultProfileID)
    #expect(work == host.spaces[1].spaceID)
    #expect(host.spaces[1].name == "Work")
  }

  @Test func deletionTellsWhetherToAsk() throws {
    let (host, browser, controller) = spacesWindow()
    let model = controller.model.spaces
    #expect(model.deletion(of: FakeHost.homeID) == nil)
    let work = try #require(model.createSpace(named: "Work", icon: nil, profile: FakeHost.defaultProfileID))
    #expect(model.deletion(of: "gone") == nil)
    #expect(try #require(model.deletion(of: work)).needsConfirmation == false)
    browser.showSpace(work)
    let deletion = try #require(model.deletion(of: work))
    #expect(deletion.space.name == "Work")
    #expect(deletion.tabCount == 1)
    #expect(deletion.needsConfirmation)
    model.deleteSpace(work)
    #expect(host.spaces.map(\.name) == ["Home"])
    model.deleteSpace(FakeHost.homeID)
    #expect(host.spaces.count == 1)
  }

  /// The engine tells of a deleted Space while its tabs are still closing,
  /// and pushes no list for it afterwards.
  @Test func aDeletedSpacesTabsAreDropped() {
    let (host, browser, _) = spacesWindow(["Work"])
    let work = host.spaces[1].spaceID
    let model = SpacesModel(host: host)
    model.tabsDidChange(browser.allTabs, inSpace: work)
    model.tabsDidChange(browser.allTabs, inSpace: "private")
    #expect(model.tabs(inSpace: work).count == 1)
    model.spacesDidChange([host.spaces[0]])
    #expect(model.tabs(inSpace: work).isEmpty)
    // An incognito window's Space was never one of the user's.
    #expect(model.tabs(inSpace: "private").count == 1)
  }
}

/// The window's Space actions against the fake host (add-spaces D3, D7, D10).
@MainActor
struct SpaceActionsTests {
  @Test func theWindowListsOnlyItsSpacesTabs() {
    let (host, browser, controller) = spacesWindow(["Work"], tabs: 2)
    let work = host.spaces[1].spaceID
    controller.showSpace(work)
    #expect(controller.model.shownSpaceID == work)
    #expect(controller.model.tabs.count == 1)
    #expect(controller.model.tabs.first?.isNewTabPage == true)
    browser.addTab(title: "Work tab")
    #expect(controller.model.tabs.map(\.title) == ["Work tab", ""])
    controller.showSpace(FakeHost.homeID)
    #expect(controller.model.tabs.map(\.title) == ["Tab 0", "Tab 1"])
  }

  /// An incognito window's tabs stay its own (share-tabs-across-windows D1);
  /// a regular window lists every window's, in SharedTabsTests.
  @Test func anotherWindowsTabsAreLeftOut() {
    let (host, _, controller) = incognitoWindow(tabs: 1)
    let other = FakeBrowser(host: host, profileKind: .incognito)
    other.addTab(title: "Elsewhere")
    #expect(host.list(controller.model.shownSpaceID).count == 2)
    #expect(controller.model.tabs.map(\.title) == ["Tab 0"])
  }

  @Test func showingASpaceWithNoTabsOpensTheCommandBar() {
    let (host, _, controller) = spacesWindow(["Work"])
    controller.showSpace(host.spaces[1].spaceID)
    #expect(controller.model.commandBar?.mode == .currentTab)
  }

  @Test func nextAndPreviousSpaceWrap() {
    let (host, browser, controller) = spacesWindow(["Work", "Travel"])
    controller.showSpace(step: -1)
    #expect(browser.shownSpaceID == host.spaces[2].spaceID)
    controller.showSpace(step: 1)
    #expect(browser.shownSpaceID == FakeHost.homeID)
    controller.showSpace(number: 2)
    #expect(browser.shownSpaceID == host.spaces[1].spaceID)
  }

  @Test func creatingASpaceShowsIt() {
    let (host, browser, controller) = spacesWindow()
    controller.beginNewSpace()
    #expect(controller.model.newSpaceForm != nil)
    controller.createSpace(named: " Work ", icon: "💼", profile: nil)
    #expect(controller.model.newSpaceForm == nil)
    #expect(host.spaces.map(\.name) == ["Home", "Work"])
    #expect(host.spaces.last?.icon == "💼")
    #expect(browser.shownSpaceID == host.spaces[1].spaceID)
  }

  @Test func cancellingCreatesNothing() {
    let (host, browser, controller) = spacesWindow()
    controller.beginNewSpace()
    controller.model.newSpaceForm?.name = "Work"
    controller.cancelNewSpace()
    #expect(controller.model.newSpaceForm == nil)
    #expect(host.spaces.count == 1)
    #expect(browser.shownSpaceID == FakeHost.homeID)
  }

  @Test func renamingIgnoresAnEmptyName() {
    let (host, _, controller) = spacesWindow()
    controller.beginRenamingSpace()
    #expect(controller.model.spaceHeaderEdit == .renaming)
    controller.renameSpace(FakeHost.homeID, to: "  ")
    #expect(host.spaces[0].name == "Home")
    controller.renameSpace(FakeHost.homeID, to: "Research")
    #expect(host.spaces[0].name == "Research")
    #expect(controller.model.shownSpace?.name == "Research")
  }

  @Test func deletingAnEmptySpaceSkipsTheConfirmation() {
    let (host, _, controller) = spacesWindow(["Work"])
    let work = host.spaces[1].spaceID
    controller.deleteSpace(work)
    #expect(controller.dialogs.showing == nil)
    #expect(host.spaces.map(\.name) == ["Home"])
  }

  @Test func deletingASpaceWithTabsAsksFirst() throws {
    let (host, browser, controller) = spacesWindow(["Work"])
    let work = host.spaces[1].spaceID
    browser.showSpace(work)
    browser.addTab(title: "Work tab")
    controller.deleteSpace(work)
    let dialog = try #require(controller.dialogs.showing)
    #expect(dialog.page.title == "Delete the “Work” Space?")
    #expect(dialog.page.message == "Its 2 tabs will close.")
    #expect(host.spaces.count == 2)
    dialog.answer(.accepted)
    #expect(host.spaces.map(\.name) == ["Home"])
    #expect(browser.shownSpaceID == FakeHost.homeID)
    #expect(browser.allTabs.allSatisfy { $0.spaceID == FakeHost.homeID })
  }

  @Test func theOnlySpaceIsntDeleted() {
    let (host, _, controller) = spacesWindow()
    controller.deleteSpace(FakeHost.homeID)
    #expect(controller.dialogs.showing == nil)
    #expect(host.spaces.count == 1)
  }

  /// add-profiles D9: the window follows its active tab, with no notice.
  @Test func movingTheActiveTabShowsItsNewSpace() {
    let (host, browser, controller) = spacesWindow(["Work"], tabs: 3)
    let work = host.spaces[1].spaceID
    let active = browser.activeTabID
    controller.moveTab(active, toSpace: work)
    #expect(browser.shownSpaceID == work)
    #expect(controller.model.shownSpaceID == work)
    #expect(browser.activeTabID == active)
    #expect(host.list(work).first?.tabID == active)
    #expect(controller.model.tabs.first?.tabID == active)
    #expect(controller.model.notice.notice == nil)
  }

  /// Moving any other tab leaves the window, and says where the tab went.
  @Test func movingAnotherTabShowsANotice() {
    let (host, browser, controller) = spacesWindow(["Work"], tabs: 3)
    let work = host.spaces[1].spaceID
    let active = browser.activeTabID
    let other = try! #require(controller.model.tabs.first { $0.tabID != active }).tabID
    controller.moveTab(other, toSpace: work)
    #expect(browser.shownSpaceID == FakeHost.homeID)
    #expect(browser.activeTabID == active)
    #expect(host.list(work).first?.tabID == other)
    #expect(controller.model.notice.notice?.text == "Tab was moved to Work")
  }

  /// In an incognito window, which lists its own tabs only.
  @Test func draggingARowCountsTheWindowsTabsOnly() {
    let (host, browser, controller) = incognitoWindow(tabs: 2)
    let other = FakeBrowser(host: host, profileKind: .incognito)
    other.addTab(title: "Elsewhere", at: 1, activate: false)
    // The Space's list: Tab 0, Tab 1, Elsewhere, wherever the other window
    // put its tab; this window's rows are Tab 0 and Tab 1.
    let first = browser.tabs[0].tabID
    let windowIndex = TabListLogic.stripIndex(movingRow: 0, toRow: 1, in: controller.model.tabs)
    #expect(windowIndex == 1)
    controller.move(tab: first, to: windowIndex ?? 0)
    #expect(controller.model.tabs.map(\.title) == ["Tab 1", "Tab 0"])
    #expect(host.list(controller.model.shownSpaceID).contains { $0.title == "Elsewhere" })
  }

  @Test func spaceIndexSkipsOtherWindowsTabs() {
    let a = FakeTab(id: 1, browserID: 1), b = FakeTab(id: 2, browserID: 2), c = FakeTab(id: 3, browserID: 1)
    let d = FakeTab(id: 4, browserID: 1)
    // The Space: a, b (another window's), c, d. The window: a, c, d.
    let space: [any ClairTab] = [a, b, c, d], window: [any ClairTab] = [a, c, d]
    #expect(TabListLogic.spaceIndex(movingTab: 4, toWindowIndex: 0, windowTabs: window, spaceTabs: space) == 0)
    // Between c and d: b, c, a, d.
    #expect(TabListLogic.spaceIndex(movingTab: 1, toWindowIndex: 1, windowTabs: window, spaceTabs: space) == 2)
    #expect(TabListLogic.spaceIndex(movingTab: 1, toWindowIndex: 2, windowTabs: window, spaceTabs: space) == 3)
    #expect(TabListLogic.spaceIndex(movingTab: 9, toWindowIndex: 0, windowTabs: window, spaceTabs: space) == nil)
  }

  @Test func incognitoWindowsHaveNoSpaces() {
    let host = FakeHost()
    host.addSpaces(["Work"])
    let browser = FakeBrowser(host: host, profileKind: .incognito)
    browser.addTab(title: "Private")
    let controller = BrowserWindowController(
      browser: browser, spaces: browser.spaces,
      preferences: SidebarPreferences(defaults: UserDefaults(suiteName: #function)!))
    browser.clairWindow = controller
    #expect(!controller.model.showsSpaces)
    #expect(controller.model.shownSpace == nil)
    #expect(controller.model.tabs.map(\.title) == ["Private"])
    controller.beginNewSpace()
    #expect(controller.model.newSpaceForm == nil)
    controller.showSpace(host.spaces[1].spaceID)
    #expect(!browser.commands.contains { $0.hasPrefix("showSpace") })
  }
}

/// Manage Spaces' state (add-spaces D10).
@MainActor
struct ManageSpacesTests {
  @Test func opensOnTheWindowsSpace() {
    let (host, _, controller) = spacesWindow(["Work", "Travel"])
    let work = host.spaces[1].spaceID
    controller.showSpace(work)
    let state = ManageSpacesState(spaces: controller.model.spaces, selecting: controller.model.shownSpaceID)
    #expect(state.selection == work)
    #expect(state.nameDraft == "Work")
  }

  @Test func addMakesANewSpaceLastAndSelectsIt() {
    let (host, _, controller) = spacesWindow()
    let state = ManageSpacesState(spaces: controller.model.spaces, selecting: FakeHost.homeID)
    state.add()
    #expect(host.spaces.map(\.name) == ["Home", "New Space"])
    #expect(state.selection == host.spaces[1].spaceID)
    #expect(state.nameDraft == "New Space")
    #expect(state.nameFocusRequests == 1)
  }

  @Test func removeIsOffForTheOnlySpace() {
    let (_, _, controller) = spacesWindow()
    let state = ManageSpacesState(spaces: controller.model.spaces, selecting: FakeHost.homeID)
    #expect(!state.canRemove)
    state.add()
    #expect(state.canRemove)
  }

  @Test func anEmptiedNameReverts() {
    let (host, _, controller) = spacesWindow()
    let state = ManageSpacesState(spaces: controller.model.spaces, selecting: FakeHost.homeID)
    state.nameDraft = "Res"
    state.nameChanged()
    #expect(host.spaces[0].name == "Res")
    state.nameDraft = "  "
    state.nameChanged()
    #expect(host.spaces[0].name == "Res")
    state.commitName()
    #expect(state.nameDraft == "Res")
  }

  @Test func draggingReordersSpaces() {
    let (host, _, controller) = spacesWindow(["Work", "Travel"])
    let state = ManageSpacesState(spaces: controller.model.spaces, selecting: FakeHost.homeID)
    state.move(host.spaces[2].spaceID, to: 0)
    #expect(host.spaces.map(\.name) == ["Travel", "Home", "Work"])
  }

  @Test func removingASpaceSelectsTheOneBefore() {
    let (host, _, controller) = spacesWindow(["Work", "Travel"])
    let travel = host.spaces[2].spaceID
    let state = ManageSpacesState(spaces: controller.model.spaces, selecting: travel)
    host.deleteSpace(travel)
    state.removed(travel, at: 2)
    #expect(state.selection == host.spaces[1].spaceID)
    #expect(state.nameDraft == "Work")
  }
}
