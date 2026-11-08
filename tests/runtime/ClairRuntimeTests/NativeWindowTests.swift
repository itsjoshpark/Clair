// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import Foundation
import XCTest

/// The native window's fundamentals (replace-browser-window design D14): one
/// test or more for each item of the build-pipeline spec's native window
/// coverage. XCUITest finds ClairUI's views by accessibility identifier, and
/// DevTools reads the pages' state.
@MainActor
class NativeWindowTestCase: RuntimeTestCase {
  func url(_ page: String) -> String { "\(fixture.baseURL)/pages/\(page)" }

  /// Starts Clair with one tab showing `page`, and returns that tab.
  func startWithPage(_ page: String = "index.html", arguments: [String] = []) async throws -> (Browser, DevToolsSession) {
    let browser = try await startBrowser(arguments: arguments)
    let tab = try await browser.open(url(page))
    browser.ui.activate()
    try require(browser.nativeWindow.waitForExistence(timeout: 30), "Clair shows no native window")
    return (browser, tab)
  }
}

extension Browser {
  /// The first window with a sidebar.
  var nativeWindow: XCUIElement {
    ui.windows.containing(.any, identifier: "clair.sidebar").firstMatch
  }

  func element(_ identifier: String, in root: XCUIElement? = nil) -> XCUIElement {
    (root ?? nativeWindow).descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  var sidebar: XCUIElement { element("clair.sidebar") }

  /// Whether the sidebar is in the window, shown or revealed, rather than
  /// moved out of it. XCUITest's isHittable can't see into the sidebar's
  /// SwiftUI content, so this goes by its frame.
  var isSidebarInWindow: Bool {
    guard sidebar.exists else { return false }
    let frame = sidebar.frame
    return frame.width > 0 && frame.minX >= nativeWindow.frame.minX - 1
  }
  var card: XCUIElement { element("clair.card") }

  var tabRows: [XCUIElement] {
    nativeWindow.descendants(matching: .any).matching(identifier: "clair.tabRow").allElementsBoundByIndex
  }

  var tabTitles: [String] { tabRows.map(\.label) }

  /// Waits for the sidebar's tab titles to satisfy `condition`.
  func waitForTabs(_ seconds: TimeInterval = 15, _ condition: @escaping ([String]) -> Bool) async -> Bool {
    await Harness.wait(for: seconds) { condition(self.tabTitles) }
  }

  /// The page's `document.visibilityState`.
  func visibility(of tab: DevToolsSession) async throws -> String {
    try await tab.evaluate("document.visibilityState") as? String ?? ""
  }

  /// The window that shows `tab`, as DevTools sees it.
  func windowBounds(of tab: DevToolsSession, targetID: String? = nil) async throws -> [String: Any] {
    let session = try await browserSession()
    defer { session.close() }
    var parameters: [String: Any] = [:]
    if let targetID { parameters["targetId"] = targetID }
    let window = try await session.send("Browser.getWindowForTarget", parameters)
    return window["bounds"] as? [String: Any] ?? [:]
  }

  /// Lets downloads save to a folder without asking, as ungoogled-chromium
  /// otherwise does for every download. The setting lasts as long as the
  /// returned session, which the caller closes.
  func allowDownloads(to folder: URL) async throws -> DevToolsSession {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let session = try await browserSession()
    try await session.send("Browser.setDownloadBehavior", ["behavior": "allow", "downloadPath": folder.path])
    return session
  }

  /// A point in the card, as a fraction of its size.
  func cardPoint(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
    card.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
  }
}

extension DevToolsSession {
  /// The target this session is attached to, through its URL.
  func targetID(in browser: Browser) async throws -> String? {
    let href = try await evaluate("location.href") as? String
    return try await browser.pageTargets().first { $0.url == href }?.id
  }

  var innerWidth: Double {
    get async throws { try await evaluate("innerWidth") as? Double ?? 0 }
  }
}

/// Which windows are native, and how the window is laid out (task 4.1).
@MainActor
final class NativeWindowStructureTests: NativeWindowTestCase {
  func testNormalWindowsAreNative() async throws {
    let (browser, tab) = try await startWithPage()
    defer { tab.close() }
    XCTAssertTrue(browser.sidebar.exists, "The window has no sidebar")
    XCTAssertTrue(browser.card.exists, "The window has no card")
    XCTAssertFalse(browser.ui.windows.toolbars.firstMatch.exists, "The window shows a toolbar")

    // An incognito window is native, and says so.
    browser.ui.typeKey("n", modifierFlags: [.command, .shift])
    let incognito = await Harness.wait(for: 30) {
      browser.ui.windows.containing(.any, identifier: "clair.sidebar").count >= 2
    }
    XCTAssertTrue(incognito, "The incognito window isn't native")
    XCTAssertTrue(
      browser.ui.staticTexts["Incognito"].waitForExistence(timeout: 10), "The incognito window doesn't say so")
    browser.ui.typeKey("w", modifierFlags: [.command, .shift])

    // A pop-up keeps Chromium's window.
    let windowsBefore = browser.ui.windows.count
    _ = try await tab.evaluate("window.open('index.html?popup', 'popup', 'popup,width=420,height=320'); 1")
    let popup = await Harness.wait(for: 30) { browser.ui.windows.count > windowsBefore }
    try require(popup, "The pop-up didn't open")
    let native = browser.ui.windows.containing(.any, identifier: "clair.sidebar").count
    XCTAssertEqual(native, 1, "The pop-up opened in a native window")
  }

