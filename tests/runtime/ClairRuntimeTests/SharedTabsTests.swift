// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import Foundation
import XCTest

/// One of Clair's native windows, found by its frame, which these tests never
/// change: the order XCUITest lists windows in follows which is in front.
@MainActor
struct NativeWindow {
  let browser: Browser
  let frame: CGRect

  var element: XCUIElement {
    let windows = browser.ui.windows.containing(.any, identifier: "clair.sidebar").allElementsBoundByIndex
    return windows.first { $0.frame == frame }
      ?? browser.ui.windows.matching(identifier: "clair.noSuchWindow").firstMatch
  }

  func element(_ identifier: String) -> XCUIElement { browser.element(identifier, in: element) }

  var tabRows: [XCUIElement] {
    element.descendants(matching: .any).matching(identifier: "clair.tabRow").allElementsBoundByIndex
  }

  func tabRow(_ title: String) -> XCUIElement? { tabRows.first { $0.label == title } }

  /// The rows' titles, from one snapshot of the window.
  var tabTitles: [String] {
    guard let window = try? element.snapshot() else { return [] }
    var titles: [String] = []
    func collect(_ element: any XCUIElementSnapshot) {
      if element.identifier == "clair.tabRow" {
        titles.append(element.label)
      }
      element.children.forEach(collect)
    }
    collect(window)
    return titles
  }

  var activeRow: String? { tabRows.first(where: \.isSelected)?.label }
  var spaceName: String {
    let name = element("clair.spaceName")
    return name.exists ? name.value as? String ?? "" : ""
  }
  /// The faded still of a tab another window took (share-tabs-across-windows
  /// D2).
  var still: XCUIElement { element("clair.still") }

  /// Whether the window shows a still: one of the app's stills lies in the
  /// window's frame. Found app-wide, since a window found by index can turn
  /// into another once the other comes to the front.
  var showsStill: Bool {
    browser.ui.descendants(matching: .any).matching(identifier: "clair.still").allElementsBoundByIndex.contains {
      frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY))
    }
  }
  var urlField: XCUIElement { element("clair.urlField") }
  var peekBadge: XCUIElement { element("clair.peekBadge") }

  func waitForTabs(_ seconds: TimeInterval = 15, _ condition: @escaping ([String]) -> Bool) async -> Bool {
    await Harness.wait(for: seconds) { condition(self.tabTitles) }
  }

  func waitForActiveRow(_ title: String, seconds: TimeInterval = 15) async -> Bool {
    await Harness.wait(for: seconds) { self.activeRow == title }
  }

  func waitForStill(_ shown: Bool = true, seconds: TimeInterval = 15) async -> Bool {
    await Harness.wait(for: seconds) { self.showsStill == shown }
  }

  /// Makes the window key with a click on its sidebar's empty space below
  /// the rows, which selects nothing. A window showing a still takes its tab
  /// back.
  func click() {
    element("clair.sidebar").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).click()
  }
}

extension Browser {
  /// Every native window, in no particular order.
  var nativeWindows: [NativeWindow] {
    ui.windows.containing(.any, identifier: "clair.sidebar").allElementsBoundByIndex.map {
      NativeWindow(browser: self, frame: $0.frame)
    }
  }

  /// Waits for `count` native windows and returns them.
  func waitForNativeWindows(_ count: Int, seconds: TimeInterval = 30) async throws -> [NativeWindow] {
    let opened = await Harness.wait(for: seconds) { self.nativeWindows.count == count }
    try require(opened, "Clair doesn't show \(count) windows: \(nativeWindows.count)")
    return nativeWindows
  }
}

/// Tabs shared across windows (share-tabs-across-windows task 3.4), with the
/// counter page, whose state shows that a tab kept its page.
@MainActor
final class SharedTabsTests: NativeWindowTestCase {
  func counter(_ name: String) -> String { url("counter.html?\(name)") }

