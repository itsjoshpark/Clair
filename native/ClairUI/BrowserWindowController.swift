// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import os

/// One native browser window (`ClairWindow`, design D3 and D4). Chromium
/// creates the `NSWindow` and the browser; this styles the window, fills it,
/// and keeps `BrowserWindowModel` up to date with what Chromium reports.
final class BrowserWindowController: NSObject, ClairWindow {
  /// The browser, until Chromium closes the window.
  private(set) var browser: (any ClairBrowser)?
  let window: NSWindow
  let model: BrowserWindowModel
  private let preferences: SidebarPreferences

  init(browser: any ClairBrowser, preferences: SidebarPreferences = SidebarPreferences()) {
    self.browser = browser
    self.window = browser.window
    self.preferences = preferences
    self.model = BrowserWindowModel(profileKind: browser.profileKind, sidebar: preferences.initialState)
    super.init()
    WindowStyle.apply(to: window, profileKind: browser.profileKind)
    model.setTabs(browser.tabs)
    model.setActiveTab(browser.activeTabID)
    model.setExtensionActions(browser.extensionActions)
    model.setDownloads(browser.downloads)
  }

  // MARK: ClairWindow

  var pageContainerView: NSView {
    window.contentView ?? NSView()
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
  }

  func devToolsDidChange() {}

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

  func anchor(for kind: AnchorKind, indicator: TabIndicators, extensionID: String?) -> Anchor {
    Anchor(rect: .zero, edge: .bottom)
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
    browser = nil
  }
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
  }
}