  func testWindowLayout() async throws {
    let (browser, tab) = try await startWithPage()
    defer { tab.close() }
    let window = browser.nativeWindow.frame
    let sidebar = browser.sidebar.frame
    let card = browser.card.frame
    XCTAssertEqual(sidebar.minX, window.minX, accuracy: 1, "The sidebar isn't at the leading edge")
    XCTAssertEqual(card.minX, sidebar.maxX, accuracy: 2, "The card doesn't meet the sidebar")
    XCTAssertEqual(card.minY - window.minY, 10, accuracy: 2, "The card's top inset")
    XCTAssertEqual(window.maxX - card.maxX, 10, accuracy: 2, "The card's trailing inset")
    XCTAssertEqual(window.maxY - card.maxY, 10, accuracy: 2, "The card's bottom inset")
    let close = browser.nativeWindow.buttons[XCUIIdentifierCloseWindow]
    XCTAssertTrue(close.exists, "The window has no close button")
    XCTAssertTrue(sidebar.contains(close.frame), "The window controls aren't in the sidebar")
    XCTAssertTrue(browser.element("clair.urlField").exists, "The sidebar has no URL field")
    XCTAssertTrue(browser.element("clair.back").exists, "The sidebar has no back button")
  }

  /// The window controls sit at Arc's place and the top row lines up with
  /// them, before and after a title change (place-traffic-lights-with-appkit).
  func testWindowControlsStayInPlace() async throws {
    let (browser, tab) = try await startWithPage()
    defer { tab.close() }

    func check(_ when: String) {
      let sidebar = browser.sidebar.frame
      let close = browser.nativeWindow.buttons[XCUIIdentifierCloseWindow]
      // A window that can go full screen has a full-screen button for zoom.
      let fullScreen = browser.nativeWindow.buttons[XCUIIdentifierFullScreenWindow]
      let zoom = fullScreen.exists ? fullScreen : browser.nativeWindow.buttons[XCUIIdentifierZoomWindow]
      let hideSidebar = browser.element("clair.hideSidebar")
      guard close.exists, zoom.exists, hideSidebar.exists else {
        XCTFail("The window controls or the hide-sidebar button are missing \(when)")
        return
      }
      XCTAssertEqual(close.frame.minX - sidebar.minX, 12, accuracy: 1.5, "The close button's x \(when)")
      XCTAssertEqual(close.frame.minY - sidebar.minY, 16, accuracy: 1.5, "The close button's y \(when)")
      XCTAssertEqual(hideSidebar.frame.midY, close.frame.midY, accuracy: 1, "The top row isn't centred on the window controls \(when)")
      XCTAssertGreaterThanOrEqual(hideSidebar.frame.minX, zoom.frame.maxX, "The hide-sidebar button overlaps the zoom button \(when)")
    }

    check("at first")
    _ = try await tab.evaluate("document.title = 'A different title'; 1")
    let retitled = await browser.waitForTabs { $0.contains("A different title") }
    try require(retitled, "The page's new title didn't reach the sidebar")
    // Give AppKit's title bar a moment to lay out for the new window title.
    try await Task.sleep(for: .seconds(1))
    check("after a title change")
  }
}

/// The page in the card, and the window's place across a relaunch (task 4.2).
@MainActor
final class PageHostingTests: NativeWindowTestCase {
  func testPageShownInTheCard() async throws {
    let (browser, first) = try await startWithPage("index.html?first")
    let second = try await browser.open(url("index.html?second"))
    defer {
      first.close()
      second.close()
    }
    // The newest tab is active and at the top.
    let listed = await browser.waitForTabs { $0.count >= 2 }
    try require(listed, "The sidebar doesn't list both tabs: \(browser.tabTitles)")
    let rows = browser.tabRows
    rows[1].click()
    let switched = await Harness.wait(for: 15) {
      try await browser.visibility(of: first) == "visible"
    }
    XCTAssertTrue(switched, "Selecting the tab didn't show its page")
    let hidden = try await browser.visibility(of: second)
    XCTAssertEqual(hidden, "hidden", "The previous page isn't hidden")

    // The page follows the card's size.
    let session = try await browser.browserSession()
    defer { session.close() }
    let targetID = try await first.targetID(in: browser) ?? ""
    let window = try await session.send("Browser.getWindowForTarget", ["targetId": targetID])
    let windowID = window["windowId"] as? Int ?? 0
    try await session.send(
      "Browser.setWindowBounds", ["windowId": windowID, "bounds": ["width": 900, "height": 600]])
    let resized = await Harness.wait(for: 15) {
      let width = try await first.innerWidth
      return abs(width - Double(browser.card.frame.width)) <= 2
    }
    XCTAssertTrue(resized, "The page's viewport doesn't match the card after a resize")
  }

