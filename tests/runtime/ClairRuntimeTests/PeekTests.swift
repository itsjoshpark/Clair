// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import Foundation
import XCTest

extension Browser {
  var peek: XCUIElement { element("clair.peek") }
  var peekBadge: XCUIElement { element("clair.peekBadge") }
  var peekClose: XCUIElement { element("clair.peekClose") }
  var peekExpand: XCUIElement { element("clair.peekExpand") }

  /// The sidebar's row titled `title`.
  func tabRow(_ title: String) -> XCUIElement? {
    tabRows.first { $0.label == title }
  }

  /// The tab whose URL ends with `suffix`, if one is open.
  func target(endingWith suffix: String) async throws -> Target? {
    try await pageTargets().first { $0.url.hasSuffix(suffix) }
  }

  /// Waits for a tab whose URL ends with `suffix` to open, or with `open`
  /// false, to close.
  func waitForTarget(_ suffix: String, open: Bool = true, seconds: TimeInterval = 15) async -> Bool {
    await Harness.wait(for: seconds) { try await (self.target(endingWith: suffix) != nil) == open }
  }

  /// A session on the tab whose URL ends with `suffix`.
  func session(endingWith suffix: String) async throws -> DevToolsSession {
    guard let target = try await target(endingWith: suffix) else {
      throw HarnessError("No tab ends with \(suffix)")
    }
    return try await session(onTarget: target.id)
  }
}

extension DevToolsSession {
  /// Clicks the element with `id` as the user would, with CDP's modifier bits
  /// (8 is Shift).
  func click(_ id: String, modifiers: Int = 0) async throws {
    let center =
      try await evaluate(
        "(() => { const r = document.getElementById('\(id)').getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2]; })()"
      ) as? [Double] ?? [0, 0]
    for type in ["mousePressed", "mouseReleased"] {
      try await send(
        "Input.dispatchMouseEvent",
        ["type": type, "x": center[0], "y": center[1], "button": "left", "clickCount": 1, "modifiers": modifiers])
    }
  }

  func shiftClick(_ id: String) async throws {
    try await click(id, modifiers: 8)
  }
}

/// Peek (add-peek tasks 2.6, 3.2, 4.1 and 5.1): Shift+click opens a link in a
/// Peek over its tab, which closes, expands and lives with its tab.
@MainActor
final class PeekTests: NativeWindowTestCase {
  static let links = "Clair Peek links"
  static let target = "Clair Peek target"

  /// Whether a switch or checkbox is on, whichever way it reports its value.
  static func isOn(_ toggle: XCUIElement) -> Bool? {
    switch toggle.value {
    case let number as NSNumber: number.boolValue
    case let text as String: text == "1" || text.lowercased() == "on"
    default: nil
    }
  }

  /// Starts Clair with another tab and then the page of links, which is
  /// active and first in the sidebar.
  func startWithLinks() async throws -> (Browser, DevToolsSession, DevToolsSession) {
    let browser = try await startBrowser()
    let other = try await browser.open(url("index.html?other"))
    let links = try await browser.open(url("peek.html"))
    browser.ui.activate()
    try require(browser.nativeWindow.waitForExistence(timeout: 30), "Clair shows no native window")
    let listed = await browser.waitForTabs { $0.first == Self.links }
    try require(listed, "The page of links isn't first: \(browser.tabTitles)")
    return (browser, links, other)
  }

  /// Shift+clicks a link and waits for its Peek.
  func openPeek(_ id: String, in page: DevToolsSession, browser: Browser, suffix: String) async throws {
    try await page.shiftClick(id)
    let opened = await browser.waitForTarget(suffix)
    try require(opened, "Shift+clicking #\(id) opened nothing")
    try require(browser.peek.waitForExistence(timeout: 15), "Shift+clicking #\(id) shows no Peek")
  }

