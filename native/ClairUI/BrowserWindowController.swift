// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import SwiftUI
import os

/// One native browser window (`ClairWindow`, design D3 and D4). Chromium
/// creates the `NSWindow` and the browser; this styles the window, fills it,
/// and keeps `BrowserWindowModel` up to date with what Chromium reports.
final class BrowserWindowController: NSObject, ClairWindow, SidebarActions {
  /// The browser, until Chromium closes the window.
  private(set) var browser: (any ClairBrowser)?
  let window: NSWindow
  let model: BrowserWindowModel
  let rootView: BrowserRootView
  private let preferences: SidebarPreferences

  init(browser: any ClairBrowser, preferences: SidebarPreferences = SidebarPreferences()) {
    self.browser = browser
    self.window = browser.window
    self.preferences = preferences
    let model = BrowserWindowModel(profileKind: browser.profileKind, sidebar: preferences.initialState)
    self.model = model
    let sidebarHost = NSHostingView(rootView: SidebarView(model: model, actions: nil))
    self.rootView = BrowserRootView(model: model, sidebar: sidebarHost)
    super.init()
    sidebarHost.rootView = SidebarView(model: model, actions: self)
    WindowStyle.apply(to: window, profileKind: browser.profileKind)
    window.contentView = rootView
    model.setTabs(browser.tabs)
    model.setExtensionActions(browser.extensionActions)
    model.setDownloads(browser.downloads)
    activeTabDidChange(browser.activeTabID)
  }

  // MARK: ClairWindow

  var pageContainerView: NSView {
    rootView.card.container
  }

  var isSidebarHidden: Bool {
    model.sidebar.isHidden
  }

  func tabsDidChange(_ tabs: [any ClairTab]) {
    model.setTabs(tabs)
  }

  func tabDidChange(_ tab: any ClairTab) {
    model.updateTab(tab)
  }

  func activeTabDidChange(_ tabID: TabID) {
    model.setActiveTab(tabID)
    rootView.card.show(page: browser?.pageView(for: tabID))
    devToolsDidChange()
  }

  func devToolsDidChange() {
    guard let browser else { return }
    rootView.card.show(devTools: browser.devToolsView, layout: browser.devToolsLayout)
  }

  func showCommandBar(mode: CommandBarMode) {
    model.commandBar = mode
  }

  func toggleSidebar() {
    model.sidebar.isHidden.toggle()
    model.sidebar.isRevealed = false
    preferences.remember(model.sidebar)
  }

  func showFind(text: String) {
    model.find = FindState(text: text)
  }

  func hideFind() {
    model.find = nil
  }

  func findResultDidChange(_ result: FindResult) {
    model.find?.result = result
  }

  func statusTextDidChange(_ text: String?) {
    model.statusText = text
  }

  func showToast(_ message: String) {
    model.toast = message
  }

  func pageFullscreenDidChange(_ fullscreen: Bool) {
    model.isPageFullscreen = fullscreen
  }

  func showExclusiveAccessNotice(_ text: String?) {
    model.exclusiveAccessNotice = text
  }

  func anchor(for kind: AnchorKind, indicator: TabIndicators, extensionID: String?) -> BubbleAnchor {
    // Until the sidebar's controls exist, every bubble uses the card's corner.
    let card = rootView.convert(rootView.card.frame, to: nil)
    return BubbleAnchor(
      rect: NSRect(x: card.minX + AnchorPlacement.fallbackInset, y: card.maxY, width: 0, height: 0),
      edge: .bottom)
  }

  func extensionActionsDidChange(_ actions: [any ClairExtensionAction]) {
    model.setExtensionActions(actions)
  }

  func showExtensionPopup(_ view: NSView, size: NSSize, extension extensionID: String, anchor: AnchorKind) {}

  func extensionPopupDidResize(_ size: NSSize) {}

  func closeExtensionPopup() {}

  func downloadsDidChange(_ downloads: [any ClairDownload]) {
    model.setDownloads(downloads)
  }

  func browserDidClose() {
    // The pages belong to Chromium; let go of them and of the browser.
    rootView.card.show(page: nil)
    rootView.card.show(devTools: nil, layout: DevToolsLayout(dockSide: .none, pageBounds: .zero, hidesPage: false))
    browser = nil
  }

  // MARK: SidebarActions

  func activate(tab: TabID) {
    browser?.activate(tab: tab)
  }

  func close(tab: TabID) {
    browser?.close(tab: tab)
  }

  func newTab() {
    showCommandBar(mode: .newTab)
  }
}

/// Where Chromium's bubbles attach when the sidebar isn't shown in place.
enum AnchorPlacement {
  /// Chromium's kNoToolbarLeftOffset.
  static let fallbackInset: CGFloat = 40
}

/// How a native window looks before its content is added (design D4): no
/// title bar, a full-size content view, and the incognito appearance.
enum WindowStyle {
  static func apply(to window: NSWindow, profileKind: ProfileKind) {
    window.styleMask.formUnion([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.toolbar = nil
    window.isMovableByWindowBackground = false
    window.isOpaque = false
    window.backgroundColor = .clear
    window.appearance = profileKind == .incognito ? NSAppearance(named: .darkAqua) : nil
    window.tabbingMode = .disallowed
    window.minSize = NSSize(width: 500, height: 300)
  }
}