  func testWindowSizeAndPlacementRestored() async throws {
    let browser = try await startBrowser()
    let first = try await browser.open(url("index.html?a"))
    let second = try await browser.open(url("index.html?b"), newWindow: true)
    let session = try await browser.browserSession()
    // Both fit the hosted runner's 1024×768 screen, which would clamp them.
    let sizes = [(first, 720, 520), (second, 900, 600)]
    var expected: [String: (Int, Int)] = [:]
    for (tab, width, height) in sizes {
      let id = try await tab.targetID(in: browser) ?? ""
      let window = try await session.send("Browser.getWindowForTarget", ["targetId": id])
      try await session.send(
        "Browser.setWindowBounds",
        ["windowId": window["windowId"] as? Int ?? 0, "bounds": ["left": 40, "top": 60, "width": width, "height": height]])
      expected[try await tab.evaluate("location.search") as? String ?? ""] = (width, height)
    }
    session.close()
    first.close()
    second.close()
    // Let session restore write the bounds.
    try await Task.sleep(for: .seconds(3))
    try await browser.quit()

    try await browser.start(arguments: ["--restore-last-session"])
    for (search, size) in expected {
      var target: Browser.Target?
      let restored = await Harness.wait(for: 60) {
        target = try await browser.pageTargets().first { $0.url.hasSuffix(search) }
        return target != nil
      }
      try require(restored, "The tab \(search) didn't come back")
      let tab = try await browser.session(onTarget: target!.id)
      defer { tab.close() }
      let bounds = try await browser.windowBounds(of: tab, targetID: target!.id)
      XCTAssertEqual(bounds["width"] as? Int, size.0, "The window of \(search) came back at another width")
      XCTAssertEqual(bounds["height"] as? Int, size.1, "The window of \(search) came back at another height")
    }
    let native = browser.ui.windows.containing(.any, identifier: "clair.sidebar").count
    XCTAssertEqual(native, 2, "The restored windows aren't native")
  }
}

/// DevTools docked in the card (task 4.3).
@MainActor
final class DockedDevToolsTests: NativeWindowTestCase {
  func testDevToolsDocksInTheCardAndUndocks() async throws {
    let (browser, tab) = try await startWithPage()
    defer { tab.close() }
    let full = try await tab.innerWidth
    browser.cardPoint(0.5, 0.5).click()
    browser.ui.typeKey("i", modifierFlags: [.command, .option])
    let docked = await Harness.wait(for: 30) {
      try await tab.innerWidth < full - 200
    }
    XCTAssertTrue(docked, "DevTools didn't narrow the page")
    let windows = browser.ui.windows.count
    XCTAssertEqual(
      browser.ui.windows.containing(.any, identifier: "clair.sidebar").count, windows,
      "DevTools opened in a window of its own")

    // Undocked, it moves to its own window and the page fills the card again.
    browser.ui.typeKey("d", modifierFlags: [.command, .shift])
    let undocked = await Harness.wait(for: 30) {
      abs(try await tab.innerWidth - full) <= 2
    }
    XCTAssertTrue(undocked, "Undocking didn't give the page its width back")
  }
}

/// Page full screen (task 4.4).
@MainActor
final class FullscreenTests: NativeWindowTestCase {
  func testPageFullscreenFillsTheScreenAndEndsWithEscape() async throws {
    let (browser, tab) = try await startWithPage("fullscreen.html")
    defer { tab.close() }
    let entered = try await tab.evaluate("enter()") as? String
    try require(entered == "entered", "The page couldn't enter full screen")
    let screen = NSScreen.main?.frame.size ?? .zero
    let filled = await Harness.wait(for: 30) {
      let width = try await tab.evaluate("innerWidth") as? Double ?? 0
      return abs(width - Double(screen.width)) <= 2
    }
    XCTAssertTrue(filled, "The page doesn't fill the screen")
    XCTAssertFalse(browser.isSidebarInWindow, "The sidebar shows in page full screen")
    // The notice appears once the window has finished moving into full screen.
    // The window hides its sidebar now, so look for it in the whole app.
    let notice = browser.ui.descendants(matching: .any).matching(identifier: "clair.fullscreenNotice").firstMatch
    XCTAssertTrue(notice.waitForExistence(timeout: 15), "No notice says how to leave full screen")
    browser.ui.typeKey(.escape, modifierFlags: [])
    let ended = await Harness.wait(for: 30) {
      try await tab.evaluate("document.fullscreenElement === null") as? Bool == true
    }
    XCTAssertTrue(ended, "Esc didn't end page full screen")
    let back = await Harness.wait(for: 30) { browser.isSidebarInWindow }
    XCTAssertTrue(back, "The sidebar didn't come back")
  }
}

/// Toasts (task 4.6).
@MainActor
final class ToastTests: NativeWindowTestCase {
  func testCopyImageShowsAToast() async throws {
    let (browser, tab) = try await startWithPage("image.html")
    defer { tab.close() }
    let loaded = await Harness.wait(for: 15) {
      try await tab.evaluate("document.getElementById('image').complete") as? Bool == true
    }
    try require(loaded, "The image didn't load")
    // The image is 400×300 at the page's top left.
    let card = browser.card.frame
    let point = browser.card.coordinate(
      withNormalizedOffset: CGVector(dx: 100 / card.width, dy: 100 / card.height))
    point.rightClick()
    let copy = browser.ui.menuItems["Copy Image"]
    try require(copy.waitForExistence(timeout: 10), "The context menu has no Copy Image item")
    copy.click()
    let toast = browser.element("clair.toast")
    XCTAssertTrue(toast.waitForExistence(timeout: 10), "Copy Image showed no toast")
  }
}

/// The top row and the URL field (task 5.1).
@MainActor
final class NavigationTests: NativeWindowTestCase {
  func testBackAndForward() async throws {
    let (browser, tab) = try await startWithPage("link.html")
    defer { tab.close() }
    try await tab.navigate(to: url("index.html?next"))
    let back = browser.element("clair.back")
    let enabled = await Harness.wait(for: 15) { back.isEnabled }
    try require(enabled, "Back isn't available after a navigation")
    back.click()
    let wentBack = await Harness.wait(for: 15) {
      (try await tab.evaluate("location.pathname") as? String)?.hasSuffix("link.html") == true
    }
    XCTAssertTrue(wentBack, "Back didn't return to the previous page")
    let forward = browser.element("clair.forward")
    let forwardEnabled = await Harness.wait(for: 15) { forward.isEnabled }
    XCTAssertTrue(forwardEnabled, "Forward isn't available after going back")
    forward.click()
    let wentForward = await Harness.wait(for: 15) {
      try await tab.evaluate("location.search") as? String == "?next"
    }
    XCTAssertTrue(wentForward, "Forward didn't go to the next page")
  }
}

/// Reload and stop follow the page's own loading (arc-navigation-feedback
/// task 3.2): frames loading on their own and same-document navigations
/// leave reload in place.
@MainActor
final class ReloadStopTests: NativeWindowTestCase {
  static let reload = "Reload this page"
  static let stop = "Stop loading this page"