  func testPeekOpensClosesAndExpands() async throws {
    let (browser, links, other) = try await startWithLinks()
    defer {
      links.close()
      other.close()
    }
    let rows = browser.tabRows.count

    // Shift+click opens a Peek: no window, no row, the parent's row badged and
    // highlighted, and the URL field on the Peek's site.
    try await openPeek("plain", in: links, browser: browser, suffix: "?plain")
    let windows = try await browser.windowCount()
    XCTAssertEqual(windows, 1, "Shift+click opened a window")
    XCTAssertEqual(browser.tabRows.count, rows, "The Peek has a row of its own")
    XCTAssertTrue(browser.peekBadge.exists, "The parent's row shows no badge")
    XCTAssertEqual(browser.tabRow(Self.links)?.isSelected, true, "The parent's row isn't highlighted")
    XCTAssertEqual(browser.element("clair.urlField").label, "127.0.0.1", "The URL field doesn't show the Peek's site")
    let peek = try await browser.session(endingWith: "?plain")
    defer { peek.close() }
    var parentVisibility = try await browser.visibility(of: links)
    var peekVisibility = try await browser.visibility(of: peek)
    XCTAssertEqual(parentVisibility, "visible", "The parent page isn't visible behind its Peek")
    XCTAssertEqual(peekVisibility, "visible", "The Peek's page isn't visible")

    // Ctrl+Tab moves on to the next row and leaves the Peek open; both pages
    // are hidden, and selecting the parent's row shows the Peek again.
    browser.ui.typeKey(.tab, modifierFlags: .control)
    let switched = await Harness.wait(for: 15) { try await browser.visibility(of: other) == "visible" }
    XCTAssertTrue(switched, "Ctrl+Tab didn't select the next row")
    parentVisibility = try await browser.visibility(of: links)
    peekVisibility = try await browser.visibility(of: peek)
    XCTAssertEqual(parentVisibility, "hidden", "The parent page is still visible behind another tab")
    XCTAssertEqual(peekVisibility, "hidden", "The Peek is still visible behind another tab")
    browser.tabRow(Self.links)?.click()
    var back = await Harness.wait(for: 15) { try await browser.visibility(of: peek) == "visible" }
    XCTAssertTrue(back, "Selecting the parent's row didn't show its Peek")
    // Cmd+2 and Cmd+1 count rows, so the parent and its Peek are one stop.
    browser.ui.typeKey("2", modifierFlags: .command)
    let second = await Harness.wait(for: 15) { try await browser.visibility(of: other) == "visible" }
    XCTAssertTrue(second, "Cmd+2 didn't select the second row")
    browser.ui.typeKey("1", modifierFlags: .command)
    back = await Harness.wait(for: 15) { try await browser.visibility(of: peek) == "visible" }
    XCTAssertTrue(back, "Cmd+1 didn't show the first row's Peek")

    // The Close button.
    browser.peekClose.click()
    var closed = await browser.waitForTarget("?plain", open: false)
    XCTAssertTrue(closed, "The Close button didn't close the Peek")
    XCTAssertFalse(browser.peekBadge.exists, "The badge stayed after the Peek closed")
    parentVisibility = try await browser.visibility(of: links)
    XCTAssertEqual(parentVisibility, "visible", "Closing the Peek didn't show its parent")

    // A link with a target, and Cmd+W, which closes only the Peek.
    try await openPeek("blank", in: links, browser: browser, suffix: "?blank")
    XCTAssertEqual(browser.tabRows.count, rows, "The target link's Peek has a row of its own")
    browser.ui.typeKey("w", modifierFlags: .command)
    closed = await browser.waitForTarget("?blank", open: false)
    XCTAssertTrue(closed, "Cmd+W didn't close the Peek")
    let parentOpen = try await browser.target(endingWith: "peek.html") != nil
    XCTAssertTrue(parentOpen, "Cmd+W closed the parent tab")

    // A click beside the Peek closes it without reaching the parent page.
    try await openPeek("plain", in: links, browser: browser, suffix: "?plain")
    let clicks = try await links.evaluate("window.clicks") as? Int ?? 0
    browser.cardPoint(0.03, 0.5).click()
    closed = await browser.waitForTarget("?plain", open: false)
    XCTAssertTrue(closed, "A click beside the Peek didn't close it")
    let clicksAfter = try await links.evaluate("window.clicks") as? Int ?? 0
    XCTAssertEqual(clicksAfter, clicks, "The click beside the Peek reached the parent page")

    // Inside a Peek, a plain click navigates it and Shift+click opens a tab
    // at the top.
    try await openPeek("plain", in: links, browser: browser, suffix: "?plain")
    let inPeek = try await browser.session(endingWith: "?plain")
    try await inPeek.click("next")
    let navigated = await browser.waitForTarget("?next")
    XCTAssertTrue(navigated, "A click inside the Peek didn't navigate it")
    XCTAssertEqual(browser.tabRows.count, rows, "Navigating inside the Peek added a row")
    inPeek.close()
    let inPeekAgain = try await browser.session(endingWith: "?next")
    defer { inPeekAgain.close() }
    try await inPeekAgain.shiftClick("out")
    let opened = await browser.waitForTabs { $0.count == rows + 1 }
    XCTAssertTrue(opened, "Shift+click inside the Peek opened no tab")
    XCTAssertEqual(browser.tabTitles.first, "Clair runtime test page", "The tab from the Peek isn't first")
    let peekStays = try await browser.target(endingWith: "?next") != nil
    XCTAssertTrue(peekStays, "Opening a tab from the Peek closed it")

    // Expand with Cmd+O, as in Arc: a row right below the parent, which goes
    // back through the Peek's history. (Unit tests cover the button.)
    browser.tabRow(Self.links)?.click()
    try require(browser.peek.waitForExistence(timeout: 15), "The parent's row didn't show its Peek")
    browser.ui.typeKey("o", modifierFlags: .command)
    let expanded = await browser.waitForTabs { $0.count == rows + 2 }
    XCTAssertTrue(expanded, "Cmd+O didn't expand the Peek into a row")
    let titles = browser.tabTitles
    if let parent = titles.firstIndex(of: Self.links), parent + 1 < titles.count {
      XCTAssertEqual(titles[parent + 1], Self.target, "The expanded Peek isn't right below its parent: \(titles)")
    } else {
      XCTFail("The parent's row is gone: \(titles)")
    }
    _ = try await inPeekAgain.evaluate("history.back(); 1")
    let wentBack = await browser.waitForTarget("?plain")
    XCTAssertTrue(wentBack, "Back in the expanded tab didn't return through the Peek's history")

    // Closing the parent's row closes its Peek too.
    browser.tabRow(Self.links)?.click()
    try await openPeek("blank", in: links, browser: browser, suffix: "?blank")
    let row = try XCTUnwrap(browser.tabRow(Self.links))
    row.hover()
    let close = browser.element("clair.tabClose", in: row)
    try require(close.waitForExistence(timeout: 10), "Hovering the parent's row shows no close button")
    close.click()
    let parentClosed = await browser.waitForTarget("peek.html", open: false)
    let peekClosed = await browser.waitForTarget("?blank", open: false)
    XCTAssertTrue(parentClosed, "The parent's row didn't close")
    XCTAssertTrue(peekClosed, "Closing the parent left its Peek open")
  }