  /// Puts the windows of `tabs` side by side, left to right, so a click
  /// meant for one never lands on another.
  func tile(_ tabs: [DevToolsSession], in browser: Browser) async throws {
    let session = try await browser.browserSession()
    defer { session.close() }
    let screen = NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900)
    let width = Int(screen.width) / tabs.count
    let height = Int(min(900, screen.height - 80))
    for (index, tab) in tabs.enumerated() {
      guard let targetID = try await tab.targetID(in: browser) else {
        throw HarnessError("A tab to tile has no target")
      }
      let window = try await session.send("Browser.getWindowForTarget", ["targetId": targetID])
      guard let windowID = window["windowId"] as? Int else {
        throw HarnessError("A tab to tile has no window")
      }
      try await session.send(
        "Browser.setWindowBounds",
        ["windowId": windowID, "bounds": ["left": index * width, "top": 40, "width": width, "height": height]])
    }
  }

  /// Starts Clair with Counter a in window A, then opens Counter b in a new
  /// window B, which is key, and puts A on the left and B on the right.
  func startWithTwoWindows() async throws -> (Browser, NativeWindow, NativeWindow, DevToolsSession, DevToolsSession) {
    let (browser, a) = try await startWithPage("counter.html?a")
    try require(browser.nativeWindows.count == 1, "Clair didn't start with one window")
    let b = try await browser.open(counter("b"), newWindow: true)
    _ = try await browser.waitForNativeWindows(2)
    try await tile([a, b], in: browser)
    try await Task.sleep(for: .seconds(1))
    let windows = try await browser.waitForNativeWindows(2).sorted { $0.frame.minX < $1.frame.minX }
    let windowA = windows[0], windowB = windows[1]
    let shown = await windowB.waitForActiveRow("Counter b")
    try require(shown, "Window B doesn't show Counter b: \(windowB.activeRow ?? "none")")
    return (browser, windowA, windowB, a, b)
  }

  func count(_ tab: DevToolsSession) async throws -> Double? {
    try await tab.evaluate("window.counter") as? Double
  }

  func testBothWindowsListTheSameTabs() async throws {
    let (browser, windowA, windowB, a, b) = try await startWithTwoWindows()
    defer {
      a.close()
      b.close()
    }
    var same = await Harness.wait(for: 15) {
      windowA.tabTitles == windowB.tabTitles && windowA.tabTitles.starts(with: ["Counter b", "Counter a"])
    }
    XCTAssertTrue(same, "The windows don't list the same tabs: \(windowA.tabTitles) and \(windowB.tabTitles)")

    // A tab opened in B, the key window, shows in A at the top.
    let c = try await browser.open(counter("c"))
    defer { c.close() }
    let opened = await windowA.waitForTabs { $0.first == "Counter c" }
    XCTAssertTrue(opened, "A tab opened in B isn't listed in A: \(windowA.tabTitles)")
    // Moved in B, moved in A.
    browser.ui.typeKey(.pageDown, modifierFlags: [.control, .shift])
    let moved = await windowA.waitForTabs { $0.starts(with: ["Counter b", "Counter c"]) }
    XCTAssertTrue(moved, "A row moved in B didn't move in A: \(windowA.tabTitles)")
    // Closed in B, gone from A.
    browser.ui.typeKey("w", modifierFlags: .command)
    let closed = await windowA.waitForTabs { !$0.contains("Counter c") }
    XCTAssertTrue(closed, "A tab closed in B is still listed in A: \(windowA.tabTitles)")

    // Cmd+N lists the Space's tabs, below its new tab page.
    let listedBefore = windowA.tabTitles
    browser.ui.typeKey("n", modifierFlags: .command)
    _ = try await browser.waitForNativeWindows(3)
    browser.ui.typeKey(.escape, modifierFlags: [])
    // The new window may open over another, at the same frame: it's the one
    // in front.
    let front = NativeWindow(browser: browser, frame: browser.nativeWindow.frame)
    same = await front.waitForTabs { $0 == ["New Tab"] + listedBefore }
    XCTAssertTrue(same, "The new window doesn't list the Space's tabs: \(front.tabTitles)")
    browser.ui.typeKey("w", modifierFlags: [.command, .shift])
  }

  func testTakingATabKeepsItsPageAndLeavesAStill() async throws {
    let (_, windowA, windowB, a, b) = try await startWithTwoWindows()
    defer {
      a.close()
      b.close()
    }
    windowA.click()
    _ = await windowA.waitForActiveRow("Counter a")
    _ = try await a.evaluate("window.counter = 7; 1")

    // B selects A's tab: B shows the live page, A a still of it.
    windowB.click()
    windowB.tabRow("Counter a")?.click()
    let taken = await windowB.waitForActiveRow("Counter a")
    try require(taken, "B didn't show Counter a: \(windowB.activeRow ?? "none")")
    let count = try await count(a)
    XCTAssertEqual(count, 7, "Taking the tab reloaded its page")
    let still = await windowA.waitForStill()
    try require(still, "A shows no still of the tab B took")
    XCTAssertEqual(windowA.activeRow, "Counter a", "A doesn't keep the tab's row highlighted")
    XCTAssertEqual(windowA.urlField.label, "Search or Enter URL…", "A's URL field isn't empty")
    XCTAssertFalse(windowA.element("clair.back").isEnabled, "A's back button is on")
    XCTAssertFalse(windowA.element("clair.reload").isEnabled, "A's reload button is on")
    XCTAssertFalse(windowA.element("clair.forward").isEnabled, "A's forward button is on")

    // A click in A takes it back; B keeps the still now.
    windowA.click()
    let back = await windowA.waitForStill(false)
    XCTAssertTrue(back, "Clicking in A didn't take the tab back")
    let stillInB = await windowB.waitForStill()
    XCTAssertTrue(stillInB, "B shows no still once A took the tab back")
    let countBack = try await self.count(a)
    XCTAssertEqual(countBack, 7, "Taking the tab back reloaded its page")

    // A moves on to another row: B shows the tab live again, unclicked.
    windowA.tabRow("Counter b")?.click()
    _ = await windowA.waitForActiveRow("Counter b")
    let given = await windowB.waitForStill(false)
    XCTAssertTrue(given, "Moving on in A didn't give the tab back to B")
    XCTAssertEqual(windowB.activeRow, "Counter a", "B doesn't show the tab it got back")
  }

  func testSelectingATabNoWindowShows() async throws {
    let (browser, windowA, windowB, a, b) = try await startWithTwoWindows()
    defer {
      a.close()
      b.close()
    }
    // A opens x, then shows a again: x shows nowhere.
    windowA.click()
    let x = try await browser.open(counter("x"))
    defer { x.close() }
    _ = await windowA.waitForActiveRow("Counter x")
    windowA.tabRow("Counter a")?.click()
    _ = await windowA.waitForActiveRow("Counter a")
    windowB.click()
    windowB.tabRow("Counter x")?.click()
    let shown = await windowB.waitForActiveRow("Counter x")
    XCTAssertTrue(shown, "B didn't show Counter x")
    try await Task.sleep(for: .seconds(1))
    XCTAssertFalse(windowA.showsStill, "A shows a still of a tab it didn't show")
    XCTAssertEqual(windowA.activeRow, "Counter a", "A changed")
  }

  func testTheStillEndsWhenItsTabClosesOrTheUserMovesOn() async throws {
    let (browser, windowA, windowB, a, b) = try await startWithTwoWindows()
    defer {
      a.close()
      b.close()
    }
    // B takes a. A first click on another row in A, which isn't key, only
    // takes a back, as in Arc; the second selects the row, and B gets a back.
    windowB.tabRow("Counter a")?.click()
    _ = await windowB.waitForActiveRow("Counter a")
    var still = await windowA.waitForStill()
    try require(still, "A shows no still")
    windowA.tabRow("Counter b")?.click()
    let back = await windowA.waitForStill(false)
    XCTAssertTrue(back, "A click in A didn't take the tab back")
    let stillInB = await windowB.waitForStill()
    XCTAssertTrue(stillInB, "B shows no still once A took the tab back")
    windowA.tabRow("Counter b")?.click()
    _ = await windowA.waitForActiveRow("Counter b")
    let given = await windowB.waitForStill(false)
    XCTAssertTrue(given, "Moving on in A didn't give the tab back to B")
    XCTAssertEqual(windowB.activeRow, "Counter a", "B doesn't show the tab it got back")

    // Switching Space in a window showing a still needs the window key,
    // which takes the tab back first; the unit tests cover it
    // (StillTests.switchingSpaceEndsTheStill).

    // B closes the still's tab: A shows a new tab page with the command bar.
    windowA.click()
    windowA.tabRow("Counter a")?.click()
    _ = await windowA.waitForActiveRow("Counter a")
    still = await windowB.waitForStill()
    try require(still, "B shows no still of a")
    windowB.click()
    _ = await windowB.waitForActiveRow("Counter a")
    still = await windowA.waitForStill()
    try require(still, "A shows no still of a")
    browser.ui.typeKey("w", modifierFlags: .command)
    let closed = await windowA.waitForStill(false)
    XCTAssertTrue(closed, "Closing the still's tab left the still")
    XCTAssertTrue(
      windowA.element("clair.commandBarField").waitForExistence(timeout: 10),
      "A didn't open the command bar on its new tab page")
    XCTAssertFalse(windowA.tabTitles.contains("Counter a"), "The closed tab is still listed")
  }

  /// Creates a Space from the window's plus menu and closes the command bar
  /// its new tab page opens with.
  func createSpace(_ name: String, in window: NativeWindow) async throws {
    let plus = window.element("clair.footerNew")
    plus.click()
    let item = plus.menuItems["New Space…"]
    try require(item.waitForExistence(timeout: 5), "The plus menu has no New Space…")
    item.click()
    let field = window.element("clair.newSpaceName")
    try require(field.waitForExistence(timeout: 10), "The New Space form didn't open")
    field.typeText("\(name)\n")
    let shown = await Harness.wait(for: 15) { window.spaceName == name }
    try require(shown, "The window doesn't show the new Space \(name)")
    window.browser.ui.typeKey(.escape, modifierFlags: [])
  }

  func testSwitchingToASpaceWhoseTabsAreElsewhere() async throws {
    let (browser, windowA, windowB, a, b) = try await startWithTwoWindows()
    defer {
      a.close()
      b.close()
    }
    // A creates Work and opens w1, then w2, then shows Home: neither shows.
    windowA.click()
    try await createSpace("Work", in: windowA)
    let w1 = try await browser.open(counter("w1"))
    let w2 = try await browser.open(counter("w2"))
    defer {
      w1.close()
      w2.close()
    }
    _ = await windowA.waitForActiveRow("Counter w2")
    browser.ui.typeKey("1", modifierFlags: .control)
    _ = await Harness.wait(for: 15) { windowA.spaceName == "Home" }

    // B shows Work: the more recently active of its tabs, from A.
    windowB.click()
    browser.ui.typeKey("2", modifierFlags: .control)
    let shown = await windowB.waitForActiveRow("Counter w2")
    XCTAssertTrue(shown, "B didn't show Work's more recent tab: \(windowB.activeRow ?? "none")")
    XCTAssertFalse(windowA.showsStill, "A shows a still of a tab it didn't show")

    // B creates Travel, whose only tab B shows: A gets a new tab page there,
    // and B keeps its own.
    try await createSpace("Travel", in: windowB)
    let travelTab = windowB.activeRow
    windowA.click()
    browser.ui.typeKey("3", modifierFlags: .control)
    let travel = await Harness.wait(for: 15) { windowA.spaceName == "Travel" }
    try require(travel, "A didn't show Travel")
    let two = await windowA.waitForTabs { $0.count == 2 }
    XCTAssertTrue(two, "A didn't open a new tab page in Travel: \(windowA.tabTitles)")
    browser.ui.typeKey(.escape, modifierFlags: [])
    XCTAssertFalse(windowB.showsStill, "A took the tab B showed")
    XCTAssertEqual(windowB.activeRow, travelTab, "B's tab changed")
  }

  /// `arc-reference.md`'s close sequences with the row above held by another
  /// window, shown there and not, and a Space's last tab.
  func testTheTabShownAfterACloseAcrossWindows() async throws {
    let (browser, windowA, windowB, a, b) = try await startWithTwoWindows()
    defer {
      a.close()
      b.close()
    }
    // Rows: w (A), b (B), x (A), a (A), and the new tab page.
    windowA.click()
    let x = try await browser.open(counter("x"))
    let w = try await browser.open(counter("w"))
    defer {
      x.close()
      w.close()
    }
    let listed = await windowB.waitForTabs { $0.starts(with: ["Counter w", "Counter x", "Counter b", "Counter a"]) }
    try require(listed, "The rows aren't w, x, b, a: \(windowB.tabTitles)")

    // The row above, x, is A's and not shown there: B shows it, A doesn't
    // change.
    windowA.click()
    windowA.tabRow("Counter w")?.click()
    _ = await windowA.waitForActiveRow("Counter w")
    windowB.click()
    browser.ui.typeKey("w", modifierFlags: .command)
    var shown = await windowB.waitForActiveRow("Counter x")
    XCTAssertTrue(shown, "B didn't show the row above, held by A: \(windowB.activeRow ?? "none")")
    XCTAssertFalse(windowA.showsStill, "A shows a still of a tab it didn't show")

    // The row above, w, shows in A: B shows it, A keeps a still.
    browser.ui.typeKey("w", modifierFlags: .command)
    shown = await windowB.waitForActiveRow("Counter w")
    XCTAssertTrue(shown, "B didn't show the row above, shown in A: \(windowB.activeRow ?? "none")")
    let still = await windowA.waitForStill()
    XCTAssertTrue(still, "A shows no still of the row B took")

    // A Space's last tab: B shows Home's most recently active tab no window
    // shows.
    try await createSpace("Work", in: windowB)
    browser.ui.typeKey("w", modifierFlags: .command)
    let home = await Harness.wait(for: 15) { windowB.spaceName == "Home" }
    XCTAssertTrue(home, "Closing Work's only tab didn't show Home")
  }

  func testTabCommandsReachRowsFromAnotherWindow() async throws {
    let (browser, windowA, windowB, a, b) = try await startWithTwoWindows()
    defer {
      a.close()
      b.close()
    }
    windowA.click()
    let x = try await browser.open(counter("x"))
    defer { x.close() }
    // Rows: x (A), b (B), a (A), and the new tab page.
    let listed = await windowA.waitForTabs { $0.starts(with: ["Counter x", "Counter b", "Counter a"]) }
    try require(listed, "The rows aren't x, b, a: \(windowA.tabTitles)")

    // Cmd+2 in A reaches B's tab; Next Tab then A's own.
    browser.ui.typeKey("2", modifierFlags: .command)
    var shown = await windowA.waitForActiveRow("Counter b")
    XCTAssertTrue(shown, "Cmd+2 didn't show B's tab in A")
    let still = await windowB.waitForStill()
    XCTAssertTrue(still, "B shows no still of the tab Cmd+2 took")
    browser.ui.typeKey(.downArrow, modifierFlags: [.command, .option])
    shown = await windowA.waitForActiveRow("Counter a")
    XCTAssertTrue(shown, "Next Tab didn't go to the next row")

    // Close Tabs Below x closes rows whichever window holds them.
    windowA.tabRow("Counter x")?.rightClick()
    browser.ui.menuItems["Close Tabs Below"].click()
    let closed = await windowB.waitForTabs { $0 == ["Counter x"] }
    XCTAssertTrue(closed, "Close Tabs Below didn't close every row below: \(windowB.tabTitles)")
  }

  func testAPeekMovesWithItsTab() async throws {
    let (browser, windowA, windowB, a, b) = try await startWithTwoWindows()
    defer {
      a.close()
      b.close()
    }
    windowA.click()
    let links = try await browser.open(url("peek.html"))
    defer { links.close() }
    _ = await windowA.waitForActiveRow(PeekTests.links)
    try await links.shiftClick("plain")
    let opened = await browser.waitForTarget("?plain")
    try require(opened, "Shift+clicking the link opened nothing")
    try require(windowA.element("clair.peek").waitForExistence(timeout: 15), "A shows no Peek")
    let peek = try await browser.session(endingWith: "?plain")
    defer { peek.close() }
    _ = try await links.evaluate("window.mark = 3; 1")
    _ = try await peek.evaluate("window.mark = 4; 1")

    // B takes the tab: it shows with its Peek, both pages as they were.
    windowB.click()
    windowB.tabRow(PeekTests.links)?.click()
    try require(windowB.element("clair.peek").waitForExistence(timeout: 15), "B shows the tab without its Peek")
    let marks = [try await links.evaluate("window.mark") as? Double, try await peek.evaluate("window.mark") as? Double]
    XCTAssertEqual(marks, [3, 4], "Taking the tab reloaded a page")
    _ = await windowA.waitForStill()
    XCTAssertFalse(windowA.peekBadge.exists, "A's row shows the Peek's badge under the still")
    XCTAssertFalse(windowA.element("clair.peek").exists, "A's still shows the Peek")

    // B closes: A keeps the tab and its Peek.
    browser.ui.typeKey("w", modifierFlags: [.command, .shift])
    _ = try await browser.waitForNativeWindows(1)
    let badge = windowA.peekBadge.waitForExistence(timeout: 15)
    XCTAssertTrue(badge, "The tab's row lost its Peek's badge when B closed")
    windowA.tabRow(PeekTests.links)?.click()
    XCTAssertTrue(windowA.element("clair.peek").waitForExistence(timeout: 15), "The Peek didn't come with its tab")
    let peekMark = try await peek.evaluate("window.mark") as? Double
    XCTAssertEqual(peekMark, 4, "Closing the window reloaded the Peek")
  }

  func testClosingAWindowKeepsItsTabs() async throws {
    let (browser, windowA, _, a, b) = try await startWithTwoWindows()
    defer {
      a.close()
      b.close()
    }
    // B also holds a page that asks before it closes, armed by a click.
    let asking = try await browser.open(url("beforeunload.html"))
    defer { asking.close() }
    _ = try await asking.evaluate("document.body.id = 'body'; 1")
    try await asking.click("body")
    _ = try await b.evaluate("window.counter = 3; 1")

    // Closing B keeps its tabs in A, without asking.
    browser.ui.typeKey("w", modifierFlags: [.command, .shift])
    _ = try await browser.waitForNativeWindows(1)
    XCTAssertFalse(browser.ui.buttons["Leave"].waitForExistence(timeout: 3), "Closing B asked about a page")
    let kept = await windowA.waitForTabs { $0.contains("Counter b") && $0.contains("Clair leave page") }
    XCTAssertTrue(kept, "A doesn't list B's tabs: \(windowA.tabTitles)")
    windowA.tabRow("Counter b")?.click()
    _ = await windowA.waitForActiveRow("Counter b")
    let count = try await count(b)
    XCTAssertEqual(count, 3, "B's tab reloaded")

    // Closing the last window closes its tabs; Reopen Closed Window brings
    // them back.
    browser.ui.typeKey("w", modifierFlags: [.command, .shift])
    let leave = browser.ui.buttons["Leave"]
    if leave.waitForExistence(timeout: 10) {
      leave.click()
    }
    let closed = await browser.waitForTarget("?b", open: false, seconds: 30)
    try require(closed, "Closing the last window didn't close its tabs")
    browser.ui.typeKey("t", modifierFlags: [.command, .shift])
    let back = await browser.waitForTarget("?b", seconds: 30)
    XCTAssertTrue(back, "Reopen Closed Window didn't bring the tabs back")
  }

  func testAnIncognitoWindowListsItsOwnTabs() async throws {
    let (browser, a) = try await startWithPage("counter.html?a")
    defer { a.close() }
    let regular = browser.nativeWindows[0]
    browser.ui.typeKey("n", modifierFlags: [.command, .shift])
    let windows = try await browser.waitForNativeWindows(2)
    browser.ui.typeKey(.escape, modifierFlags: [])
    guard let incognito = windows.first(where: { $0.frame != regular.frame }) else {
      throw HarnessError("Can't find the incognito window")
    }
    let own = await incognito.waitForTabs { $0.count == 1 }
    XCTAssertTrue(own, "The incognito window lists other windows' tabs: \(incognito.tabTitles)")
    XCTAssertFalse(incognito.tabTitles.contains("Counter a"), "The incognito window lists a regular tab")
    browser.ui.typeKey("w", modifierFlags: [.command, .shift])
  }

  func testQuittingWithAStill() async throws {
    let (browser, windowA, windowB, a, b) = try await startWithTwoWindows()
    windowB.tabRow("Counter a")?.click()
    _ = await windowB.waitForActiveRow("Counter a")
    let still = await windowA.waitForStill()
    try require(still, "A shows no still")
    // Let session restore write the tabs.
    try await Task.sleep(for: .seconds(3))
    a.close()
    b.close()
    try await browser.quit()
    try await browser.start()
    let windows = try await browser.waitForNativeWindows(2, seconds: 60)
    for window in windows {
      let once = await window.waitForTabs(30) { $0.filter { $0 == "Counter a" }.count == 1 }
      XCTAssertTrue(once, "Counter a isn't listed once: \(window.tabTitles)")
      XCTAssertFalse(window.showsStill, "A window shows a still after a relaunch")
    }
    let newTabPages = windows.filter { $0.activeRow != "Counter a" && $0.activeRow != "Counter b" }
    XCTAssertEqual(newTabPages.count, 1, "The window that showed a still doesn't show a new tab page")
  }
}
