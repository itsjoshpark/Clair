// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import SwiftUI
import Testing

@testable import ClairUI

/// The tab list's rules for Peeks (add-peek design D4).
@MainActor
struct PeekTabListTests {
  /// Three tabs, the second with a Peek right after it, as Chromium orders
  /// them.
  let tabs: [any ClairTab] = [
    FakeTab(id: 1, title: "One"),
    FakeTab(id: 2, title: "Two", peekID: 4),
    FakeTab(id: 4, title: "Peek", peekParentID: 2),
    FakeTab(id: 3, title: "Three"),
  ]

  @Test func aPeekIsNeverARow() {
    #expect(TabListLogic.rows(tabs).map(\.tabID) == [1, 2, 3])
  }

  @Test func theParentsRowIsHighlightedWhileItsPeekIsActive() {
    #expect(TabListLogic.highlightedRow(activeTabID: 4, in: tabs) == 2)
    #expect(TabListLogic.highlightedRow(activeTabID: 2, in: tabs) == 2)
    #expect(TabListLogic.highlightedRow(activeTabID: 3, in: tabs) == 3)
  }

  @Test func aClickOnTheRowTargetsThePeek() {
    #expect(TabListLogic.tabToActivate(forRow: 2, in: tabs) == 4)
    #expect(TabListLogic.tabToActivate(forRow: 1, in: tabs) == 1)
  }

  @Test func theRowShowsItsPeeksFavicon() {
    #expect(TabListLogic.peek(ofRow: 2, in: tabs)?.title == "Peek")
    #expect(TabListLogic.peek(ofRow: 1, in: tabs) == nil)
  }

  @Test func theCardShowsThePeekOverItsParent() {
    let shown = TabListLogic.ShownPeek(parentID: 2, peekID: 4)
    #expect(TabListLogic.shownPeek(activeTabID: 4, in: tabs) == shown)
    // The parent, made active some other way, shows with its Peek.
    #expect(TabListLogic.shownPeek(activeTabID: 2, in: tabs) == shown)
    #expect(TabListLogic.shownPeek(activeTabID: 1, in: tabs) == nil)
    // A closing Peek has left its parent's peekID: the parent shows alone.
    let closing: [any ClairTab] = [FakeTab(id: 2), FakeTab(id: 4, peekParentID: 2)]
    #expect(TabListLogic.shownPeek(activeTabID: 2, in: closing) == nil)
    // A Peek whose parent has gone shows on its own.
    let orphan: [any ClairTab] = [FakeTab(id: 4, peekParentID: 9)]
    #expect(TabListLogic.shownPeek(activeTabID: 4, in: orphan) == nil)
  }

  @Test func draggingARowCountsPeeksInTheTabStripIndex() {
    // Rows [1, 2(+4), 3]: the third row above the first lands at index 0.
    #expect(TabListLogic.stripIndex(movingRow: 2, toRow: 0, in: tabs) == 0)
    // The first row below the second lands after 2 and its Peek.
    #expect(TabListLogic.stripIndex(movingRow: 0, toRow: 1, in: tabs) == 2)
    // The tab with the Peek to the end: after 1 and 3.
    #expect(TabListLogic.stripIndex(movingRow: 1, toRow: 2, in: tabs) == 2)
    #expect(TabListLogic.stripIndex(movingRow: 5, toRow: 0, in: tabs) == nil)
  }
}

/// The Peek's geometry (add-peek design D4).
struct PeekLayoutTests {
  let card = CGRect(x: 0, y: 0, width: 1723, height: 1030)

  @Test func thePeekMatchesArcsAtArcsCard() {
    let peek = PeekLayout.peekFrame(in: card)
    #expect(peek.size == CGSize(width: 1386, height: 1026))
    #expect(peek.minY == 2)
    #expect(abs(peek.midX - card.midX) <= 0.5)
  }

  @Test func thePeekKeepsItsProportionsAsTheCardResizes() {
    let peek = PeekLayout.peekFrame(in: CGRect(x: 0, y: 0, width: 1000, height: 600))
    #expect(peek.width == 804)
    #expect(peek.height == 596)
    #expect(peek.minX == 98)
  }

  @Test func theParentShrinksNinePointsPerSide() {
    #expect(PeekLayout.parentFrame(in: card) == CGRect(x: 9, y: 9, width: 1705, height: 1012))
    let transform = PeekLayout.parentTransform(size: card.size, anchor: .zero)
    let corner = CGPoint(x: 0, y: 0).applying(CATransform3DGetAffineTransform(transform))
    let far = CGPoint(x: card.width, y: card.height).applying(CATransform3DGetAffineTransform(transform))
    #expect(abs(corner.x - 9) < 0.001 && abs(corner.y - 9) < 0.001)
    #expect(abs(far.x - (card.width - 9)) < 0.001 && abs(far.y - (card.height - 9)) < 0.001)
  }