  func testEscapeTheLinksSettingAndQuitting() async throws {
    let (browser, links, other) = try await startWithLinks()
    defer {
      links.close()
      other.close()
    }

    // Esc on a page that doesn't use it closes the Peek.
    try await openPeek("plain", in: links, browser: browser, suffix: "?plain")
    browser.ui.typeKey(.escape, modifierFlags: [])
    var closed = await browser.waitForTarget("?plain", open: false)
    XCTAssertTrue(closed, "Esc didn't close the Peek")

    // The page closes its own dialog on Esc and keeps the Peek; Close turns
    // into Confirm, and Esc again closes the Peek.
    try await openPeek("esc", in: links, browser: browser, suffix: "?modal")
    var page = try await browser.session(endingWith: "?modal")
    browser.ui.typeKey(.escape, modifierFlags: [])
    var kept = await Harness.wait(for: 5) { try await page.evaluate("window.escapes") as? Int == 1 }
    try require(kept, "The page didn't get the first Esc")
    XCTAssertTrue(
      browser.peekClose.label.contains("Confirm"), "Close doesn't show Confirm: \(browser.peekClose.label)")
    browser.ui.typeKey(.escape, modifierFlags: [])
    closed = await browser.waitForTarget("?modal", open: false)
    XCTAssertTrue(closed, "Esc while Confirm showed didn't close the Peek")
    page.close()

    // Two seconds later, Esc reaches the page again: its text field keeps it.
    try await openPeek("esc", in: links, browser: browser, suffix: "?modal")
    page = try await browser.session(endingWith: "?modal")
    defer { page.close() }
    browser.ui.typeKey(.escape, modifierFlags: [])
    kept = await Harness.wait(for: 5) { try await page.evaluate("window.escapes") as? Int == 1 }
    try require(kept, "The page didn't get the first Esc")
    try await Task.sleep(for: .seconds(2))
    XCTAssertFalse(browser.peekClose.label.contains("Confirm"), "Confirm didn't go away")
    browser.ui.typeKey(.escape, modifierFlags: [])
    kept = await Harness.wait(for: 5) { try await page.evaluate("window.escapes") as? Int == 2 }
    XCTAssertTrue(kept, "The Esc after Confirm went away didn't reach the page")
    let stillOpen = try await browser.target(endingWith: "?modal") != nil
    XCTAssertTrue(stillOpen, "Esc in the page's text field closed the Peek")
    browser.ui.typeKey(.escape, modifierFlags: [])
    closed = await browser.waitForTarget("?modal", open: false)
    XCTAssertTrue(closed, "Esc again didn't close the Peek")

    // With the Links setting off, Shift+click opens a window, as in Chromium.
    browser.ui.typeKey(",", modifierFlags: .command)
    let linksPage = browser.ui.toolbars.buttons["Links"]
    try require(linksPage.waitForExistence(timeout: 15), "Settings has no Links page")
    linksPage.click()
    // A form draws the toggle as a switch, its label beside it.
    let toggle = browser.ui.switches["clair.peekToggle"]
    try require(toggle.waitForExistence(timeout: 10), "The Links page has no Peek toggle")
    XCTAssertEqual(Self.isOn(toggle), true, "The Peek toggle isn't on by default")
    toggle.click()
    try await links.shiftClick("window")
    let window = await Harness.wait(for: 15) { try await browser.windowCount() == 2 }
    XCTAssertTrue(window, "Shift+click with the setting off didn't open a window")
    XCTAssertFalse(browser.peek.exists, "Shift+click with the setting off opened a Peek")
    if let opened = try await browser.target(endingWith: "?window") {
      let session = try await browser.browserSession()
      _ = try? await session.send("Target.closeTarget", ["targetId": opened.id])
      session.close()
    }
    toggle.click()
    XCTAssertEqual(Self.isOn(toggle), true, "The Peek toggle didn't turn back on")
    browser.ui.typeKey("w", modifierFlags: .command)

    // A Peek open at quit doesn't come back with its tab.
    try await openPeek("plain", in: links, browser: browser, suffix: "?plain")
    // Let session restore write the tabs.
    try await Task.sleep(for: .seconds(3))
    links.close()
    other.close()
    try await browser.quit()
    try await browser.start(arguments: ["--restore-last-session"])
    let restored = await browser.waitForTarget("peek.html", seconds: 60)
    try require(restored, "The Peek's parent tab didn't come back")
    let peekRestored = try await browser.target(endingWith: "?plain") != nil
    XCTAssertFalse(peekRestored, "The Peek came back after quitting")
  }
}
