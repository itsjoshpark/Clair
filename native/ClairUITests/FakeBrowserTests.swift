// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import ClairHost
import Foundation
import Testing

@testable import ClairUI

/// The fake host reaches a window through the calls Chromium makes, so the
/// window's logic can be tested without an engine (design D14).
@MainActor
struct FakeBrowserTests {
  @Test func tabChangesReachTheWindow() {
    let browser = FakeBrowser()
    let window = RecordingWindow()
    let observer = RecordingSpacesObserver()
    browser.clairWindow = window
    browser.host.addObserver(observer)

    let first = browser.addTab(title: "One", url: "https://one.example/")
    let second = browser.addTab(title: "Two", url: "https://two.example/", activate: false)
    browser.change(first.with(title: "One!", isLoading: true))
    browser.moveTab(first.tabID, to: 0)
    browser.closeTabNow(first.tabID)

    let home = FakeHost.homeID
    #expect(
      observer.calls == [
        "tabs \(home) \(first.tabID)",
        "tabs \(home) \(second.tabID),\(first.tabID)",
        "tab \(first.tabID)",
        "tabs \(home) \(first.tabID),\(second.tabID)",
        "tabs \(home) \(second.tabID)",
      ])
    #expect(window.calls == ["active \(first.tabID)", "active \(second.tabID)"])
    #expect(observer.lists[home]?.map(\.tabID) == [second.tabID])
    #expect(observer.lastTab?.title == "One!")
    #expect(observer.lastTab?.isLoading == true)
  }

  // MARK: Spaces (add-spaces design D3, D4)

  /// A browser with rows E, D, C, B, A from the top, A active.
  func rows(_ titles: [String] = ["E", "D", "C", "B", "A"]) -> (FakeBrowser, [String: TabID]) {
    let browser = FakeBrowser()
    var ids: [String: TabID] = [:]
    for title in titles.reversed() {
      ids[title] = browser.addTab(title: title).tabID
    }
    browser.activate(tab: ids[titles.last!]!)
    return (browser, ids)
  }

  func activeTitle(_ browser: FakeBrowser) -> String? {
    browser.allTabs.first { $0.tabID == browser.activeTabID }?.title
  }

  @Test func aNewTabJoinsTheShownSpace() {
    let host = FakeHost()
    let work = host.addSpaces("Work")[0]
    let browser = FakeBrowser(host: host)
    browser.addTab(title: "Home tab")
    browser.showSpace(work)
    let tab = browser.addTab(title: "Work tab")
    #expect(tab.spaceID == work)
    // Above the new tab page that showing the empty Space opened.
    #expect(browser.tabs.map(\.title) == ["Work tab", ""])
    #expect(browser.tabs.allSatisfy { $0.spaceID == work })
    #expect(host.list(FakeHost.homeID).map(\.title) == ["Home tab"])
  }

  @Test func closingReturnsToWhereTheUserCameFrom() {
    let (browser, ids) = rows()
    browser.activate(tab: ids["A"]!)
    browser.activate(tab: ids["C"]!)
    browser.close(tab: ids["C"]!)
    #expect(activeTitle(browser) == "A")
  }

  @Test func afterACloseTheRowAboveIsNext() {
    let (browser, ids) = rows(["F", "E", "D", "B"])
    browser.activate(tab: ids["F"]!)
    browser.activate(tab: ids["D"]!)
    browser.activate(tab: ids["E"]!)
    browser.close(tab: ids["E"]!)
    // E came from D, so D shows; one step only.
    #expect(activeTitle(browser) == "D")
    browser.close(tab: ids["D"]!)
    #expect(activeTitle(browser) == "F")
  }

  @Test func closingTheTopRowShowsTheRowBelow() {
    let (browser, ids) = rows(["X", "Y", "Z"])
    // Z was selected from X.
    browser.close(tab: ids["Z"]!)
    #expect(activeTitle(browser) == "X")
    // A close made X active, so nothing is remembered: the row below.
    browser.close(tab: ids["X"]!)
    #expect(activeTitle(browser) == "Y")
  }

  @Test func closingASpacesLastTabShowsAnotherSpace() {
    let host = FakeHost()
    let work = host.addSpaces("Work")[0]
    let browser = FakeBrowser(host: host)
    let window = RecordingWindow()
    browser.clairWindow = window
    browser.addTab(title: "Home tab")
    browser.showSpace(work)
    let only = browser.allTabs.first { $0.spaceID == work }!
    browser.close(tab: only.tabID)
    #expect(browser.shownSpaceID == FakeHost.homeID)
    #expect(activeTitle(browser) == "Home tab")
    #expect(window.calls.contains("space \(FakeHost.homeID) from \(work)"))
  }

  @Test func showingAnEmptySpaceOpensANewTabPageWithTheCommandBar() {
    let host = FakeHost()
    let work = host.addSpaces("Work")[0]
    let browser = FakeBrowser(host: host)
    let window = RecordingWindow()
    browser.clairWindow = window
    browser.addTab(title: "Home tab")
    browser.showSpace(work)
    #expect(browser.shownSpaceID == work)
    #expect(browser.tabs.count == 1)
    #expect(browser.tabs.first?.isNewTabPage == true)
    #expect(window.calls.suffix(3) == ["space \(work) from \(FakeHost.homeID)", "active \(browser.activeTabID)", "commandBar 1"])
    // Back home, the tab last active there shows.
    browser.showSpace(FakeHost.homeID)
    #expect(activeTitle(browser) == "Home tab")
  }

  @Test func theShownSpaceFollowsTheActiveTab() {
    let host = FakeHost()
    let work = host.addSpaces("Work")[0]
    let browser = FakeBrowser(host: host)
    let homeTab = browser.addTab(title: "Home tab")
    browser.showSpace(work)
    browser.activate(tab: homeTab.tabID)
    #expect(browser.shownSpaceID == FakeHost.homeID)
  }

  // MARK: Tabs shared across windows (share-tabs-across-windows D1 to D4)

  /// Windows A and B on one host. A holds Notes and Docs, Docs on top and
  /// active; B holds "B tab", on top of the list and active there.
  @MainActor struct TwoWindows {
    let host = FakeHost()
    let a: FakeBrowser
    let b: FakeBrowser
    let windowA = RecordingWindow()
    let windowB = RecordingWindow()
    let docs: FakeTab
    let notes: FakeTab
    let bTab: FakeTab

    init() {
      a = FakeBrowser(host: host)
      b = FakeBrowser(host: host)
      a.clairWindow = windowA
      b.clairWindow = windowB
      notes = a.addTab(title: "Notes")
      docs = a.addTab(title: "Docs")
      bTab = b.addTab(title: "B tab")
    }

    func titles() -> [String] { host.list(FakeHost.homeID).map(\.title) }
    func holder(_ tab: FakeTab) -> BrowserID? { host.tab(tab.tabID)?.browserID }
  }

  @Test func bothWindowsListTheSameTabs() {
    let w = TwoWindows()
    #expect(w.a.tabs.map(\.tabID) == w.b.tabs.map(\.tabID))
    #expect(w.titles() == ["B tab", "Docs", "Notes"])
  }

  @Test func takingATabLeavesAStillAndTakingItBackSwapsThem() {
    let w = TwoWindows()
    w.b.activate(tab: w.docs.tabID)
    // B shows the live page; the list keeps its order.
    #expect(w.b.activeTabID == w.docs.tabID)
    #expect(w.holder(w.docs) == w.b.browserID)
    #expect(w.b.pageView(for: w.docs.tabID) != nil)
    #expect(w.a.pageView(for: w.docs.tabID) == nil)
    #expect(w.titles() == ["B tab", "Docs", "Notes"])
    // A shows a still over its placeholder, on the same Space.
    #expect(w.a.stillTabID == w.docs.tabID)
    #expect(w.a.stillImage != nil)
    #expect(w.a.activeTabID == w.a.placeholderID)
    #expect(w.a.shownSpaceID == FakeHost.homeID)
    #expect(w.windowA.calls.suffix(2) == ["still", "active \(w.a.placeholderID)"])
    #expect(!w.a.tabs.contains { $0.tabID == w.a.placeholderID })

    // A click in A takes it back; B keeps the still now.
    w.a.becomeKey()
    #expect(w.a.activeTabID == w.docs.tabID)
    #expect(w.a.stillTabID == ClairTabIDNone)
    #expect(w.holder(w.docs) == w.a.browserID)
    #expect(w.b.stillTabID == w.docs.tabID)
    #expect(w.b.activeTabID == w.b.placeholderID)
  }

  @Test func takingATabNoWindowShowsLeavesItsWindowAlone() {
    let w = TwoWindows()
    w.b.activate(tab: w.notes.tabID)
    #expect(w.b.activeTabID == w.notes.tabID)
    #expect(w.a.activeTabID == w.docs.tabID)
    #expect(w.a.stillTabID == ClairTabIDNone)
    #expect(w.windowA.calls.last == "active \(w.docs.tabID)")
  }

  @Test func selectingAnotherRowEndsTheStill() {
    let w = TwoWindows()
    w.b.activate(tab: w.docs.tabID)
    w.a.activate(tab: w.notes.tabID)
    #expect(w.a.stillTabID == ClairTabIDNone)
    #expect(w.a.activeTabID == w.notes.tabID)
    #expect(w.b.activeTabID == w.docs.tabID)
    #expect(w.windowA.calls.suffix(2) == ["still", "active \(w.notes.tabID)"])
  }

  @Test func closingTheStillsTabLeavesANewTabPage() {
    let w = TwoWindows()
    w.b.activate(tab: w.docs.tabID)
    let placeholder = w.a.placeholderID
    w.b.close(tab: w.docs.tabID)
    // B goes back to where it came from.
    #expect(w.b.activeTabID == w.bTab.tabID)
    // A's placeholder is an ordinary new tab page at the top of the Space.
    #expect(w.a.stillTabID == ClairTabIDNone)
    #expect(w.a.activeTabID == placeholder)
    #expect(w.a.tabs.first?.tabID == placeholder)
    #expect(w.a.tabs.first?.isNewTabPage == true)
    #expect(w.windowA.calls.last == "commandBar 1")
  }

  @Test func showingASpaceWhoseTabsAreHeldElsewhere() {
    let host = FakeHost()
    let work = host.addSpaces("Work")[0]
    let a = FakeBrowser(host: host)
    a.addTab(title: "Home tab")
    let b = FakeBrowser(host: host)
    b.addTab(title: "B tab")
    a.showSpace(work)
    let older = a.activeTabID
    let newer = a.addTab(title: "Newer").tabID
    a.activate(tab: older)
    a.activate(tab: newer)
    a.showSpace(FakeHost.homeID)
    // Neither Work tab shows in A; B shows the more recently active.
    b.showSpace(work)
    #expect(b.activeTabID == newer)
    #expect(host.tab(newer)?.browserID == b.browserID)
    #expect(a.stillTabID == ClairTabIDNone)
    #expect(a.shownSpaceID == FakeHost.homeID)
  }

  @Test func showingASpaceWhoseOnlyTabShowsElsewhere() {
    let host = FakeHost()
    let work = host.addSpaces("Work")[0]
    let a = FakeBrowser(host: host)
    a.addTab(title: "Home tab")
    let b = FakeBrowser(host: host)
    let windowB = RecordingWindow()
    b.clairWindow = windowB
    b.addTab(title: "B tab")
    a.showSpace(work)
    let shown = a.activeTabID
    b.showSpace(work)
    #expect(a.activeTabID == shown)
    #expect(a.stillTabID == ClairTabIDNone)
    #expect(b.activeTabID != shown)
    #expect(host.tab(b.activeTabID)?.isNewTabPage == true)
    #expect(host.list(work).count == 2)
    #expect(windowB.calls.last == "commandBar 1")
  }

  @Test func theRowAboveHeldElsewhereShowsHere() {
    let host = FakeHost()
    let a = FakeBrowser(host: host), b = FakeBrowser(host: host)
    let x = a.addTab(title: "X")
    let shownInA = a.addTab(title: "Shown in A")
    let y = b.addTab(title: "Y", at: 2)
    #expect(host.list(FakeHost.homeID).map(\.title) == ["Shown in A", "X", "Y"])
    b.close(tab: y.tabID)
    #expect(b.activeTabID == x.tabID)
    #expect(a.activeTabID == shownInA.tabID)
    #expect(a.stillTabID == ClairTabIDNone)
  }

  @Test func theRowAboveShowingElsewhereIsTakenWithAStill() {
    let host = FakeHost()
    let a = FakeBrowser(host: host), b = FakeBrowser(host: host)
    let x = a.addTab(title: "X")
    let y = b.addTab(title: "Y", at: 1)
    #expect(host.list(FakeHost.homeID).map(\.title) == ["X", "Y"])
    b.close(tab: y.tabID)
    #expect(b.activeTabID == x.tabID)
    #expect(a.stillTabID == x.tabID)
  }

  @Test func closingAWindowHandsItsTabsToAnother() {
    let w = TwoWindows()
    let peek = w.a.openPeek(of: w.docs.tabID, title: "Peek")!
    w.a.requestClose()
    #expect(w.a.isClosed)
    #expect(w.windowA.calls.last == "closed")
    // Every tab, the Peek with its parent, now in B, in the same order.
    #expect(w.titles() == ["B tab", "Docs", "Peek", "Notes"])
    #expect(w.host.list(FakeHost.homeID).allSatisfy { $0.browserID == w.b.browserID })
    #expect(w.host.tab(w.docs.tabID)?.peekID == peek.tabID)
    #expect(w.b.activeTabID == w.bTab.tabID)
  }

  @Test func closingTheLastWindowGoesThroughChromium() {
    let w = TwoWindows()
    w.b.requestClose()
    w.a.requestClose()
    // B's tabs went to A; A had no other window, so Chromium closes it.
    #expect(w.b.isClosed)
    #expect(!w.a.isClosed)
    #expect(w.a.commands.last == "requestClose")
    #expect(w.host.list(FakeHost.homeID).allSatisfy { $0.browserID == w.a.browserID })
  }

  @Test func suggestionsReachTheDelegate() {
    final class Delegate: NSObject, ClairAutocompleteDelegate {
      var received: [[String]] = []
      func autocomplete(_ session: any ClairAutocomplete, didUpdate suggestions: [any ClairSuggestion], finished: Bool) {
        received.append(suggestions.map(\.contents))
      }
    }
    let browser = FakeBrowser()
    let delegate = Delegate()
    let session = browser.startAutocomplete(mode: .newTab, delegate: delegate)
    session.query("wiki")
    browser.autocomplete?.post([FakeSuggestion(id: 1, contents: "Wikipedia"), FakeSuggestion(id: 2, contents: "wiki")])
    session.stop()
    browser.autocomplete?.post([FakeSuggestion(id: 3, contents: "late")])

    #expect(browser.autocomplete?.queries == ["wiki"])
    #expect(delegate.received == [["Wikipedia", "wiki"]])
  }

  @Test func closedBrowserIgnoresCommands() {
    let browser = FakeBrowser()
    let window = RecordingWindow()
    browser.clairWindow = window
    browser.addTab()
    browser.closeWindow()
    browser.goBack()
    #expect(window.calls.last == "closed")
    #expect(browser.commands.isEmpty)
  }
}