  private func waitUntilLoaded(_ tab: DevToolsSession) async -> Bool {
    await Harness.wait(for: 30) { try await tab.evaluate("document.readyState") as? String == "complete" }
  }

  /// Watches the reload button for `seconds` and returns every label it showed.
  private func labels(of button: XCUIElement, for seconds: TimeInterval) -> Set<String> {
    var seen = Set<String>()
    let end = Date(timeIntervalSinceNow: seconds)
    while Date() < end {
      seen.insert(button.label)
      Thread.sleep(forTimeInterval: 0.1)
    }
    return seen
  }

  private func checkReloadStays(on page: String) async throws {
    let (browser, tab) = try await startWithPage(page)
    defer { tab.close() }
    try require(await waitUntilLoaded(tab), "\(page) didn't finish loading")
    let reload = browser.element("clair.reload")
    try require(reload.waitForExistence(timeout: 10), "The sidebar has no reload button")
    let seen = labels(of: reload, for: 5)
    XCTAssertEqual(seen, [Self.reload], "On \(page), the reload button showed \(seen.sorted())")
  }

  func testBusyFramesKeepReload() async throws {
    try await checkReloadStays(on: "busy-frames.html")
  }

  func testPushStateKeepsReload() async throws {
    try await checkReloadStays(on: "push-state.html")
  }

