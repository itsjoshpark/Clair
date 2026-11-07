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

  @Test func switchingTabsClosesTheCommandBar() throws {
    let (browser, controller) = makeWindow()
    controller.showCommandBar(mode: .currentTab)
    #expect(controller.model.commandBar != nil)
    controller.activeTabDidChange(controller.model.activeTabID)
    #expect(controller.model.commandBar != nil)
    browser.activate(tab: browser.tabs[1].tabID)
    #expect(controller.model.commandBar == nil)
  }

  @Test func pageFullscreenGivesThePageTheKeyboard() {
    let (browser, controller) = makeWindow()
    controller.pageFullscreenDidChange(true)
    #expect(controller.model.isPageFullscreen)
    #expect(browser.commands.last == "focusPage")
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

/// Where the window controls go (place-traffic-lights-with-appkit D3).
@MainActor
struct WindowControlsTests {
  let size = CGSize(width: 1200, height: 800)

  func controls(_ controller: BrowserWindowController) -> FakeWindow {
    controller.rootView.frame = CGRect(origin: .zero, size: size)
    controller.rootView.needsLayout = true
    controller.rootView.layoutSubtreeIfNeeded()
    return controller.window as! FakeWindow
  }

  func makeController() -> BrowserWindowController {
    let browser = FakeBrowser()
    browser.addTab(title: "Tab", url: "https://example.com/")
    let controller = BrowserWindowController(
      browser: browser, preferences: SidebarPreferences(defaults: UserDefaults(suiteName: "WindowControlsTests")!))
    controller.model.sidebar = SidebarState()
    browser.clairWindow = controller
    return controller
  }

  @Test func shownSidebarPutsThemAtArcsPlace() {
    let window = controls(makeController())
    #expect(window.windowControlsOrigin == CGPoint(x: 13, y: 17))
    #expect(!window.windowControlsHidden)
  }

  @Test func hiddenSidebarHidesThem() {
    let controller = makeController()
    controller.model.sidebar.isHidden = true
    let window = controls(controller)
    #expect(window.windowControlsHidden)
  }

  @Test func revealedSidebarCarriesThem() {
    let controller = makeController()
    controller.model.sidebar.isHidden = true
    controller.model.sidebar.isRevealed = true
    let window = controls(controller)
    #expect(window.windowControlsOrigin == CGPoint(x: 18, y: 22))
    #expect(!window.windowControlsHidden)
  }

  @Test func pageFullscreenHidesThem() {
    let controller = makeController()
    controller.model.isPageFullscreen = true
    let window = controls(controller)
    #expect(window.windowControlsHidden)
  }

  @Test func halfHiddenSidebarSlidesThem() {
    let layout = WindowLayout.blended(size: size, width: 228, shown: 0.5)
    let placement = WindowControlsPlacement(sidebar: layout.sidebar, isPageFullscreen: false)
    #expect(placement.origin == CGPoint(x: -101, y: 17))
    #expect(!placement.isHidden)
  }

  @Test func unchangedPlaceIsNotSetAgain() {
    let window = FakeWindow()
    let placement = WindowControlsPlacement(sidebar: CGRect(x: 0, y: 0, width: 228, height: 800), isPageFullscreen: false)
    placement.apply(to: window)
    placement.apply(to: window)
    #expect(window.originSets == 1)
    #expect(window.windowControlsOrigin == CGPoint(x: 13, y: 17))
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
    #expect(SidebarState(width: 50).width == 164)
    #expect(SidebarState(width: 900).width == 500)
  }

  @Test func blendedLayoutIsHalfway() {
    let layout = WindowLayout.blended(size: size, width: 228, shown: 0.5)
    #expect(layout.sidebar.minX == -114)
    #expect(layout.card == CGRect(x: 116.5, y: 7.5, width: 1076, height: 785))
  }

  @Test func revealedSidebarSlidesInFromTheEdge() {
    let away = WindowLayout.revealedSidebar(size: size, width: 228, revealed: 0)
    let shown = WindowLayout.revealedSidebar(size: size, width: 228, revealed: 1)
    #expect(away.maxX < 0)
    #expect(shown == CGRect(x: 5, y: 5, width: 228, height: 790))
  }

  @Test func compactTopRowBelowArcsThreshold() {
    #expect(SidebarState(width: 213).hasCompactTopRow)
    #expect(!SidebarState(width: 214).hasCompactTopRow)
  }

  @Test func hideSidebarButtonMakesRoomInANarrowRow() {
    #expect(TopRow.hideSidebarX(width: 228) == 77)
    #expect(TopRow.hideSidebarX(width: 214) == 74)
  }
}

struct SpringValueTests {
  @Test func settlesOnItsTarget() {
    var value = SpringValue(0)
    value.animate(to: 1, at: 0)
    #expect(value.isMoving)
    value.step(at: 0.05)
    #expect(value.value > 0 && value.value < 1)
    let moving = value.step(at: 5)
    #expect(!moving)
    #expect(value.value == 1)
  }

  @Test func turningAroundStartsFromWhereItIs() {
    var value = SpringValue(0)
    value.animate(to: 1, at: 0)
    value.step(at: 0.05)
    let midway = value.value
    value.animate(to: 0, at: 0.05)
    value.step(at: 0.05)
    #expect(abs(value.value - midway) < 0.001)
  }

  @Test func jumpStops() {
    var value = SpringValue(0)
    value.animate(to: 1, at: 0)
    value.jump(to: 0)
    #expect(!value.isMoving)
    #expect(value.value == 0)
  }
}

@MainActor
struct MainMenuTitlesTests {
  @Test func renamesOpenLocation() {
    let menu = NSMenu()
    let file = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
    file.submenu = NSMenu()
    let item = NSMenuItem(title: "Open Location…", action: nil, keyEquivalent: "l")
    item.tag = MainMenuTitles.focusLocationTag
    file.submenu?.addItem(item)
    menu.addItem(file)
    MainMenuTitles.apply(to: menu)
    #expect(item.title == "Open Location Bar")
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