  @Test func theParentTransformAllowsForTheAnchor() {
    // About the centre, the same page lands in the same place.
    let transform = PeekLayout.parentTransform(size: card.size, anchor: CGPoint(x: 0.5, y: 0.5))
    let centre = CGPoint(x: card.midX, y: card.midY)
    let corner = CGPoint(x: 0, y: 0)
    let affine = CATransform3DGetAffineTransform(transform)
    // Applied about the anchor: p' = c + M(p - c).
    func apply(_ point: CGPoint) -> CGPoint {
      let moved = CGPoint(x: point.x - centre.x, y: point.y - centre.y).applying(affine)
      return CGPoint(x: moved.x + centre.x, y: moved.y + centre.y)
    }
    #expect(abs(apply(corner).x - 9) < 0.001 && abs(apply(corner).y - 9) < 0.001)
  }

  @Test func theButtonsSitBesideTheTopTrailingCorner() {
    let peek = PeekLayout.peekFrame(in: card)
    let buttons = PeekLayout.buttonFrames(beside: peek)
    #expect(buttons.count == 2)
    #expect(buttons[0] == CGRect(x: peek.maxX + 13, y: peek.minY + 7.5, width: 34.5, height: 33.5))
    #expect(buttons[1].minY - buttons[0].minY == 43.5)
  }

  @Test func theGrowTransformShrinksTowardThePoint() {
    let point = CGPoint(x: 100, y: 200)
    let position = CGPoint(x: 168, y: 2)
    let transform = CATransform3DGetAffineTransform(
      PeekLayout.growTransform(from: point, position: position, scale: 0))
    // Every point of the layer collapses onto `point`, about its position.
    for corner in [CGPoint(x: 168, y: 2), CGPoint(x: 1554, y: 1028)] {
      let moved = CGPoint(x: corner.x - position.x, y: corner.y - position.y).applying(transform)
      #expect(abs(moved.x + position.x - point.x) < 0.001)
      #expect(abs(moved.y + position.y - point.y) < 0.001)
    }
  }
}

/// A window with a Peek, through the calls Chromium makes (add-peek design D4).
@MainActor
struct PeekWindowTests {
  let browser = FakeBrowser()
  let controller: BrowserWindowController

  init() {
    let defaults = UserDefaults(suiteName: "ClairUITests.Peek.\(UUID().uuidString)")!
    controller = BrowserWindowController(
      browser: browser, spaces: browser.spaces, preferences: SidebarPreferences(defaults: defaults),
      peekPreference: PeekPreference(defaults: defaults))
    browser.clairWindow = controller
  }

  /// Three tabs, the middle one active, with a Peek opened from it.
  private func openPeek() -> (parent: FakeTab, peek: FakeTab) {
    browser.addTab(title: "Three", url: "https://three.example/")
    let parent = browser.addTab(title: "Two", url: "https://two.example/")
    browser.addTab(title: "One", url: "https://one.example/", activate: false)
    let peek = browser.openPeek(of: parent.tabID, title: "Peek", url: "https://peek.example/")!
    return (parent, peek)
  }