  func testSlowPageShowsStopUntilLoaded() async throws {
    let (browser, tab) = try await startWithPage()
    defer { tab.close() }
    let reload = browser.element("clair.reload")
    try require(reload.waitForExistence(timeout: 10), "The sidebar has no reload button")
    _ = try await tab.evaluate("location.href = '\(fixture.baseURL)/slow-page?seconds=6'; 1")
    let stopped = await Harness.wait(for: 5) { reload.label == Self.stop }
    XCTAssertTrue(stopped, "The reload button didn't show stop while the slow page loaded")
    let stillStop = labels(of: reload, for: 2)
    XCTAssertEqual(stillStop, [Self.stop], "Stop didn't hold while the slow page loaded: \(stillStop.sorted())")
    let reloaded = await Harness.wait(for: 20) { reload.label == Self.reload }
    XCTAssertTrue(reloaded, "The reload button didn't show reload once the slow page loaded")
  }
}

/// The back button's history menu (arc-navigation-feedback task 4.2).
@MainActor
final class HistoryMenuTests: NativeWindowTestCase {
  func testChoosingAnEntryInTheBackMenu() async throws {
    let (browser, tab) = try await startWithPage("link.html")
    defer { tab.close() }
    try await tab.navigate(to: url("index.html?second"))
    try await tab.navigate(to: url("find.html"))
    let back = browser.element("clair.back")
    let enabled = await Harness.wait(for: 15) { back.isEnabled }
    try require(enabled, "Back isn't available after two navigations")
    back.rightClick()
    let first = browser.ui.menuItems["Clair link page"]
    try require(first.waitForExistence(timeout: 10), "The back menu doesn't list the first page")
    let second = browser.ui.menuItems["Clair runtime test page"]
    XCTAssertTrue(second.exists, "The back menu doesn't list the second page")
    if second.exists {
      XCTAssertLessThan(second.frame.minY, first.frame.minY, "The back menu isn't nearest first")
    }
    first.click()
    let wentBack = await Harness.wait(for: 15) {
      (try await tab.evaluate("location.pathname") as? String)?.hasSuffix("link.html") == true
    }
    XCTAssertTrue(wentBack, "Choosing the first page didn't go there")
    let forward = browser.element("clair.forward")
    let forwardEnabled = await Harness.wait(for: 15) { forward.isEnabled }
    XCTAssertTrue(forwardEnabled, "Forward isn't available after going back through the menu")
  }
}

/// Permission prompts attached to the sidebar or the card's corner (task 5.2).
@MainActor
final class PermissionPromptTests: NativeWindowTestCase {
  private func ask(_ browser: Browser, _ tab: DevToolsSession, choose button: String, expect result: String) async throws {
    _ = try await tab.evaluate("ask(); 1")
    let choice = browser.ui.buttons[button]
    try require(choice.waitForExistence(timeout: 20), "No permission prompt with \(button)")
    if let screen = NSScreen.main?.frame {
      XCTAssertTrue(
        screen.contains(choice.frame), "The prompt's \(button) button is off screen at \(choice.frame)")
    }
    choice.click()
    let answered = await Harness.wait(for: 15) {
      try await tab.evaluate("window.permissionResult") as? String == result
    }
    XCTAssertTrue(answered, "Choosing \(button) didn't give \(result)")
  }

  func testPromptWithTheSidebarShownAllows() async throws {
    let (browser, tab) = try await startWithPage("notify.html")
    defer { tab.close() }
    try await ask(browser, tab, choose: "Allow", expect: "granted")
  }

