// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Testing

@testable import ClairUI

/// The URL field's display rules (sidebar spec, "URL field").
@MainActor
struct URLDisplayTests {
  @Test func webPageShowsItsHost() {
    let tab = FakeTab(id: 1, url: "https://news.ycombinator.com/item?id=1")
    #expect(URLDisplay.text(for: tab) == "news.ycombinator.com")
  }

  @Test func chromePageShowsItsFullURL() {
    let tab = FakeTab(id: 1, url: "chrome://settings/")
    #expect(URLDisplay.text(for: tab) == "chrome://settings/")
  }

  @Test func fileShowsItsFullURL() {
    let tab = FakeTab(id: 1, url: "file:///Users/me/notes.txt")
    #expect(URLDisplay.text(for: tab) == "file:///Users/me/notes.txt")
  }

  @Test func newTabPageShowsThePlaceholder() {
    let tab = FakeTab(id: 1, url: "chrome://newtab/")
    #expect(URLDisplay.text(for: tab) == nil)
    #expect(URLDisplay.editingText(for: tab) == "")
  }

  @Test func editingShowsTheFullURL() {
    let tab = FakeTab(id: 1, url: "https://news.ycombinator.com/item?id=1")
    #expect(URLDisplay.editingText(for: tab) == "https://news.ycombinator.com/item?id=1")
  }

  @Test func noTabShowsThePlaceholder() {
    #expect(URLDisplay.text(for: nil) == nil)
  }
}

/// Where Chromium's bubbles attach (design D7).
@MainActor
struct AnchorResolverTests {
  let siteControls = CGRect(x: 20, y: 700, width: 24, height: 24)
  let camera = CGRect(x: 160, y: 700, width: 20, height: 20)
  let pinned = CGRect(x: 40, y: 640, width: 28, height: 28)
  let extensionsButton = CGRect(x: 180, y: 640, width: 28, height: 28)
  let card = CGRect(x: 228, y: 10, width: 962, height: 780)

  func resolver(inPlace: Bool) -> AnchorResolver {
    AnchorResolver(
      sidebarInPlace: inPlace,
      controls: [
        .siteControls: siteControls,
        .indicator(TabIndicators.camera.rawValue): camera,
        .extensionAction("pinned"): pinned,
        .extensionsButton: extensionsButton,
      ],
      card: card)
  }

  @Test func sidebarShownAnchorsToControls() {
    let resolver = resolver(inPlace: true)
    let site = resolver.anchor(for: .siteControls, indicator: [], extensionID: nil)
    #expect(site.rect == siteControls)
    #expect(site.edge == .trailing)
    #expect(resolver.anchor(for: .indicator, indicator: .camera, extensionID: nil).rect == camera)
    #expect(resolver.anchor(for: .extensionAction, indicator: [], extensionID: "pinned").rect == pinned)
  }

  @Test func missingControlsFallBackToTheirNeighbours() {
    let resolver = resolver(inPlace: true)
    #expect(resolver.anchor(for: .indicator, indicator: .location, extensionID: nil).rect == siteControls)
    #expect(resolver.anchor(for: .extensionAction, indicator: [], extensionID: "unpinned").rect == extensionsButton)
  }

  @Test(arguments: [AnchorKind.siteControls, .indicator, .extensionAction, .extensionsButton, .downloads])
  func sidebarHiddenAnchorsToTheCardCorner(kind: AnchorKind) {
    let anchor = resolver(inPlace: false).anchor(for: kind, indicator: .camera, extensionID: "pinned")
    #expect(anchor.edge == .bottom)
    #expect(anchor.rect.origin == CGPoint(x: card.minX + AnchorResolver.fallbackInset, y: card.maxY))
  }

  @Test func unknownDownloadsButtonFallsBack() {
    let anchor = resolver(inPlace: true).anchor(for: .downloads, indicator: [], extensionID: nil)
    #expect(anchor.edge == .bottom)
  }
}

/// The tab list's ordering, insertion and Close Tabs Below (design D12).
@MainActor
struct TabListTests {
  @Test func dragDownLandsAboveTheDropRow() {
    #expect(TabListLogic.moveTarget(from: 0, to: 3, count: 5) == 2)
  }

  @Test func dragUpLandsAtTheDropRow() {
    #expect(TabListLogic.moveTarget(from: 2, to: 0, count: 5) == 0)
  }

  @Test func droppingInPlaceDoesNothing() {
    #expect(TabListLogic.moveTarget(from: 2, to: 2, count: 5) == nil)
    #expect(TabListLogic.moveTarget(from: 2, to: 3, count: 5) == nil)
    #expect(TabListLogic.moveTarget(from: 7, to: 0, count: 5) == nil)
  }

