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
final class BrowserWindowController: NSObject, ClairWindow, SidebarActions, OverlayActions, PeekActions,
  SpacesModelListener
{
  static let toastDuration: Duration = .seconds(3)

  /// Every window's controller, for app-wide menus such as Extensions.
  private static let all = NSHashTable<BrowserWindowController>.weakObjects()

  /// The main window's controller, or else a visible window's.
  static var main: BrowserWindowController? {
    let open = all.allObjects.filter { $0.browser != nil }
    return open.first { $0.window === NSApp.mainWindow } ?? open.first { $0.window.isVisible }
  }

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
  /// The window's dialogs (add-clair-dialogs D1), for every dialog on it.
  private(set) lazy var dialogs = ClairDialogPresenter(window: window)
  private lazy var extensionPrompts = ExtensionPromptSheets(dialogs: dialogs) { [weak self] promptID, accepted in
    self?.browser?.answerExtensionPrompt(promptID, accepted: accepted)
  }
  nonisolated(unsafe) private var observers: [any NSObjectProtocol] = []
  /// Dragging the window from the top of the page (drag-window-from-page-top).
  private let dragPreference: WindowDragPreference
  /// Whether Shift+click opens a Peek (add-peek design D10).
  private let peekPreference: PeekPreference
  /// Watches the rest of a press once the window server has its window drag.
  private var safetyNetMonitor: Any?
  private var safetyNet = WindowDragSafetyNet()
  /// Watches for Delete while the command bar is open.
  private var commandBarKeyMonitor: Any?
  /// When the link status capsule shows and hides.
  private var statusState = StatusCapsuleState()
  private var statusTimer: Task<Void, Never>?

  /// `spaces` is the app's model of Spaces, the running native layer's when
  /// nil.
  init(
    browser: any ClairBrowser, spaces: SpacesModel? = nil, preferences: SidebarPreferences = SidebarPreferences(),
    dragPreference: WindowDragPreference = WindowDragPreference(),
    peekPreference: PeekPreference = PeekPreference()
  ) {
    self.browser = browser
    self.window = browser.window
    self.preferences = preferences
    self.dragPreference = dragPreference
    self.peekPreference = peekPreference
    let spaces = spaces ?? NativeLayer.current?.spaces ?? .detached
    let model = BrowserWindowModel(
      profileKind: browser.profileKind, sidebar: preferences.initialState, browserID: browser.browserID,
      shownSpaceID: browser.shownSpaceID, spaces: spaces)
    self.model = model
    sidebarHost = NSHostingView.edgeToEdge(rootView: SidebarView(model: model, actions: nil))
    rootView = BrowserRootView(model: model, sidebar: sidebarHost)
    super.init()
    Self.all.add(self)
    sidebarHost.rootView = SidebarView(model: model, actions: self)
    rootView.onScrimClick = { [weak self] in self?.model.commandBar?.cancel() }
    rootView.onCopyURL = { [weak self] in self?.copyURL() }
    rootView.canCopyURL = { [weak self] in
      guard let tab = self?.model.activeTab else { return false }
      return TabListLogic.link(of: tab) != nil && !tab.isNewTabPage
    }
    // The popup in the card's corner stays; it's empty while nothing shows.
    let noticeHost = SelfSizingHostingView(rootView: NoticePopupView(state: model.notice))
    noticeHost.hitInset = NoticePopupView.margin
    rootView.noticeHost = noticeHost
    noticeHost.rootView = NoticePopupView(state: model.notice) { [weak self, weak noticeHost] url in
      guard self != nil, let noticeHost else { return }
      NSSharingServicePicker(items: [url]).show(relativeTo: noticeHost.bounds, of: noticeHost, preferredEdge: .minY)
    }
    rootView.resizeHandle.currentWidth = { [weak model] in model?.sidebar.width ?? SidebarState.defaultWidth }
    rootView.resizeHandle.onResize = { [weak self] width, done in
      guard let self else { return }
      self.model.sidebar.width = max(width, self.model.windowControls.narrowestSidebar)
      if done { self.preferences.remember(self.model.sidebar) }
    }
    // The Peek's buttons, and a click beside it, close or expand it
    // (add-peek design D4).
    let peekControls = NSHostingView(rootView: PeekControlsView(confirm: model.peekConfirm, actions: self))
    // Near the window's top edge the title bar's safe area pushed the
    // buttons about 10 pt down from Arc's place.
    peekControls.safeAreaRegions = []
    peekControls.sizingOptions = []
    rootView.card.peekControls = peekControls
    rootView.card.peekClickCatcher.onClick = { [weak self] in self?.closePeek() }
    rootView.card.onConfirmDirectionChange = { [weak model] towardPeek in
      model?.peekConfirm.growsTowardPeek = towardPeek
    }
    WindowStyle.apply(to: window, profileKind: browser.profileKind)
    window.contentView = rootView
    model.isWindowKey = window.isKeyWindow
    observeWindow()
    observeOverlays()
    setUpWindowDrag()
    spaces.addListener(self)
    model.reloadTabs()
    model.setExtensionActions(browser.extensionActions)
    model.setDownloads(browser.downloads, progress: browser.downloadProgress)
    stillDidChange()
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
            self.offerCommandBarIfNew()
          }
        })
    }
    observers.append(
      center.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.extensionPopup?.dismiss() }
      })
    for name in [NSWindow.didResizeNotification, NSWindow.didEnterFullScreenNotification,
                 NSWindow.didExitFullScreenNotification] {
      observers.append(
        center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
          MainActor.assumeIsolated {
            guard let self else { return }
            self.model.isWindowFullscreen = self.isWindowFullscreen
            self.rootView.needsLayout = true
            self.extensionPopup?.dismiss()
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
        // Lays the window out again as results come and go, so the panel
        // keeps its top and grows downwards (design D18).
        let host = SelfSizingHostingView(rootView: CommandBarView(model: commandBar))
        rootView.commandBarHost = host
        window.makeFirstResponder(host)
      }
    } else if rootView.commandBarHost != nil {
      rootView.commandBarHost = nil
    }
    // Only keyword mode needs Delete watched (see leavesKeywordMode).
    if model.commandBar?.keywordName != nil {
      startCommandBarKeyMonitor()
    } else {
      stopCommandBarKeyMonitor()
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
    reportStatus(model.commandBar == nil ? model.statusText : nil, commandBarOpen: model.commandBar != nil)
    // Toasts.
    if let toast = model.toast {
      rootView.toastHost = NSHostingView(
        rootView: CapsuleText(text: toast.message, font: .system(size: 13, weight: .medium), identifier: "clair.toast"))
    } else if rootView.toastHost != nil {
      rootView.toastHost = nil
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

  // MARK: The link status (design D18)

  /// Hands Chromium's link status to the capsule's timing rules, once per
  /// change; the command bar hides the capsule at once.
  private func reportStatus(_ text: String?, commandBarOpen: Bool) {
    guard text != statusState.reportedText || (commandBarOpen && statusState.shownText != nil) else { return }
    if commandBarOpen {
      statusState.reset()
    } else {
      statusState.report(text, at: ProcessInfo.processInfo.systemUptime)
    }
    applyStatus()
  }

  /// Shows what the capsule's state says, and waits for its next change.
  private func applyStatus() {
    statusTimer?.cancel()
    statusTimer = nil
    if let text = statusState.shownText {
      let capsule = CapsuleText(text: text, identifier: "clair.status")
      if let host = rootView.statusHost as? SelfSizingHostingView<CapsuleText> {
        host.rootView = capsule
        fade(host, to: 1)
      } else {
        let host = SelfSizingHostingView(rootView: capsule)
        host.alphaValue = 0
        rootView.statusHost = host
        fade(host, to: 1)
      }
    } else if let host = rootView.statusHost {
      fade(host, to: 0) { [weak self, weak host] in
        guard let self, let host, self.statusState.shownText == nil, self.rootView.statusHost === host else { return }
        self.rootView.statusHost = nil
      }
    }
    if let deadline = statusState.deadline {
      statusTimer = Task { [weak self] in
        try? await Task.sleep(for: .seconds(max(0, deadline - ProcessInfo.processInfo.systemUptime)))
        guard !Task.isCancelled, let self else { return }
        if self.statusState.tick(at: max(deadline, ProcessInfo.processInfo.systemUptime)) {
          self.applyStatus()
        }
      }
    }
  }

  private func fade(_ view: NSView, to alpha: CGFloat, completion: (@MainActor () -> Void)? = nil) {
    guard view.alphaValue != alpha else {
      completion?()
      return
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.15
      view.animator().alphaValue = alpha
    } completionHandler: {
      MainActor.assumeIsolated { completion?() }
    }
  }

  deinit {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  // MARK: Dragging the window from the top of the page

  private func setUpWindowDrag() {
    let strip = rootView.card.dragStrip
    strip.isEnabled = { [weak self] in
      guard let self else { return false }
      return self.dragPreference.isEnabled && !self.model.isPageFullscreen && !self.isWindowFullscreen
    }
    strip.onDragWindow = { [weak self] event in self?.dragWindow(with: event) }
    rootView.topInset.onDoubleClick = { [weak self] in self?.titleBarDoubleClicked() }
  }

  private func dragWindow(with event: NSEvent) {
    removeSafetyNet()
    safetyNet = WindowDragSafetyNet()
    safetyNetMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDragged, .leftMouseUp, .leftMouseDown]
    ) { [weak self] event in
      let keeps = MainActor.assumeIsolated { self?.keepsFromPage(event) ?? false }
      return keeps ? nil : event
    }
    window.performDrag(with: event)
  }

  /// Keeps the page from a press whose window drag didn't start (design D1,
  /// step 3).
  private func keepsFromPage(_ event: NSEvent) -> Bool {
    guard event.window === window else { return false }
    switch event.type {
    case .leftMouseDragged:
      safetyNet.drag(dx: event.deltaX, dy: event.deltaY)
      return true
    case .leftMouseUp:
      removeSafetyNet()
      return safetyNet.keepsRelease
    default:
      removeSafetyNet()
      return false
    }
  }

  /// Delete in the command bar's empty field leaves keyword mode, as in the
  /// omnibox. The field editor takes Delete before SwiftUI's key handlers
  /// and shortcuts see it, so it's caught here, before the window sends it.
  private func startCommandBarKeyMonitor() {
    guard commandBarKeyMonitor == nil else { return }
    commandBarKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      let handled = MainActor.assumeIsolated { self?.leavesKeywordMode(event) ?? false }
      return handled ? nil : event
    }
  }

  private func stopCommandBarKeyMonitor() {
    if let commandBarKeyMonitor {
      NSEvent.removeMonitor(commandBarKeyMonitor)
    }
    commandBarKeyMonitor = nil
  }

  private func leavesKeywordMode(_ event: NSEvent) -> Bool {
    // A fresh press of Delete (kVK_Delete, 51) without modifiers: holding
    // Delete to clear the query stops at the empty field.
    guard event.window === window, event.keyCode == 51, !event.isARepeat,
      event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]),
      let commandBar = model.commandBar, let host = rootView.commandBarHost,
      // In the command bar's own field, not another one such as Find, and
      // not while an input method is composing text there.
      let editor = window.firstResponder as? NSTextView,
      (editor.delegate as? NSView)?.isDescendant(of: host) == true,
      !editor.hasMarkedText(), editor.string.isEmpty
    else {
      return false
    }
    return commandBar.deleteBackwardInEmptyField()
  }

  private func removeSafetyNet() {
    if let safetyNetMonitor {
      NSEvent.removeMonitor(safetyNetMonitor)
    }
    safetyNetMonitor = nil
  }

  // MARK: ClairWindow

  var pageContainerView: NSView {
    // The Peek's container while a Peek shows, so its dialogs centre on it
    // (add-peek design D4).
    rootView.card.activeContainer
  }

  var isSidebarHidden: Bool {
    model.sidebar.isHidden
  }

  var opensPeekOnShiftClick: Bool {
    peekPreference.isEnabled
  }

  func peekDidKeepEscape(for duration: TimeInterval) {
    model.peekConfirm.show(for: duration)
  }

  // MARK: Spaces and their tabs (add-spaces design D10)

  func shownSpaceDidChange(_ spaceID: SpaceID, from previousSpaceID: SpaceID?) {
    // The earlier Space's header and rows slide out as the new one's slide
    // in, unless Reduce Motion is on (D10).
    // Nor from a Space that's gone: there's no header to slide out, and no
    // place in the order to tell the side from.
    // A window of another profile that the group swaps in (add-profiles
    // D12) didn't show the earlier Space: it draws it from the model, and
    // takes the outgoing window's sidebar (D3). The engine tells it before
    // it orders the window in.
    let swappedIn = previousSpaceID != nil && previousSpaceID != model.shownSpaceID
    let outgoing = swappedIn ? previousSpaceID.flatMap(swapSource(showing:)) : nil
    if let outgoing {
      model.sidebar.width = outgoing.model.sidebar.width
      model.sidebar.isHidden = outgoing.model.sidebar.isHidden
      model.sidebar.isRevealed = false
    }
    if let previousSpaceID, previousSpaceID != spaceID, model.showsSpaces, window.isVisible || swappedIn,
      let previousSpace = model.spaces.space(previousSpaceID),
      !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    {
      model.spaceSlide = SpaceSlide(
        fromSpace: previousSpace, fromTabs: swappedIn ? model.spaces.tabs(inSpace: previousSpaceID) : model.tabs,
        fromTrailing: SpacesLogic.slidesFromTrailing(to: spaceID, from: previousSpaceID, in: model.spaces.spaces))
    } else {
      model.spaceSlide = nil
    }
    model.spaceHeaderEdit = nil
    model.newSpaceForm = nil
    model.setShownSpace(spaceID)
    tabsChanged()
    if let outgoing {
      takeManageSpaces(from: outgoing)
    }
  }

  /// The window of the group this one is swapped in for, which shows
  /// `spaceID`: the key one, as the user switched there, or else one already
  /// ordered out.
  private func swapSource(showing spaceID: SpaceID) -> BrowserWindowController? {
    let candidates = Self.all.allObjects.filter {
      $0 !== self && $0.browser != nil && $0.model.spaces === model.spaces && $0.model.shownSpaceID == spaceID
    }
    // With a dialog up, its sheet is key and the window main.
    return candidates.first { $0.window.isKeyWindow || $0.window.isMainWindow }
      ?? candidates.first { !$0.window.isVisible }
  }

  /// D12: a dialog follows a swap. When the group swaps from a window with
  /// Manage Spaces open, as when the shown Space's profile changes there,
  /// this window presents it again with the same selection.
  private func takeManageSpaces(from other: BrowserWindowController) {
    guard dialogs.showing == nil, let state = other.openManageSpaces else { return }
    other.closeManageSpaces()
    ManageSpacesDialog.show(for: self, state: state)
  }

  /// The Manage Spaces dialog on the window, if it's open.
  private(set) var openManageSpaces: ManageSpacesState?
  private weak var manageSpacesDialog: ClairDialog?

  /// Manage Spaces opened on the window.
  func manageSpacesDidOpen(_ state: ManageSpacesState, dialog: ClairDialog) {
    openManageSpaces = state
    manageSpacesDialog = dialog
  }

  /// Manage Spaces closed, or moved to another window.
  func manageSpacesDidClose(_ state: ManageSpacesState) {
    if openManageSpaces === state {
      openManageSpaces = nil
      manageSpacesDialog = nil
    }
  }

  private func closeManageSpaces() {
    if let dialog = manageSpacesDialog {
      openManageSpaces = nil
      manageSpacesDialog = nil
      dialogs.dismiss(dialog)
    }
  }

  func spaceTabsDidChange(_ spaceID: SpaceID) {
    guard spaceID == model.shownSpaceID else { return }
    model.reloadTabs()
    tabsChanged()
  }

  func spaceTabDidChange(_ tab: any ClairTab) {
    guard tab.spaceID == model.shownSpaceID, !model.listsOwnTabsOnly || tab.browserID == model.browserID else {
      return
    }
    tabChanged(tab)
  }

  func spacesDidChange() {}

  /// The window's rows were added, closed or moved, or it shows another
  /// Space.
  private func tabsChanged() {
    // A Peek opened, closed or expanded.
    showPages()
    model.reloadStop.loadingChanged(model.activeTab?.isLoading == true)
    rootView.loadingIndicator.loadingChanged(model.activeTab?.isLoading == true)
  }

  private func tabChanged(_ tab: any ClairTab) {
    model.updateTab(tab)
    if tab.tabID == model.activeTabID {
      model.reloadStop.loadingChanged(tab.isLoading)
      rootView.loadingIndicator.loadingChanged(tab.isLoading)
    }
    offerCommandBarIfNew()
    // The command bar a new window opened with gives way to a page that
    // loads without it, as a link from another app.
    if let offered = offeredCommandBar, offered === model.commandBar, tab.tabID == model.activeTabID,
      !tab.isNewTabPage, offered.text.isEmpty {
      offered.cancel()
    }
  }

  // MARK: The command bar in a new window (design D18)

  /// Whether the window may still open the command bar for its first tab.
  private var offersCommandBar = true
  private weak var offeredCommandBar: CommandBarModel?

  /// Opens the command bar once, when the window first shows a single new tab
  /// page, so typing goes straight into it, as in Arc.
  private func offerCommandBarIfNew() {
    guard offersCommandBar, window.isKeyWindow, let tab = model.activeTab else { return }
    // A new tab has no URL until its first navigation starts.
    guard tab.isNewTabPage || !(tab.urlText.isEmpty && (tab.url?.absoluteString ?? "").isEmpty) else { return }
    offersCommandBar = false
    guard model.tabs.count == 1, tab.isNewTabPage, model.commandBar == nil else { return }
    editURL()
    offeredCommandBar = model.commandBar
  }

  // MARK: The still (share-tabs-across-windows D2)

  func stillDidChange() {
    guard let browser else { return }
    let wasShowing = model.isShowingStill
    model.setStill(browser.stillTabID, image: browser.stillImage)
    if model.isShowingStill && !wasShowing {
      // The command bar belonged to the page that left.
      model.commandBar?.cancel()
    }
    rootView.card.showStill(model.isShowingStill, image: model.stillImage)
    model.reloadStop.loadingChanged(model.activeTab?.isLoading == true)
    rootView.loadingIndicator.loadingChanged(model.activeTab?.isLoading == true)
  }

  func activeTabDidChange(_ tabID: TabID) {
    // The command bar belongs to the tab it opened on; another tab coming to
    // the front, from the command bar or not, closes it.
    let switched = tabID != model.activeTabID
    if switched {
      model.commandBar?.cancel()
    }
    model.setActiveTab(tabID)
    if switched {
      model.reloadStop.tabSwitched(isLoading: model.activeTab?.isLoading == true)
      rootView.loadingIndicator.tabSwitched(isLoading: model.activeTab?.isLoading == true)
    }
    showPages()
    devToolsDidChange()
    offerCommandBarIfNew()
  }

  /// What the card shows: the active tab's page, or a Peek over its parent's
  /// (add-peek design D4).
  private func showPages() {
    let shown = TabListLogic.shownPeek(activeTabID: model.activeTabID, in: model.tabs)
    if shown?.peekID != shownPeek?.peekID {
      model.peekConfirm.hide()
    }
    shownPeek = shown
    if let shown {
      rootView.card.show(page: browser?.pageView(for: shown.peekID), behind: browser?.pageView(for: shown.parentID))
    } else {
      rootView.card.show(page: browser?.pageView(for: model.activeTabID), behind: nil)
    }
    rootView.needsLayout = true
  }

  /// The Peek the card shows, if any.
  private var shownPeek: TabListLogic.ShownPeek?

  // MARK: PeekActions

  func closePeek() {
    guard let shownPeek else { return }
    browser?.closePeek(of: shownPeek.parentID)
  }

  func expandPeek() {
    guard let shownPeek else { return }
    browser?.expandPeek(of: shownPeek.parentID)
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

  /// Does what System Settings says a title bar double-click does.
  func titleBarDoubleClicked() {
    guard !isWindowFullscreen, !model.isPageFullscreen else { return }
    TitleBarDoubleClickAction.current().perform(on: window)
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

  /// Chromium's "Press Esc to exit full screen", in the same popup as Copy
  /// URL's (design D18), for as long as Chromium shows it.
  func showExclusiveAccessNotice(_ text: String?) {
    model.exclusiveAccessNotice = text
    if let text {
      model.notice.show(Notice(text: text, identifier: Self.fullscreenNoticeID), for: nil)
    } else if model.notice.notice?.identifier == Self.fullscreenNoticeID {
      model.notice.hide()
    }
  }

  static let fullscreenNoticeID = "clair.fullscreenNotice"

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
    let name = model.extensionActions.first { $0.extensionID == extensionID }?.name ?? ""
    let popup = ExtensionPopupWindow(page: view, size: size, name: name, parent: window, anchor: anchorRect) { [weak self] in
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

  func showExtensionPrompt(_ prompt: any ClairExtensionPrompt) {
    extensionPrompts.show(prompt)
  }

  func dismissExtensionPrompt(_ promptID: Int) {
    extensionPrompts.dismiss(promptID)
  }

  func downloadsDidChange(_ downloads: [any ClairDownload], progress: DownloadProgress) {
    model.setDownloads(downloads, progress: progress)
  }

  func downloadProgressDidChange(_ progress: DownloadProgress) {
    model.setDownloadProgress(progress)
  }

  func browserDidClose() {
    // The pages belong to Chromium; let go of them and of the browser.
    model.spaces.removeListener(self)
    model.commandBar?.cancel()
    closeExtensionPopup()
    dialogs.cancelAll()
    rootView.card.show(page: nil)
    rootView.card.showStill(false, image: nil)
    removeSafetyNet()
    stopCommandBarKeyMonitor()
    rootView.card.show(devTools: nil, layout: DevToolsLayout(dockSide: .none, pageBounds: .zero, hidesPage: false))
    browser = nil
  }

  // MARK: SidebarActions

  func activate(tab: TabID) {
    // A tab with a Peek shows with its Peek (add-peek D4).
    browser?.activate(tab: TabListLogic.tabToActivate(forRow: tab, in: model.tabs))
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
    // A regular window lists the Space's whole list, so the index is the
    // engine's (share-tabs-across-windows D1).
    guard model.listsOwnTabsOnly else {
      browser?.move(tab: tab, to: index)
      return
    }
    // An incognito or guest window's index counts its own tabs; the engine
    // counts the Space's, which its other windows' tabs share (add-spaces D2).
    let spaceTabs = model.spaces.tabs(inSpace: model.shownSpaceID)
    guard
      let spaceIndex = TabListLogic.spaceIndex(
        movingTab: tab, toWindowIndex: index, windowTabs: model.tabs, spaceTabs: spaceTabs)
    else { return }
    browser?.move(tab: tab, to: spaceIndex)
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

  func historyMenu(_ direction: HistoryDirection) -> HistoryMenuBuilder? {
    browser.flatMap { HistoryMenuBuilder(browser: $0, direction: direction) }
  }

  func reloadOrStop() {
    switch model.reloadStop.press() {
    case .stop: browser?.stop()
    case .reload: browser?.reload()
    case nil: break
    }
  }

  func reloadButtonHovered(_ hovering: Bool) {
    if hovering {
      model.reloadStop.pointerEntered()
    } else {
      model.reloadStop.pointerExited()
    }
  }

  func editURL() {
    showCommandBar(mode: .currentTab)
  }

  func copyURL() {
    guard let tab = model.activeTab, !tab.isNewTabPage, let link = TabListLogic.link(of: tab) else { return }
    copyToPasteboard(link)
    // Arc's popup, with a share button for the page.
    model.notice.show(
      Notice(text: "Copied Current URL", shareURL: URL(string: link), identifier: "clair.copiedURL"),
      for: NoticeState.copiedDuration)
  }

  private func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  func showSiteControls(indicator: TabIndicators) {
    browser?.showPageInfo(at: indicator.isEmpty ? .siteControls : .indicator, indicator: indicator)
  }

  func runExtension(_ extensionID: String, pinned: Bool) {
    browser?.runExtensionAction(extensionID, anchor: pinned ? .extensionAction : .siteControls)
  }

  func openInNewTab(_ url: URL) {
    browser?.open(url, disposition: .newForegroundTab)
  }

  func contextMenu(forExtension extensionID: String) -> NSMenu? {
    browser?.contextMenu(forExtension: extensionID)
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

  // MARK: SpaceActions (add-spaces D10)

  func showSpace(_ spaceID: SpaceID) {
    guard model.showsSpaces else { return }
    model.newSpaceForm = nil
    browser?.showSpace(spaceID)
  }

  /// Next and Previous Space, wrapping around at the ends.
  func showSpace(step: Int) {
    guard model.showsSpaces,
      let spaceID = SpacesLogic.neighbour(of: model.shownSpaceID, by: step, in: model.spaces.spaces)
    else { return }
    showSpace(spaceID)
  }

  /// Ctrl+1 to Ctrl+9.
  func showSpace(number: Int) {
    guard let spaceID = SpacesLogic.space(number: number, in: model.spaces.spaces) else { return }
    showSpace(spaceID)
  }

  /// The form and the header's edits need the sidebar in its place.
  private func showSidebarForEditing() {
    if model.sidebar.isHidden {
      toggleSidebar()
    }
  }

  func beginNewSpace() {
    guard model.showsSpaces else { return }
    showSidebarForEditing()
    model.spaceHeaderEdit = nil
    // The popup starts on the profile of the Space shown before.
    model.newSpaceForm = NewSpaceFormState(profileID: model.spaces.defaultProfile(after: model.shownSpaceID))
  }

  func cancelNewSpace() {
    model.newSpaceForm = nil
  }

  func createSpace(named name: String, icon: String?, profile: ProfileID?) {
    guard let profile = profile ?? model.spaces.defaultProfile(after: model.shownSpaceID),
      let spaceID = model.spaces.createSpace(named: name, icon: icon, profile: profile)
    else { return }
    model.newSpaceForm = nil
    // A Space with no tab here opens on a new tab page with the command bar.
    browser?.showSpace(spaceID)
  }

  func beginRenamingSpace() {
    guard model.shownSpace != nil else { return }
    showSidebarForEditing()
    model.newSpaceForm = nil
    model.spaceHeaderEdit = .renaming
  }

  func beginChangingSpaceIcon() {
    guard model.shownSpace != nil else { return }
    showSidebarForEditing()
    model.newSpaceForm = nil
    model.spaceHeaderEdit = .icon
  }

  func endEditingSpaceHeader() {
    model.spaceHeaderEdit = nil
  }

  func renameSpace(_ spaceID: SpaceID, to name: String) {
    model.spaces.renameSpace(spaceID, to: name)
  }

  func setIcon(_ icon: String?, forSpace spaceID: SpaceID) {
    model.spaces.setIcon(icon, forSpace: spaceID)
  }

  func deleteSpace(_ spaceID: SpaceID) {
    let spaces = model.spaces
    guard let deletion = spaces.deletion(of: spaceID) else { return }
    guard deletion.needsConfirmation else {
      spaces.deleteSpace(spaceID)
      return
    }
    let dialog = ClairDialog(Self.deletionPage(for: deletion.space, tabCount: deletion.tabCount))
    dialogs.show(dialog) { answer in
      if answer == .accepted {
        spaces.deleteSpace(spaceID)
      }
    }
  }

  /// The confirmation for deleting a Space with tabs (spaces spec, "Deleting
  /// a Space"), worded for Clair: its tabs close.
  static func deletionPage(
    for space: any ClairSpace, tabCount: Int, confirm: (@MainActor (ClairDialog) -> Void)? = nil,
    cancel: (@MainActor (ClairDialog) -> Void)? = nil
  ) -> ClairDialogPage {
    ClairDialogPage(
      title: SpacesLogic.deletionTitle(space.name), message: SpacesLogic.deletionMessage(tabCount: tabCount),
      buttons: [
        ClairDialogButton(title: "Cancel", role: .cancel, action: cancel),
        ClairDialogButton(title: "Delete Space", role: .destructive, action: confirm),
      ])
  }

  func moveSpace(_ spaceID: SpaceID, to index: Int) {
    model.spaces.moveSpace(spaceID, to: index)
  }

  func moveTab(_ tab: TabID, toSpace spaceID: SpaceID) {
    // add-profiles D9: the window follows its active tab; moving any other
    // tab leaves it, and says where the tab went.
    let isActive =
      !model.isShowingStill && TabListLogic.highlightedRow(activeTabID: model.activeTabID, in: model.tabs) == tab
    guard let space = model.spaces.space(spaceID) else { return }
    model.spaces.moveTab(tab, toSpace: spaceID)
    if !isActive {
      model.notice.show(
        Notice(text: SpacesLogic.movedNotice(space.name), identifier: Self.movedNoticeID),
        for: NoticeState.copiedDuration)
    }
  }

  static let movedNoticeID = "clair.tabMoved"

  // MARK: Profiles (add-profiles D9, D10, D12)

  func newProfileForNewSpace() {
    ProfileDialogs.showNewProfile(on: dialogs, spaces: model.spaces) { [weak self] profileID in
      guard let self, let profileID, self.model.newSpaceForm != nil else { return }
      self.model.newSpaceForm?.profileID = profileID
    }
  }

  func setProfile(_ profileID: ProfileID, forSpace spaceID: SpaceID) {
    let spaces = model.spaces
    guard let change = spaces.profileChange(of: spaceID, to: profileID) else { return }
    guard change.needsConfirmation else {
      spaces.setProfile(profileID, forSpace: spaceID)
      return
    }
    dialogs.show(ClairDialog(Self.profileChangePage(for: change))) { answer in
      if answer == .accepted {
        spaces.setProfile(profileID, forSpace: spaceID)
      }
    }
  }

  func newProfile(forSpace spaceID: SpaceID) {
    ProfileDialogs.showNewProfile(on: dialogs, spaces: model.spaces) { [weak self] profileID in
      guard let self, let profileID else { return }
      self.setProfile(profileID, forSpace: spaceID)
    }
  }

  /// The confirmation for a Space with tabs taking another profile, after
  /// Arc's.
  static func profileChangePage(
    for change: SpacesModel.ProfileChange, confirm: (@MainActor (ClairDialog) -> Void)? = nil,
    cancel: (@MainActor (ClairDialog) -> Void)? = nil
  ) -> ClairDialogPage {
    ClairDialogPage(
      title: SpacesLogic.profileChangeTitle(change.profile.name),
      message: SpacesLogic.profileChangeMessage(change.space.name),
      buttons: [
        ClairDialogButton(title: "Cancel", role: .cancel, action: cancel),
        ClairDialogButton(title: SpacesLogic.profileChangeButton, role: .default, action: confirm),
      ])
  }

  func manageSpaces() {
    guard model.showsSpaces, dialogs.showing == nil else { return }
    ManageSpacesDialog.show(for: self)
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