  func testPromptWithTheSidebarHiddenBlocks() async throws {
    let (browser, tab) = try await startWithPage("notify.html")
    defer { tab.close() }
    browser.ui.typeKey("s", modifierFlags: .command)
    let hidden = await Harness.wait(for: 10) { !browser.isSidebarInWindow }
    try require(hidden, "Cmd+S didn't hide the sidebar")
    try await ask(browser, tab, choose: "Block", expect: "denied")
  }
}

/// An extension action's popup from its pinned button (task 5.3).
@MainActor
final class ExtensionActionTests: NativeWindowTestCase {
  func testPinnedActionOpensItsPopup() async throws {
    let extensionPath = Fixture.directory.appending(path: "extensions/popup-badge").path
    let (browser, tab) = try await startWithPage(arguments: ["--load-extension=\(extensionPath)"])
    defer { tab.close() }
    let extensions = browser.element("clair.extensions")
    try require(extensions.waitForExistence(timeout: 30), "The sidebar has no extensions button")
    extensions.click()
    let pin = browser.ui.buttons["Pin"].firstMatch
    try require(pin.waitForExistence(timeout: 10), "The extensions list can't pin the action")
    pin.click()
    browser.ui.typeKey(.escape, modifierFlags: [])
    let pinned = browser.element("clair.extensionAction")
    try require(pinned.waitForExistence(timeout: 10), "The pinned action has no button")
    let badge = await Harness.wait(for: 15) { (pinned.value as? String) == "3" }
    XCTAssertTrue(badge, "The pinned action doesn't show its badge")
    pinned.click()
    let popup = browser.ui.windows["clair.extensionPopup"]
    XCTAssertTrue(popup.waitForExistence(timeout: 15), "The action's popup didn't open")
    let session = try await browser.browserSession()
    defer { session.close() }
    let targets = try await session.send("Target.getTargets")
    let infos = targets["targetInfos"] as? [[String: Any]] ?? []
    XCTAssertTrue(
      infos.contains { ($0["url"] as? String)?.hasSuffix("/popup.html") == true },
      "No popup page is loaded")
  }
}

/// The downloads button and list (task 5.4).
@MainActor
final class DownloadsTests: NativeWindowTestCase {
  func testDownloadsButtonShowsProgressAndUnseenDownloads() async throws {
    let (browser, tab) = try await startWithPage()
    defer { tab.close() }
    let folder = browser.workDirectory.appending(path: "downloads")
    let downloads = try await browser.allowDownloads(to: folder)
    defer { downloads.close() }

    _ = try await tab.evaluate("location.href = '/slow-download'; 1")
    let button = browser.element("clair.downloads")
    try require(button.waitForExistence(timeout: 30), "No downloads button appeared")
    let progress = await Harness.wait(for: 30) { (button.value as? String)?.hasSuffix("%") == true }
    XCTAssertTrue(progress, "The downloads button shows no progress")
    _ = try await URLSession.shared.data(from: URL(string: "\(fixture.baseURL)/slow-download/finish")!)

    // The button's mark for an unseen download is part of the button, which
    // says "New" as its value.
    let unseen = await Harness.wait(for: 30) { (button.value as? String) == "New" }
    XCTAssertTrue(unseen, "The finished download isn't marked")
    button.click()
    let row = browser.ui.descendants(matching: .any).matching(identifier: "clair.downloadRow").firstMatch
    try require(row.waitForExistence(timeout: 10), "The downloads list is empty")
    row.click()
    let seen = await Harness.wait(for: 15) { (button.value as? String) != "New" }
    XCTAssertTrue(seen, "Opening the download didn't clear its mark")
    _ = try? Harness.run("/usr/bin/pkill", ["-x", "TextEdit"])
  }
}

/// The tab list and where new tabs go (task 5.5).
@MainActor
final class TabListTests: NativeWindowTestCase {
  func testSelectingClosingNewTabsAndReordering() async throws {
    let browser = try await startBrowser()
    var tabs: [DevToolsSession] = []
    for index in 1...5 {
      tabs.append(try await browser.open(url("index.html?\(index)")))
    }
    defer { tabs.forEach { $0.close() } }
    browser.ui.activate()
    let five = await browser.waitForTabs { $0.filter { $0 == "Clair runtime test page" }.count >= 5 }
    try require(five, "The sidebar doesn't list five tabs: \(browser.tabTitles)")
    let count = browser.tabRows.count

    // Selecting: the newest tab is at the top, so the third row is tab 3.
    browser.tabRows[2].click()
    let selected = await Harness.wait(for: 15) { try await browser.visibility(of: tabs[2]) == "visible" }
    XCTAssertTrue(selected, "Clicking a row didn't select its tab")

    // A link Cmd-clicked in that tab opens at the top, in the background.
    try await tabs[2].navigate(to: url("link.html"))
    // A real click: Chromium opens a scripted click's background tab in the
    // foreground, so a page can't open tabs behind the user.
    let center =
      try await tabs[2].evaluate(
        "(() => { const r = document.getElementById('link').getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2]; })()"
      ) as? [Double] ?? [0, 0]
    for type in ["mousePressed", "mouseReleased"] {
      // Modifier 4 is Meta, the Command key.
      try await tabs[2].send(
        "Input.dispatchMouseEvent",
        ["type": type, "x": center[0], "y": center[1], "button": "left", "clickCount": 1, "modifiers": 4])
    }
    let opened = await browser.waitForTabs { $0.count == count + 1 }
    try require(opened, "The Cmd-clicked link opened no tab")
    let linked = try await browser.pageTargets().first { $0.url.hasSuffix("?linked") }
    let rowsNow = browser.tabRows
    XCTAssertEqual(rowsNow.first?.label, "Clair runtime test page", "The new tab isn't first")
    XCTAssertNotNil(linked, "No tab shows the linked page")
    let stillActive = try await browser.visibility(of: tabs[2])
    XCTAssertEqual(stillActive, "visible", "The link's tab didn't stay active")

    // Closing with the row's button.
    let row = browser.tabRows[1]
    row.hover()
    let close = browser.element("clair.tabClose", in: row)
    try require(close.waitForExistence(timeout: 10), "Hovering a row shows no close button")
    close.click()
    let closed = await browser.waitForTabs { $0.count == count }
    XCTAssertTrue(closed, "The close button didn't close the tab")

    // Dragging the third row above the first makes it tab 1.
    let rows = browser.tabRows
    let moving = rows[2]
    moving.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      .press(forDuration: 0.4, thenDragTo: rows[0].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
    try await Task.sleep(for: .seconds(1))
    browser.ui.typeKey("1", modifierFlags: .command)
    let first = browser.tabRows.first
    let isFirstSelected = await Harness.wait(for: 15) { first?.isSelected == true }
    XCTAssertTrue(isFirstSelected, "Cmd+1 didn't select the tab dragged to the top")
  }
}

/// The tab row's layout (design D12, D18). Accessibility reports what's drawn,
/// not the layout's frames: on this page, which has no favicon, the favicon is
/// the 13 pt globe glyph centred in its 18 pt frame 9 pt into the pill, so it
/// reads 12 pt in, with the title 10 pt after it. While the tab plays sound,
/// the speaker sits between them with the same visible gap on each side as
/// the title has from the favicon without it, which reads 7 pt before the
/// speaker's reported frame and 5.5 pt after it. These are the values of the layout checked
/// against Arc; a change that moves any of them fails here.
@MainActor
final class TabRowLayoutTests: NativeWindowTestCase {
  func testFaviconSpeakerAndTitlePositions() async throws {
    let (browser, tab) = try await startWithPage("audio.html")
    defer { tab.close() }
    let found = await browser.waitForTabs { $0.contains("Clair runtime audio page") }
    try require(found, "The sidebar doesn't list the audio page: \(browser.tabTitles)")
    guard let row = browser.tabRows.first(where: { $0.label == "Clair runtime audio page" }) else {
      return XCTFail("No row for the audio page")
    }
    let favicon = browser.element("clair.tabFavicon", in: row)
    let title = browser.element("clair.tabTitle", in: row)
    try require(favicon.waitForExistence(timeout: 10) && title.exists, "The row shows no favicon or title")

    // Without sound.
    XCTAssertEqual(favicon.frame.minX - row.frame.minX, 12, accuracy: 1, "The favicon's inset in the pill")
    XCTAssertEqual(favicon.frame.width, 13, accuracy: 1, "The favicon's width")
    XCTAssertEqual(title.frame.minX - favicon.frame.maxX, 10, accuracy: 1, "The gap between favicon and title")

    // With sound: the speaker sits between them with even gaps.
    let state = try await tab.evaluate("startTone()") as? String
    try require(state == "running", "The test tone didn't start")
    let speaker = browser.element("clair.tabSpeaker", in: row)
    let shown = await Harness.wait(for: 15) { speaker.exists && speaker.frame.width > 10 }
    try require(shown, "The playing tab shows no speaker")
    try await Task.sleep(for: .milliseconds(500))
    XCTAssertEqual(speaker.frame.minX - favicon.frame.maxX, 7, accuracy: 1, "The gap between favicon and speaker")
    XCTAssertEqual(title.frame.minX - speaker.frame.maxX, 5.5, accuracy: 1, "The gap between speaker and title")
    XCTAssertEqual(favicon.frame.minX - row.frame.minX, 12, accuracy: 1, "The favicon moved when the speaker showed")
    _ = try await tab.evaluate("stopTone()")
  }
}

/// Hiding, revealing and Save Page As (task 5.6).
@MainActor
final class SidebarHidingTests: NativeWindowTestCase {
  func testCmdSHidesAndShowsTheSidebar() async throws {
    let (browser, tab) = try await startWithPage()
    defer { tab.close() }
    let window = browser.nativeWindow.frame
    browser.ui.typeKey("s", modifierFlags: .command)
    let hidden = await Harness.wait(for: 10) {
      abs(browser.card.frame.minX - window.minX - 10) <= 2
    }
    XCTAssertTrue(hidden, "Cmd+S didn't hide the sidebar and widen the card")
    browser.ui.typeKey("s", modifierFlags: .command)
    let shown = await Harness.wait(for: 10) {
      abs(browser.card.frame.minX - browser.sidebar.frame.maxX) <= 2 && browser.isSidebarInWindow
    }
    XCTAssertTrue(shown, "Cmd+S didn't bring the sidebar back")
  }

