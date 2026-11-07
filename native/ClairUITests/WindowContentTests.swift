// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Testing

@testable import ClairUI

/// The native window's content (design D4, D5), against the fake browser.
@MainActor
struct WindowContentTests {
  func makeWindow(tabs: Int = 2) -> (FakeBrowser, BrowserWindowController) {
    let browser = FakeBrowser()
    for index in 0..<tabs {
      browser.addTab(title: "Tab \(index)", url: "https://\(index).example/", at: index, activate: index == 0)
    }
    let controller = BrowserWindowController(
      browser: browser, preferences: SidebarPreferences(defaults: UserDefaults(suiteName: #function)!))
    browser.clairWindow = controller
    return (browser, controller)
  }

  @Test func activePageIsInTheCard() throws {
    let (browser, controller) = makeWindow()
    #expect(browser.window.contentView === controller.rootView)
    let page = try #require(browser.pageView(for: browser.activeTabID))
    #expect(page.superview === controller.pageContainerView)
  }

  @Test func switchingTabsSwapsThePage() throws {
    let (browser, controller) = makeWindow()
    let first = try #require(browser.pageView(for: browser.activeTabID))
    let secondID = browser.tabs[1].tabID
    controller.activate(tab: secondID)
    let second = try #require(browser.pageView(for: secondID))
    #expect(second.superview === controller.pageContainerView)
    #expect(first.superview == nil)
    #expect(controller.model.activeTabID == secondID)
  }

  @Test func closingLetsGoOfThePages() throws {
    let (browser, controller) = makeWindow()
    let page = try #require(browser.pageView(for: browser.activeTabID))
    browser.closeWindow()
    #expect(page.superview == nil)
    #expect(controller.browser == nil)
  }

  @Test func dockedDevToolsSharesTheCard() throws {
    let (browser, controller) = makeWindow()
    let devTools = NSView()
    browser.setDevTools(
      devTools, layout: DevToolsLayout(dockSide: .right, pageBounds: NSRect(x: 0, y: 0, width: 600, height: 700), hidesPage: false))
    #expect(devTools.superview === controller.pageContainerView)
    browser.setDevTools(nil, layout: DevToolsLayout(dockSide: .none, pageBounds: .zero, hidesPage: false))
    #expect(devTools.superview == nil)
  }
}

/// Where the sidebar and card go (design D4, D12).
struct WindowLayoutTests {
  let size = CGSize(width: 1200, height: 800)

  @Test func sidebarShown() {
    let layout = WindowLayout(size: size, sidebar: SidebarState(width: 228), isPageFullscreen: false)
    #expect(layout.sidebar == CGRect(x: 0, y: 0, width: 228, height: 800))
    #expect(layout.card == CGRect(x: 228, y: 10, width: 962, height: 780))
  }

  @Test func sidebarHidden() {
    let layout = WindowLayout(size: size, sidebar: SidebarState(width: 228, isHidden: true), isPageFullscreen: false)
    #expect(layout.card == CGRect(x: 5, y: 5, width: 1190, height: 790))
    #expect(layout.sidebar.maxX <= 0)
  }

  @Test func pageFullscreen() {
    let layout = WindowLayout(size: size, sidebar: SidebarState(width: 228), isPageFullscreen: true)
    #expect(layout.card == CGRect(origin: .zero, size: size))
  }

  @Test func widthStaysInRange() {
    #expect(SidebarState(width: 50).width == 180)
    #expect(SidebarState(width: 900).width == 400)
  }
}

/// The page's place beside docked DevTools: Chromium's
/// ApplyDevToolsContentsResizingStrategy().
struct DevToolsPlacementTests {
  let card = CGSize(width: 1000, height: 800)

  @Test func emptyBoundsFillTheCard() {
    let frame = DevToolsPlacement.pageFrame(
      in: card, layout: DevToolsLayout(dockSide: .right, pageBounds: .zero, hidesPage: false))
    #expect(frame == CGRect(origin: .zero, size: card))
  }

  @Test func dockedRightKeepsDevToolsMinimum() {
    let frame = DevToolsPlacement.pageFrame(
      in: card,
      layout: DevToolsLayout(dockSide: .right, pageBounds: NSRect(x: 0, y: 0, width: 900, height: 800), hidesPage: false))
    #expect(frame == CGRect(x: 0, y: 0, width: 750, height: 800))
  }

  @Test func dockedBottom() {
    let frame = DevToolsPlacement.pageFrame(
      in: card,
      layout: DevToolsLayout(dockSide: .bottom, pageBounds: NSRect(x: 0, y: 0, width: 1000, height: 500), hidesPage: false))
    #expect(frame == CGRect(x: 0, y: 0, width: 1000, height: 500))
  }

  @Test func dockedLeftOffsetsThePage() {
    let frame = DevToolsPlacement.pageFrame(
      in: card,
      layout: DevToolsLayout(dockSide: .left, pageBounds: NSRect(x: 400, y: 0, width: 600, height: 800), hidesPage: false))
    #expect(frame == CGRect(x: 400, y: 0, width: 600, height: 800))
  }

  @Test func hiddenPage() {
    #expect(
      DevToolsPlacement.pageFrame(
        in: card, layout: DevToolsLayout(dockSide: .right, pageBounds: .zero, hidesPage: true)) == nil)
  }
}
