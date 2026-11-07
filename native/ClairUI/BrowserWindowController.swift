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
final class BrowserWindowController: NSObject, ClairWindow, SidebarActions, OverlayActions {
  static let toastDuration: Duration = .seconds(3)

  /// The browser, until Chromium closes the window.
  private(set) var browser: (any ClairBrowser)?
  let window: NSWindow
  let model: BrowserWindowModel
  let rootView: BrowserRootView
  private let sidebarHost: NSHostingView<SidebarView>
  private let preferences: SidebarPreferences
  /// The sidebar's controls, in its hosting view's coordinates.
  private var controlFrames: [AnchorControl: CGRect] = [:]
  private var extensionPopup: ExtensionPopupWindow?
  nonisolated(unsafe) private var observers: [any NSObjectProtocol] = []

  init(browser: any ClairBrowser, preferences: SidebarPreferences = SidebarPreferences()) {
    self.browser = browser
    self.window = browser.window
    self.preferences = preferences
    let model = BrowserWindowModel(profileKind: browser.profileKind, sidebar: preferences.initialState)
    self.model = model
    sidebarHost = NSHostingView.edgeToEdge(rootView: SidebarView(model: model, actions: nil))
    rootView = BrowserRootView(model: model, sidebar: sidebarHost)
    super.init()
    sidebarHost.rootView = SidebarView(model: model, actions: self)
    rootView.onScrimClick = { [weak self] in self?.model.commandBar?.cancel() }
    rootView.resizeHandle.currentWidth = { [weak model] in model?.sidebar.width ?? SidebarState.defaultWidth }
    rootView.resizeHandle.onResize = { [weak self] width, done in
      guard let self else { return }
      self.model.sidebar.width = max(width, self.model.windowControls.narrowestSidebar)
      if done { self.preferences.remember(self.model.sidebar) }
    }
    WindowStyle.apply(to: window, profileKind: browser.profileKind)
    window.contentView = rootView
    model.isWindowKey = window.isKeyWindow
    observeWindow()
    observeOverlays()
    model.setTabs(browser.tabs)
    model.setExtensionActions(browser.extensionActions)
    model.setDownloads(browser.downloads)
    activeTabDidChange(browser.activeTabID)
  }