  func testCmdSDoesNotSaveButShiftCmdSDoes() async throws {
    let (browser, tab) = try await startWithPage()
    defer { tab.close() }
    browser.cardPoint(0.5, 0.5).click()
    browser.ui.typeKey("s", modifierFlags: .command)
    try await Task.sleep(for: .seconds(2))
    XCTAssertFalse(browser.ui.sheets.firstMatch.exists, "Cmd+S opened a save panel")
    browser.ui.typeKey("s", modifierFlags: .command)
    browser.cardPoint(0.5, 0.5).click()
    browser.ui.typeKey("s", modifierFlags: [.command, .shift])
    let saving =
      browser.ui.sheets.firstMatch.waitForExistence(timeout: 10)
      || browser.ui.dialogs.firstMatch.waitForExistence(timeout: 5)
    XCTAssertTrue(saving, "Shift+Cmd+S opened no save panel")
    browser.ui.typeKey(.escape, modifierFlags: [])
  }

  func testHoverRevealKeepsThePageSize() async throws {
    let (browser, tab) = try await startWithPage()
    defer { tab.close() }
    browser.ui.typeKey("s", modifierFlags: .command)
    let hidden = await Harness.wait(for: 10) { !browser.isSidebarInWindow }
    try require(hidden, "Cmd+S didn't hide the sidebar")
    try await Task.sleep(for: .seconds(1))
    let width = try await tab.innerWidth
    browser.nativeWindow.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
      .withOffset(CGVector(dx: 2, dy: 0)).hover()
    let revealed = await Harness.wait(for: 10) { browser.isSidebarInWindow }
    XCTAssertTrue(revealed, "Resting at the leading edge didn't reveal the sidebar")
    let after = try await tab.innerWidth
    XCTAssertEqual(after, width, accuracy: 1, "Revealing the sidebar resized the page")
  }
}

/// The command bar (task 6.2).
@MainActor
final class CommandBarTests: NativeWindowTestCase {
  private func openCommandBar(_ browser: Browser, _ key: String) throws -> XCUIElement {
    browser.ui.typeKey(key, modifierFlags: .command)
    let field = browser.element("clair.commandBarField")
    try require(field.waitForExistence(timeout: 10), "Cmd+\(key.uppercased()) didn't open the command bar")
    return field
  }