  @Test func aPeekShowsOverItsParent() {
    let (parent, peek) = openPeek()
    #expect(controller.model.activeTabID == peek.tabID)
    #expect(TabListLogic.rows(controller.model.tabs).map(\.title) == ["One", "Two", "Three"])
    #expect(TabListLogic.highlightedRow(activeTabID: controller.model.activeTabID, in: controller.model.tabs)
      == parent.tabID)
    let card = controller.rootView.card
    #expect(card.isPeeking)
    #expect(card.pageView === browser.pageView(for: peek.tabID))
    #expect(card.parentPageView === browser.pageView(for: parent.tabID))
    #expect(controller.pageContainerView === card.peekContainer)
    // The URL field shows the Peek's page.
    #expect(URLDisplay.text(for: controller.model.activeTab) == "peek.example")
  }

  @Test func theButtonsIgnoreTheTitleBarsSafeArea() throws {
    // Beside the top of the Peek they sit under the title bar, whose safe
    // area pushed them about 10 pt below Arc's place.
    let host = try #require(controller.rootView.card.peekControls as? NSHostingView<PeekControlsView>)
    #expect(host.safeAreaRegions.isEmpty)
  }

  @Test func theParentPageStaysPutWhenAPeekOpensAndCloses() {
    // Moving a page's view blanks it for a frame, so the parent's stays where
    // it is, in the page holder, and only shrinks.
    browser.addTab(title: "Two", url: "https://two.example/")
    let parent = browser.tabs[0]
    let page = browser.pageView(for: parent.tabID)
    let holder = page?.superview
    #expect(holder != nil)
    browser.openPeek(of: parent.tabID, url: "https://peek.example/")
    #expect(page?.superview === holder)
    controller.closePeek()
    #expect(page?.superview === holder)
  }

  @Test func confirmGrowsOverThePeekOnlyWithoutRoomBesideIt() {
    _ = openPeek()
    let root = controller.rootView
    root.frame = CGRect(x: 0, y: 0, width: 1920, height: 1050)
    root.layoutSubtreeIfNeeded()
    #expect(!controller.model.peekConfirm.growsTowardPeek)
    root.frame = CGRect(x: 0, y: 0, width: 900, height: 700)
    root.layoutSubtreeIfNeeded()
    #expect(controller.model.peekConfirm.growsTowardPeek)
  }

  @Test func selectingTheParentsRowShowsThePeekAgain() {
    let (parent, peek) = openPeek()
    let other = browser.tabs[0].tabID
    controller.activate(tab: other)
    #expect(!controller.rootView.card.isPeeking)
    controller.activate(tab: parent.tabID)
    #expect(browser.commands.last == "activate \(peek.tabID)")
    #expect(controller.rootView.card.isPeeking)
  }

  @Test func thePeekClosesAsSoonAsItsParentIsActive() {
    // The engine drops the closing Peek from its parent's peekID, activates
    // the parent, then closes the Peek once its page has unloaded; the card
    // doesn't wait.
    let (parent, peek) = openPeek()
    browser.beginClosingPeek(of: parent.tabID)
    browser.setActive(parent.tabID)
    #expect(controller.model.tabs.contains { $0.tabID == peek.tabID })
    #expect(!controller.rootView.card.isPeeking)
  }

  @Test func theParentComingBackAnyOtherWayShowsItsPeek() {
    // As when the tab next to it closes: the card shows the pair at once,
    // before the engine activates the Peek, so it doesn't close and reopen.
    let (parent, peek) = openPeek()
    let card = controller.rootView.card
    let other = browser.tabs[0].tabID
    browser.setActive(other)
    #expect(!card.isPeeking)
    browser.setActive(parent.tabID)
    #expect(card.isPeeking)
    #expect(card.pageView === browser.pageView(for: peek.tabID))
    #expect(card.parentPageView === browser.pageView(for: parent.tabID))
  }

  @Test func closeTabsBelowAParentKeepsItsPeek() {
    let (parent, peek) = openPeek()
    #expect(TabListLogic.tabsBelow(parent.tabID, in: controller.model.tabs) == [browser.tabs.last!.tabID])
    controller.closeTabs(below: parent.tabID)
    #expect(controller.model.tabs.contains { $0.tabID == peek.tabID })
    #expect(controller.model.tabs.last?.tabID == peek.tabID)
  }

  @Test func draggingAParentTakesItsPeekAlong() {
    let (parent, peek) = openPeek()
    // Rows [One, Two(+Peek), Three]: Two to the top.
    let index = TabListLogic.stripIndex(movingRow: 1, toRow: 0, in: controller.model.tabs)!
    controller.move(tab: parent.tabID, to: index)
    #expect(controller.model.tabs.prefix(2).map(\.tabID) == [parent.tabID, peek.tabID])
    #expect(TabListLogic.rows(controller.model.tabs).map(\.title) == ["Two", "One", "Three"])
  }

  @Test func closeAndExpandNameTheParent() {
    let (parent, peek) = openPeek()
    controller.closePeek()
    #expect(browser.commands.last == "closePeek \(parent.tabID)")
    #expect(!controller.rootView.card.isPeeking)
    #expect(controller.model.activeTabID == parent.tabID)
    #expect(!controller.model.tabs.contains { $0.tabID == peek.tabID })
    #expect(controller.pageContainerView === controller.rootView.card.activeContainer)
    #expect(controller.pageContainerView !== controller.rootView.card.peekContainer)
  }

  @Test func expandingGivesThePeekARowBelowItsParent() {
    let (parent, peek) = openPeek()
    controller.expandPeek()
    #expect(browser.commands.last == "expandPeek \(parent.tabID)")
    let rows = TabListLogic.rows(controller.model.tabs)
    let parentRow = rows.firstIndex { $0.tabID == parent.tabID }!
    #expect(rows[parentRow + 1].tabID == peek.tabID)
    #expect(controller.model.activeTabID == peek.tabID)
    let card = controller.rootView.card
    #expect(!card.isPeeking)
    #expect(card.pageView === browser.pageView(for: peek.tabID))
  }

  @Test func copyLinkOnTheRowUsesTheParentsPage() {
    let (parent, _) = openPeek()
    NSPasteboard.general.clearContents()
    controller.copyLink(of: parent.tabID)
    #expect(NSPasteboard.general.string(forType: .string) == "https://two.example/")
  }

  @Test func confirmShowsWhileThePageKeptEsc() async {
    _ = openPeek()
    var waited: [TimeInterval] = []
    let (elapsed, done) = AsyncStream.makeStream(of: Void.self)
    controller.model.peekConfirm.wait = { duration in
      waited.append(duration)
      for await _ in elapsed { return }
    }
    browser.keepEscape(for: 1)
    #expect(controller.model.peekConfirm.isShowing)
    // Confirm stays until its time is up, then goes.
    await Task.yield()
    #expect(controller.model.peekConfirm.isShowing)
    done.yield()
    for _ in 0..<100 where controller.model.peekConfirm.isShowing {
      await Task.yield()
    }
    #expect(waited == [1])
    #expect(!controller.model.peekConfirm.isShowing)
  }

  @Test func switchingAwayHidesConfirm() {
    _ = openPeek()
    browser.keepEscape(for: 5)
    controller.activate(tab: browser.tabs[0].tabID)
    #expect(!controller.model.peekConfirm.isShowing)
  }
}