  @Test func newTabsAppearAtTheTopOfTheList() {
    let browser = FakeBrowser()
    let controller = BrowserWindowController(
      browser: browser, preferences: SidebarPreferences(defaults: UserDefaults(suiteName: #function)!))
    browser.clairWindow = controller
    browser.addTab(title: "Old")
    browser.addTab(title: "New", at: 0, activate: false)
    #expect(controller.model.tabs.map(\.title) == ["New", "Old"])
  }

  @Test func closeTabsBelowClosesEveryLaterTab() {
    let browser = FakeBrowser()
    let controller = BrowserWindowController(
      browser: browser, preferences: SidebarPreferences(defaults: UserDefaults(suiteName: #function)!))
    browser.clairWindow = controller
    for index in 0..<5 {
      browser.addTab(title: "\(index)", at: index, activate: index == 0)
    }
    let second = browser.tabs[1].tabID
    #expect(TabListLogic.tabsBelow(second, in: controller.model.tabs).count == 3)
    controller.closeTabs(below: second)
    #expect(controller.model.tabs.map(\.title) == ["0", "1"])
  }

  @Test func copyLinkUsesTheFullURL() {
    #expect(TabListLogic.link(of: FakeTab(id: 1, url: "https://example.com/a?b=c")) == "https://example.com/a?b=c")
  }
}

/// The command bar's keys and modes (design D11).
@MainActor
struct CommandBarTests {
  let suggestions = [
    FakeSuggestion(id: 1, kind: .URL, contents: "example.com", destination: "https://example.com/"),
    FakeSuggestion(id: 2, kind: .history, contents: "Example Domain", destination: "https://example.org/"),
    FakeSuggestion(
      id: 3, kind: .search, contents: "wiki", destination: "https://search.example/?q=wiki", keyword: "wiki",
      keywordName: "Wikipedia"),
  ]

  func open(_ mode: CommandBarMode, text: String = "") -> (FakeBrowser, CommandBarModel, Box) {
    let browser = FakeBrowser()
    let closed = Box()
    let model = CommandBarModel(mode: mode, text: text, browser: browser) { closed.value = $0 }
    return (browser, model, closed)
  }

  final class Box { var value: Bool? }

  @Test func opensASessionOnTheText() {
    let (browser, _, _) = open(.currentTab, text: "https://example.com/")
    #expect(browser.autocomplete?.mode == .currentTab)
    #expect(browser.autocomplete?.queries == ["https://example.com/"])
  }

  @Test func typingQueries() {
    let (browser, model, _) = open(.newTab)
    model.setText("exa")
    #expect(browser.autocomplete?.queries == ["", "exa"])
  }

  @Test func firstRowIsSelectedAndArrowsMove() {
    let (browser, model, _) = open(.newTab)
    browser.autocomplete?.post(suggestions)
    #expect(model.selection == 0)
    model.moveSelection(by: 1)
    model.moveSelection(by: 1)
    model.moveSelection(by: 1)
    #expect(model.selection == 2)
    model.moveSelection(by: -5)
    #expect(model.selection == 0)
  }

  @Test func returnInNewTabModeOpensANewTab() {
    let (browser, model, closed) = open(.newTab)
    browser.autocomplete?.post(suggestions)
    model.moveSelection(by: 1)
    #expect(model.submit())
    #expect(browser.autocomplete?.opened.first?.suggestionID == 2)
    #expect(browser.autocomplete?.opened.first?.disposition == .newForegroundTab)
    #expect(browser.autocomplete?.isStopped == true)
    #expect(closed.value == true)
  }

  @Test func returnInCurrentTabModeNavigatesTheTab() {
    let (browser, model, _) = open(.currentTab, text: "https://example.com/")
    browser.autocomplete?.post(suggestions)
    model.submit()
    #expect(browser.autocomplete?.opened.first?.disposition == .currentTab)
  }

  @Test func shiftOrCommandReturnOpensANewTabFromCurrentTabMode() {
    let (browser, model, _) = open(.currentTab, text: "https://example.com/")
    browser.autocomplete?.post(suggestions)
    model.submit(newTab: true)
    #expect(browser.autocomplete?.opened.first?.disposition == .newForegroundTab)
  }

  @Test func escapeOpensNothing() {
    let (browser, model, closed) = open(.newTab)
    browser.autocomplete?.post(suggestions)
    model.cancel()
    #expect(browser.autocomplete?.opened.isEmpty == true)
    #expect(browser.autocomplete?.isStopped == true)
    #expect(closed.value == false)
    #expect(!model.submit())
  }

  @Test func returnWithoutSuggestionsDoesNothing() {
    let (_, model, closed) = open(.newTab)
    #expect(!model.submit())
    #expect(closed.value == nil)
  }

  @Test func tabEntersKeywordModeAndDeleteLeavesIt() {
    let (browser, model, _) = open(.newTab)
    model.setText("wiki")
    browser.autocomplete?.post(suggestions)
    model.moveSelection(by: 2)
    #expect(model.offeredKeywordName == "Wikipedia")
    #expect(model.acceptKeyword())
    #expect(model.keywordName == "Wikipedia")
    #expect(model.text == "")
    #expect(browser.autocomplete?.keyword == "wiki")
    model.setText("Arc")
    #expect(browser.autocomplete?.queries.last == "Arc")
    model.setText("")
    #expect(model.deleteBackwardInEmptyField())
    #expect(model.keywordName == nil)
    #expect(model.text == "wiki")
  }

  @Test func tabWithoutAKeywordDoesNothing() {
    let (browser, model, _) = open(.newTab)
    browser.autocomplete?.post(suggestions)
    #expect(!model.acceptKeyword())
  }
}
