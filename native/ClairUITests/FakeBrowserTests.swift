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
