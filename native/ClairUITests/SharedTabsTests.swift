// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Foundation
import Testing

@testable import ClairUI

/// Two regular windows on one fake host, each with its controller, as ClairUI
/// sees them (share-tabs-across-windows D1). A holds Docs and Notes, Docs
/// active; B holds "B tab", active there.
@MainActor
struct SharedWindows {
  let host = FakeHost()
  let a: FakeBrowser
  let b: FakeBrowser
  let controllerA: BrowserWindowController
  let controllerB: BrowserWindowController
  let docs: FakeTab
  let notes: FakeTab
  let bTab: FakeTab

  init(suite: String = #function) {
    a = FakeBrowser(host: host)
    b = FakeBrowser(host: host)
    controllerA = BrowserWindowController(
      browser: a, spaces: a.spaces, preferences: SidebarPreferences(defaults: UserDefaults(suiteName: suite + ".a")!))
    controllerB = BrowserWindowController(
      browser: b, spaces: b.spaces, preferences: SidebarPreferences(defaults: UserDefaults(suiteName: suite + ".b")!))
    a.clairWindow = controllerA
    b.clairWindow = controllerB
    notes = a.addTab(title: "Notes", url: "https://notes.example/")
    docs = a.addTab(title: "Docs", url: "https://docs.example/")
    bTab = b.addTab(title: "B tab", url: "https://b.example/")
  }

  func titles(_ controller: BrowserWindowController) -> [String] {
    controller.model.tabs.map(\.title)
  }
}

@MainActor
struct SharedTabListTests {
  @Test func twoWindowsOnOneSpaceListTheSameRows() {
    let w = SharedWindows()
    #expect(w.titles(w.controllerA) == ["B tab", "Docs", "Notes"])
    #expect(w.titles(w.controllerB) == w.titles(w.controllerA))
    // A tab opened, changed or closed in one shows in the other at once.
    let new = w.a.addTab(title: "New")
    #expect(w.titles(w.controllerB) == ["New", "B tab", "Docs", "Notes"])
    w.a.change(new.with(title: "Renamed"))
    #expect(w.controllerB.model.tabs.first?.title == "Renamed")
    w.a.closeTabNow(new.tabID)
    #expect(w.titles(w.controllerB) == ["B tab", "Docs", "Notes"])
  }

  @Test func aRowDraggedInOneWindowMovesInTheOther() {
    let w = SharedWindows()
    // B drags A's Notes to the top: the index is the Space's own.
    let index = TabListLogic.stripIndex(movingRow: 2, toRow: 0, in: w.controllerB.model.tabs)
    #expect(index == 0)
    w.controllerB.move(tab: w.notes.tabID, to: index ?? 0)
    #expect(w.b.commands.last == "move \(w.notes.tabID) 0")
    #expect(w.titles(w.controllerA) == ["Notes", "B tab", "Docs"])
    #expect(w.titles(w.controllerB) == ["Notes", "B tab", "Docs"])
  }

  @Test func anIncognitoWindowListsOnlyItsOwnTabs() {
    let (host, _, controller) = incognitoWindow(tabs: 1)
    let regular = FakeBrowser(host: host)
    regular.addTab(title: "Regular")
    let other = FakeBrowser(host: host, profileKind: .incognito)
    other.addTab(title: "Other incognito")
    #expect(controller.model.tabs.map(\.title) == ["Tab 0"])
  }