  private func observeWindow() {
    let center = NotificationCenter.default
    for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
      observers.append(
        center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
          MainActor.assumeIsolated {
            guard let self else { return }
            self.model.isWindowKey = self.window.isKeyWindow
          }
        })
    }
    for name in [NSWindow.didResizeNotification, NSWindow.didEnterFullScreenNotification,
                 NSWindow.didExitFullScreenNotification] {
      observers.append(
        center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
          MainActor.assumeIsolated {
            self?.rootView.needsLayout = true
            self?.extensionPopup?.dismiss()
          }
        })
    }
  }

  /// Shows and hides the overlays as the model changes.
  private func observeOverlays() {
    withObservationTracking {
      updateOverlays()
    } onChange: { [weak self] in
      Task { @MainActor in self?.observeOverlays() }
    }
  }

  private func updateOverlays() {
    let model = self.model
    // The command bar.
    if let commandBar = model.commandBar {
      if (rootView.commandBarHost as? NSHostingView<CommandBarView>)?.rootView.model !== commandBar {
        let host = NSHostingView.edgeToEdge(rootView: CommandBarView(model: commandBar))
        rootView.commandBarHost = host
        window.makeFirstResponder(host)
      }
    } else if rootView.commandBarHost != nil {
      rootView.commandBarHost = nil
    }
    // Find.
    if model.find != nil {
      if rootView.findHost == nil {
        let host = NSHostingView.edgeToEdge(rootView: FindFieldView(model: model, actions: self))
        rootView.findHost = host
        window.makeFirstResponder(host)
      }
    } else if rootView.findHost != nil {
      rootView.findHost = nil
    }
    // The link status.
    if let status = model.statusText, model.commandBar == nil {
      rootView.statusHost = NSHostingView.edgeToEdge(rootView: CapsuleText(text: status, identifier: "clair.status"))
    } else if rootView.statusHost != nil {
      rootView.statusHost = nil
    }
    // Toasts.
    if let toast = model.toast {
      rootView.toastHost = NSHostingView(
        rootView: CapsuleText(text: toast.message, font: .system(size: 13, weight: .medium), identifier: "clair.toast"))
    } else if rootView.toastHost != nil {
      rootView.toastHost = nil
    }
    // The full-screen notice.
    if let notice = model.exclusiveAccessNotice {
      rootView.noticeHost = NSHostingView.edgeToEdge(
        rootView: CapsuleText(text: notice, font: .system(size: 13, weight: .medium), identifier: "clair.fullscreenNotice"))
    } else if rootView.noticeHost != nil {
      rootView.noticeHost = nil
    }
    // The active tab's infobars and crashed page.
    let tab = model.activeTab
    if let tab, !tab.infobars.isEmpty {
      rootView.card.infobarView = NSHostingView.edgeToEdge(rootView: InfobarsView(tab: tab, actions: self))
    } else if rootView.card.infobarView != nil {
      rootView.card.infobarView = nil
    }
    if tab?.isCrashed == true {
      if rootView.card.crashedView == nil {
        rootView.card.crashedView = NSHostingView.edgeToEdge(rootView: CrashedPageView(actions: self))
      }
    } else if rootView.card.crashedView != nil {
      rootView.card.crashedView = nil
    }
  }

  deinit {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
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
    // The command bar belongs to the tab it opened on; another tab coming to
    // the front, from the command bar or not, closes it.
    if tabID != model.activeTabID {
      model.commandBar?.cancel()
    }
    model.setActiveTab(tabID)
    rootView.card.show(page: browser?.pageView(for: tabID))
    devToolsDidChange()
  }

  func devToolsDidChange() {
    guard let browser else { return }
    rootView.card.show(devTools: browser.devToolsView, layout: browser.devToolsLayout)
  }

  func showCommandBar(mode: CommandBarMode) {
    guard let browser else { return }
    if let open = model.commandBar {
      // The same shortcut again closes it, as in Arc.
      open.cancel()
      if open.mode == mode { return }
    }
    let text = mode == .currentTab ? URLDisplay.editingText(for: model.activeTab) : ""
    model.commandBar = CommandBarModel(mode: mode, text: text, browser: browser) { [weak self] opened in
      guard let self else { return }
      self.model.commandBar = nil
      if !opened {
        self.browser?.focusPage()
      }
    }
  }

  func toggleSidebar() {
    model.sidebar.isHidden.toggle()
    model.sidebar.isRevealed = false
    preferences.remember(model.sidebar)
  }

  func showFind(text: String) {
    if model.find == nil {
      model.find = FindState(text: text)
    } else {
      model.findFocusRequest += 1
      if let host = rootView.findHost {
        window.makeFirstResponder(host)
      }
    }
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
    let toast = Toast(message: message)
    model.toast = toast
    Task { [weak self] in
      try? await Task.sleep(for: Self.toastDuration)
      if self?.model.toast?.id == toast.id {
        self?.model.toast = nil
      }
    }
  }

  func pageFullscreenDidChange(_ fullscreen: Bool) {
    model.isPageFullscreen = fullscreen
    // Esc ends page full screen only when it reaches the page, so the page
    // takes the keyboard from the sidebar or an overlay.
    if fullscreen {
      model.commandBar?.cancel()
      if model.find != nil {
        browser?.stopFinding()
      }
      browser?.focusPage()
    }
  }

  func showExclusiveAccessNotice(_ text: String?) {
    model.exclusiveAccessNotice = text
  }

  func anchor(for kind: AnchorKind, indicator: TabIndicators, extensionID: String?) -> BubbleAnchor {
    rootView.layoutSubtreeIfNeeded()
    var controls: [AnchorControl: CGRect] = [:]
    for (control, frame) in controlFrames {
      controls[control] = sidebarHost.convert(frame, to: nil)
    }
    let resolver = AnchorResolver(
      sidebarInPlace: model.sidebar.isShownInPlace && !model.isPageFullscreen && !isWindowFullscreen,
      controls: controls,
      card: rootView.convert(rootView.card.frame, to: nil))
    return resolver.anchor(for: kind, indicator: indicator, extensionID: extensionID)
  }

  private var isWindowFullscreen: Bool {
    window.styleMask.contains(.fullScreen)
  }

  func extensionActionsDidChange(_ actions: [any ClairExtensionAction]) {
    model.setExtensionActions(actions)
  }

  func showExtensionPopup(_ view: NSView, size: NSSize, extension extensionID: String, anchor: AnchorKind) {
    extensionPopup?.dismiss(notify: false)
    let anchorRect = self.anchor(for: anchor, indicator: [], extensionID: extensionID).rect
    let popup = ExtensionPopupWindow(page: view, size: size, parent: window, anchor: anchorRect) { [weak self] in
      self?.extensionPopup = nil
      self?.browser?.extensionPopupDidClose()
    }
    extensionPopup = popup
    popup.present()
  }

  func extensionPopupDidResize(_ size: NSSize) {
    extensionPopup?.resize(to: size)
  }

  func closeExtensionPopup() {
    extensionPopup?.dismiss(notify: false)
    extensionPopup = nil
  }

  func downloadsDidChange(_ downloads: [any ClairDownload]) {
    model.setDownloads(downloads)
  }

  func browserDidClose() {
    // The pages belong to Chromium; let go of them and of the browser.
    model.commandBar?.cancel()
    closeExtensionPopup()
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

  func closeTabs(below tab: TabID) {
    browser?.closeTabs(below: tab)
  }

  func duplicate(tab: TabID) {
    browser?.duplicate(tab: tab)
  }

  func setMuted(_ muted: Bool, tab: TabID) {
    browser?.setMuted(muted, tab: tab)
  }

  func copyLink(of tab: TabID) {
    guard let tab = model.tabs.first(where: { $0.tabID == tab }), let link = TabListLogic.link(of: tab) else {
      return
    }
    copyToPasteboard(link)
    showToast("Copied Link")
  }

  func move(tab: TabID, to index: Int) {
    browser?.move(tab: tab, to: index)
  }

  func newTab() {
    showCommandBar(mode: .newTab)
  }

  func goBack() {
    browser?.goBack()
  }

  func goForward() {
    browser?.goForward()
  }

  func reloadOrStop() {
    if model.activeTab?.isLoading == true {
      browser?.stop()
    } else {
      browser?.reload()
    }
  }

  func editURL() {
    showCommandBar(mode: .currentTab)
  }

  func copyURL() {
    guard let tab = model.activeTab, let link = TabListLogic.link(of: tab) else { return }
    copyToPasteboard(link)
    showToast("Copied URL")
  }

  private func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  func showSiteControls(indicator: TabIndicators) {
    browser?.showPageInfo(at: indicator.isEmpty ? .siteControls : .indicator, indicator: indicator)
  }

  func runExtension(_ extensionID: String, pinned: Bool) {
    browser?.runExtensionAction(extensionID, anchor: pinned ? .extensionAction : .extensionsButton)
  }

  func setExtension(_ extensionID: String, pinned: Bool) {
    browser?.setExtensionAction(extensionID, pinned: pinned)
  }

  func openDownload(_ downloadID: String) {
    browser?.openDownload(downloadID)
  }

  func showDownloadInFinder(_ downloadID: String) {
    browser?.showDownloadInFinder(downloadID)
  }

  func cancelDownload(_ downloadID: String) {
    browser?.cancelDownload(downloadID)
  }

  func resumeDownload(_ downloadID: String) {
    browser?.resumeDownload(downloadID)
  }

  func keepDownload(_ downloadID: String) {
    browser?.keepDownload(downloadID)
  }

  func discardDownload(_ downloadID: String) {
    browser?.discardDownload(downloadID)
  }

  func downloadsListOpened() {
    browser?.markDownloadsSeen()
  }

  func openDownloadsPage() {
    if let url = URL(string: "chrome://downloads/") {
      browser?.open(url, disposition: .newForegroundTab)
    }
  }

  func controlFramesChanged(_ frames: [AnchorControl: CGRect]) {
    controlFrames = frames
  }

  // MARK: OverlayActions

  func find(_ text: String, forward: Bool) {
    model.find?.text = text
    browser?.find(text, forward: forward)
  }

  func closeFind() {
    model.find = nil
    browser?.stopFinding()
  }

  func infobar(_ infobarID: Int, didChoose action: InfobarAction) {
    browser?.infobar(infobarID, tab: model.activeTabID, didChoose: action)
  }

  func reloadCrashedPage() {
    browser?.reload()
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
    window.minSize = NSSize(width: 500, height: 300)
  }
}