  func testCmdTOpensATypedURLAtTheTop() async throws {
    let (browser, tab) = try await startWithPage()
    defer { tab.close() }
    let count = browser.tabRows.count
    let field = try openCommandBar(browser, "t")
    field.typeText(url("index.html?typed") + "\n")
    let opened = await Harness.wait(for: 15) {
      try await browser.pageTargets().contains { $0.url.hasSuffix("?typed") }
    }
    XCTAssertTrue(opened, "The typed URL didn't open")
    let listed = await browser.waitForTabs { $0.count == count + 1 }
    XCTAssertTrue(listed, "The new tab isn't in the sidebar")
    XCTAssertTrue(browser.tabRows.first?.isSelected == true, "The new tab isn't first and active")
  }

  func testEscapeCreatesNoTab() async throws {
    let (browser, tab) = try await startWithPage()
    defer { tab.close() }
    let before = try await browser.pageTargets().count
    _ = try openCommandBar(browser, "t")
    browser.ui.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(
      browser.element("clair.commandBar").waitForNonExistence(timeout: 10), "Esc didn't close the command bar")
    let after = try await browser.pageTargets().count
    XCTAssertEqual(after, before, "Esc created a tab")
  }

  func testCmdLNavigatesTheCurrentTab() async throws {
    let (browser, tab) = try await startWithPage()
    defer { tab.close() }
    let before = try await browser.pageTargets().count
    let field = try openCommandBar(browser, "l")
    field.typeKey("a", modifierFlags: .command)
    field.typeText(url("index.html?edited") + "\n")
    let navigated = await Harness.wait(for: 15) {
      try await tab.evaluate("location.search") as? String == "?edited"
    }
    XCTAssertTrue(navigated, "Cmd+L didn't navigate the current tab")
    let after = try await browser.pageTargets().count
    XCTAssertEqual(after, before, "Cmd+L created a tab")
  }

  func testSwitchesToAnOpenTab() async throws {
    let (browser, first) = try await startWithPage("index.html?open")
    let second = try await browser.open(url("link.html"))
    defer {
      first.close()
      second.close()
    }
    let before = try await browser.pageTargets().count
    let field = try openCommandBar(browser, "t")
    field.typeText(url("index.html?open"))
    let row = browser.ui.descendants(matching: .any).matching(
      NSPredicate(format: "identifier == 'clair.suggestion' AND label CONTAINS 'Switch to Tab'")
    ).firstMatch
    try require(row.waitForExistence(timeout: 15), "No Switch to Tab suggestion")
    row.click()
    let switched = await Harness.wait(for: 15) { try await browser.visibility(of: first) == "visible" }
    XCTAssertTrue(switched, "Choosing Switch to Tab didn't activate the open tab")
    let after = try await browser.pageTargets().count
    XCTAssertEqual(after, before, "Switch to Tab created a tab")
  }
}