  @Test func aNewWindowListsTheSpacesTabs() {
    let w = SharedWindows()
    let c = FakeBrowser(host: w.host)
    let controller = BrowserWindowController(
      browser: c, spaces: c.spaces, preferences: SidebarPreferences(defaults: UserDefaults(suiteName: #function)!))
    c.clairWindow = controller
    c.addTab(url: "chrome://newtab/")
    #expect(controller.model.tabs.count == 4)
    #expect(controller.model.activeTab?.isNewTabPage == true)
  }
}

/// share-tabs-across-windows D2: what a window shows while another took its
/// tab.
@MainActor
struct StillTests {
  @Test func theStillHighlightsItsRowWithoutItsPeekAndDisablesTheControls() {
    let w = SharedWindows()
    w.a.change(w.docs.with(canGoBack: true, canGoForward: true))
    var peek = w.a.openPeek(of: w.docs.tabID, title: "Peek", url: "https://peek.example/")!
    // The Peek is the active tab, whose history the buttons follow.
    peek = peek.with(canGoBack: true)
    w.a.change(peek)
    let model = w.controllerA.model
    #expect(model.rowPeeks(in: model.tabs)[w.docs.tabID]?.tabID == peek.tabID)
    #expect(model.urlFieldText != nil)

    // B takes Docs, with its Peek.
    w.controllerB.activate(tab: w.docs.tabID)
    #expect(w.b.activeTabID == peek.tabID)
    #expect(model.isShowingStill)
    #expect(model.stillTabID == w.docs.tabID)
    #expect(model.stillImage != nil)
    #expect(model.highlightedRow(in: model.tabs) == w.docs.tabID)
    #expect(model.rowPeeks(in: model.tabs)[w.docs.tabID] == nil)
    #expect(model.activeTab == nil)
    #expect(model.urlFieldText == nil)
    #expect(!model.canGoBack)
    #expect(!model.canGoForward)
    #expect(!model.canReload)
    #expect(!w.controllerA.rootView.card.stillView.isHidden)
    #expect(w.controllerA.rootView.card.stillView.isAccessibilityElement())
    #expect(w.controllerA.rootView.card.stillView.superview != nil)
    #expect(w.controllerA.rootView.card.stillView.image != nil)
    // B shows the tab with its Peek and its badge.
    let modelB = w.controllerB.model
    #expect(modelB.rowPeeks(in: modelB.tabs)[w.docs.tabID]?.tabID == peek.tabID)
    #expect(modelB.canGoBack)

    // Taking it back clears all of it.
    w.a.becomeKey()
    #expect(!model.isShowingStill)
    #expect(model.stillImage == nil)
    #expect(model.highlightedRow(in: model.tabs) == w.docs.tabID)
    #expect(model.canGoBack)
    #expect(model.canReload)
    #expect(w.controllerA.rootView.card.stillView.isHidden)
    #expect(!w.controllerA.rootView.card.stillView.isAccessibilityElement())
    #expect(w.controllerA.rootView.card.stillView.superview == nil)
    #expect(w.controllerB.model.isShowingStill)
  }

  @Test func aFailedCopyDimsTheCardAlone() {
    let w = SharedWindows()
    w.a.nextStillImage = nil
    w.controllerB.activate(tab: w.docs.tabID)
    let model = w.controllerA.model
    #expect(model.isShowingStill)
    #expect(model.stillImage == nil)
    #expect(model.highlightedRow(in: model.tabs) == w.docs.tabID)
    #expect(model.urlFieldText == nil)
    #expect(!model.canReload)
    #expect(!w.controllerA.rootView.card.stillView.isHidden)
    #expect(w.controllerA.rootView.card.stillView.image == nil)
  }

  @Test func closingTheStillsTabOpensTheCommandBar() {
    let w = SharedWindows()
    w.controllerB.activate(tab: w.docs.tabID)
    w.controllerB.close(tab: w.docs.tabID)
    let model = w.controllerA.model
    #expect(!model.isShowingStill)
    #expect(model.activeTab?.isNewTabPage == true)
    #expect(model.tabs.first?.tabID == model.activeTabID)
    #expect(model.commandBar?.mode == .currentTab)
    #expect(w.controllerA.rootView.card.stillView.isHidden)
  }

  @Test func switchingSpaceEndsTheStill() {
    let w = SharedWindows()
    let work = w.host.addSpaces("Work")[0]
    w.controllerB.activate(tab: w.docs.tabID)
    w.controllerA.showSpace(work)
    #expect(!w.controllerA.model.isShowingStill)
    #expect(w.controllerA.model.shownSpaceID == work)
    #expect(w.b.activeTabID == w.docs.tabID)
  }
}

/// Row actions on a row another window holds (share-tabs-across-windows D1,
/// D3): each reaches the tab, wherever it is.
@MainActor
struct OtherWindowRowTests {
  @Test func selectingTakesTheTab() {
    let w = SharedWindows()
    w.controllerA.activate(tab: w.bTab.tabID)
    #expect(w.a.commands.last == "activate \(w.bTab.tabID)")
    #expect(w.host.tab(w.bTab.tabID)?.browserID == w.a.browserID)
    #expect(w.controllerA.model.activeTabID == w.bTab.tabID)
    #expect(w.controllerB.model.isShowingStill)
  }

  @Test func closingAndMiddleClickingCloseItWhereItIs() {
    let w = SharedWindows()
    // A middle click on a row closes it, as its close button does.
    w.controllerB.close(tab: w.notes.tabID)
    #expect(w.b.commands.last == "close \(w.notes.tabID)")
    #expect(!w.controllerA.model.tabs.contains { $0.tabID == w.notes.tabID })
    #expect(!w.controllerB.model.tabs.contains { $0.tabID == w.notes.tabID })
    #expect(w.a.activeTabID == w.docs.tabID)
    #expect(w.b.activeTabID == w.bTab.tabID)
  }

  @Test func closingAnotherWindowsActiveTopRowLeavesThisWindowsTab() {
    let w = SharedWindows()
    // A closes B's top row. Below it, Docs shows in A, where the user is, so
    // B shows Notes, below that, and A keeps Docs.
    w.controllerA.close(tab: w.bTab.tabID)
    #expect(w.b.activeTabID == w.notes.tabID)
    #expect(w.a.activeTabID == w.docs.tabID)
    #expect(!w.controllerA.model.isShowingStill)
  }

  @Test func closingAnotherWindowsActiveRowLeavesItOnItsNextTab() {
    let w = SharedWindows()
    w.b.activate(tab: w.notes.tabID)
    w.b.activate(tab: w.bTab.tabID)
    w.controllerA.close(tab: w.bTab.tabID)
    #expect(w.b.activeTabID == w.notes.tabID)
    #expect(w.a.activeTabID == w.docs.tabID)
  }

  @Test func mutingDuplicatingAndCopyingAReachTheTab() {
    let w = SharedWindows()
    w.controllerA.setMuted(true, tab: w.bTab.tabID)
    w.controllerA.duplicate(tab: w.bTab.tabID)
    #expect(w.a.commands.suffix(2) == ["mute \(w.bTab.tabID)", "duplicate \(w.bTab.tabID)"])
    NSPasteboard.general.clearContents()
    w.controllerA.copyLink(of: w.bTab.tabID)
    #expect(NSPasteboard.general.string(forType: .string) == "https://b.example/")
  }

  @Test func movingToAnotherSpace() {
    let w = SharedWindows()
    let work = w.host.addSpaces("Work")[0]
    w.controllerA.moveTab(w.bTab.tabID, toSpace: work)
    #expect(w.host.list(work).first?.tabID == w.bTab.tabID)
    #expect(!w.controllerA.model.tabs.contains { $0.tabID == w.bTab.tabID })
    // add-profiles D9: B, which showed it, follows it; A, which didn't, says
    // where it went.
    #expect(w.b.shownSpaceID == work)
    #expect(w.b.activeTabID == w.bTab.tabID)
    #expect(w.a.shownSpaceID == FakeHost.homeID)
    #expect(w.controllerA.model.notice.notice?.text == "Tab was moved to Work")
  }

  @Test func draggingIt() {
    let w = SharedWindows()
    let index = TabListLogic.stripIndex(movingRow: 0, toRow: 2, in: w.controllerA.model.tabs)
    w.controllerA.move(tab: w.bTab.tabID, to: index ?? 0)
    #expect(w.titles(w.controllerA) == ["Docs", "Notes", "B tab"])
    #expect(w.titles(w.controllerB) == ["Docs", "Notes", "B tab"])
  }

  @Test func tabCommandsReachRowsFromAnotherWindow() {
    let w = SharedWindows()
    // Close Tabs Below from B's row closes A's rows too. A, left with no row
    // it may show, stays on its Space on a new tab page (add-profiles D13).
    w.controllerB.closeTabs(below: w.bTab.tabID)
    #expect(w.titles(w.controllerA) == ["", "B tab"])
    #expect(w.titles(w.controllerB) == ["", "B tab"])
    #expect(w.controllerA.model.activeTab?.isNewTabPage == true)
    #expect(w.b.activeTabID == w.bTab.tabID)
  }
}
