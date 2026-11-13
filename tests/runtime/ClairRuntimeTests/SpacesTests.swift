// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import Foundation
import XCTest

extension Browser {
  /// The Space header's name, which SwiftUI exposes as the text's value.
  /// While the name is a field, as during Rename Space…, there's no name to
  /// read: reading a missing element fails the test, which then hangs.
  var spaceName: String {
    let name = element("clair.spaceName")
    return name.exists ? name.value as? String ?? "" : ""
  }

  /// The footer switcher's items, in order.
  var switcherItems: [XCUIElement] {
    nativeWindow.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier MATCHES 'clair\\\\.space\\\\.[0-9]+'"))
      .allElementsBoundByIndex
  }

  var spacesMenu: XCUIElement { ui.menuBars.menuBarItems["Spaces"] }

  /// The Spaces menu's Space items, in order: those after its last separator.
  var spacesMenuSpaces: [String] {
    spacesMenu.click()
    defer { ui.typeKey(.escape, modifierFlags: []) }
    let items = spacesMenu.menuItems.allElementsBoundByIndex
    let commands: Set<String> = [
      "New Space…", "Rename Space", "Change Profile", "Manage Spaces…", "Next Space", "Previous Space", "",
    ]
    return items.map(\.title).filter { !commands.contains($0) }
  }

  func chooseSpacesItem(_ title: String) throws {
    try require(spacesMenu.waitForExistence(timeout: 30), "The menu bar has no Spaces menu")
    spacesMenu.click()
    let item = spacesMenu.menuItems[title]
    try require(item.waitForExistence(timeout: 5), "The Spaces menu has no \(title)")
    item.click()
  }

  /// Waits for the window to show the Space named `name`.
  func waitForSpace(_ name: String, seconds: TimeInterval = 15) async -> Bool {
    await Harness.wait(for: seconds) { self.spaceName == name }
  }

  /// The title of the row the window highlights.
  var activeRow: String? {
    tabRows.first(where: \.isSelected)?.label
  }

  func waitForActiveRow(_ title: String, seconds: TimeInterval = 15) async -> Bool {
    await Harness.wait(for: seconds) { self.activeRow == title }
  }
}

/// Spaces (add-spaces task 3.11), driven through the sidebar, the menu bar
/// and the keyboard, with a counter page whose state shows that a tab kept
/// its page.
@MainActor
final class SpacesTests: NativeWindowTestCase {
  func counter(_ name: String) -> String { url("counter.html?\(name)") }

  /// Creates a Space from the Spaces menu or the footer's plus menu.
  func createSpace(_ name: String, in browser: Browser, fromPlusMenu: Bool = false) async throws {
    if fromPlusMenu {
      let plus = browser.element("clair.footerNew")
      plus.click()
      // The plus menu's own item: the Spaces menu has one of the same title.
      let item = plus.menuItems["New Space…"]
      try require(item.waitForExistence(timeout: 5), "The plus menu has no New Space…")
      item.click()
    } else {
      try browser.chooseSpacesItem("New Space…")
    }
    let field = browser.element("clair.newSpaceName")
    try require(field.waitForExistence(timeout: 10), "The New Space form didn't open")
    let create = browser.element("clair.createSpace")
    XCTAssertFalse(create.isEnabled, "Create Space is on before a name is typed")
    field.click()
    field.typeText(name)
    create.click()
    let shown = await browser.waitForSpace(name)
    try require(shown, "The window doesn't show the new Space \(name): \(browser.spaceName)")
    // The new Space opens on a new tab page with the command bar; close it.
    browser.ui.typeKey(.escape, modifierFlags: [])
  }

  /// The emoji picker the icon field opens takes the typing, as its search
  /// field, while it's open: Esc closes it and leaves the field editing.
  func closeEmojiPicker(in browser: Browser) async throws {
    let opened = await Harness.wait(for: 3) {
      try Harness.run("/usr/bin/pgrep", ["-x", "CharacterPalette"]).status == 0
    }
    if opened {
      try await Task.sleep(for: .seconds(0.5))
      browser.ui.typeKey(.escape, modifierFlags: [])
      try await Task.sleep(for: .seconds(0.5))
    }
  }

  func testFirstLaunchHasOneSpaceAndNoSwitcher() async throws {
    let (browser, tab) = try await startWithPage("counter.html?a")
    defer { tab.close() }
    XCTAssertEqual(browser.spaceName, "Home", "The first Space isn't Home")
    XCTAssertTrue(browser.switcherItems.isEmpty, "One Space shows a switcher")
    XCTAssertEqual(browser.spacesMenuSpaces, ["Home"], "The Spaces menu doesn't list Home alone")
  }

  func testCreatingSpacesAndCancelling() async throws {
    let (browser, tab) = try await startWithPage("counter.html?a")
    defer { tab.close() }
    try await createSpace("Work", in: browser, fromPlusMenu: true)
    XCTAssertEqual(browser.switcherItems.map(\.label), ["Home", "Work"], "The switcher doesn't list both Spaces")
    // A new Space opens on a new tab page.
    XCTAssertEqual(browser.tabRows.count, 1, "The new Space doesn't have one tab")

    try await createSpace("Travel", in: browser)
    XCTAssertEqual(browser.switcherItems.map(\.label), ["Home", "Work", "Travel"], "Travel isn't last")

    // Esc leaves the form, creating nothing.
    try browser.chooseSpacesItem("New Space…")
    let field = browser.element("clair.newSpaceName")
    try require(field.waitForExistence(timeout: 10), "The New Space form didn't open again")
    field.click()
    field.typeText("Nope")
    browser.ui.typeKey(.escape, modifierFlags: [])
    let back = await browser.waitForSpace("Travel")
    XCTAssertTrue(back, "Esc didn't return to the earlier Space")
    XCTAssertFalse(browser.spacesMenuSpaces.contains("Nope"), "Esc created a Space")
  }

  func testSwitchingKeepsTheWindowFrame() async throws {
    let (browser, tab) = try await startWithPage("counter.html?a")
    defer { tab.close() }
    try await createSpace("Work", in: browser)
    try await createSpace("Travel", in: browser)
    let frame = browser.nativeWindow.frame

    browser.switcherItems[0].click()
    var shown = await browser.waitForSpace("Home")
    XCTAssertTrue(shown, "Clicking the switcher didn't show Home")
    XCTAssertEqual(browser.activeRow, "Counter a", "Home doesn't show its tab")

    browser.ui.typeKey("3", modifierFlags: .control)
    shown = await browser.waitForSpace("Travel")
    XCTAssertTrue(shown, "Ctrl+3 didn't show the third Space")

    // Next and Previous wrap around at the ends.
    browser.ui.typeKey(.rightArrow, modifierFlags: [.command, .option])
    shown = await browser.waitForSpace("Home")
    XCTAssertTrue(shown, "Opt+Cmd+Right on the last Space didn't show the first")
    browser.ui.typeKey(.leftArrow, modifierFlags: [.command, .option])
    shown = await browser.waitForSpace("Travel")
    XCTAssertTrue(shown, "Opt+Cmd+Left on the first Space didn't show the last")

    XCTAssertEqual(browser.nativeWindow.frame, frame, "Switching Spaces changed the window's frame")
  }

  func testAnEmptySpaceAndANewWindow() async throws {
    let (browser, tab) = try await startWithPage("counter.html?a")
    defer { tab.close() }
    try await createSpace("Work", in: browser)
    // Work's only row is a page: closing it keeps the window on Work, on a
    // new tab page with the command bar (add-profiles D13).
    let x = try await browser.open(counter("x"))
    defer { x.close() }
    browser.tabRow("New Tab")?.click()
    browser.ui.typeKey("w", modifierFlags: .command)
    let one = await browser.waitForTabs { $0 == ["Counter x"] }
    try require(one, "Work doesn't list x alone: \(browser.tabTitles)")
    browser.ui.typeKey("w", modifierFlags: .command)
    let emptied = await browser.waitForTabs { $0.count == 1 && $0 != ["Counter x"] }
    XCTAssertTrue(emptied, "Closing Work's only tab didn't leave a new tab page: \(browser.tabTitles)")
    XCTAssertEqual(browser.spaceName, "Work", "Closing Work's only tab left Work")
    XCTAssertTrue(
      browser.element("clair.commandBarField").waitForExistence(timeout: 10),
      "An emptied Space didn't open the command bar")
    browser.ui.typeKey(.escape, modifierFlags: [])

    // Cmd+N opens a window on the same Space.
    browser.ui.typeKey("n", modifierFlags: .command)
    let opened = await Harness.wait(for: 30) {
      browser.ui.windows.containing(.any, identifier: "clair.sidebar").count == 2
    }
    try require(opened, "Cmd+N didn't open a window")
    let names = browser.ui.windows.containing(.any, identifier: "clair.sidebar").allElementsBoundByIndex.map {
      $0.descendants(matching: .any).matching(identifier: "clair.spaceName").firstMatch.value as? String ?? ""
    }
    XCTAssertEqual(names, ["Work", "Work"], "The new window doesn't show the Space it was opened from")
    browser.ui.typeKey("w", modifierFlags: [.command, .shift])
  }

  func testTabCommandsStayInTheSpace() async throws {
    let (browser, tab) = try await startWithPage("counter.html?home")
    defer { tab.close() }
    try await createSpace("Work", in: browser)
    // Close Work's new tab page once it has tabs of its own.
    let x = try await browser.open(counter("x"))
    let y = try await browser.open(counter("y"))
    let z = try await browser.open(counter("z"))
    defer {
      x.close()
      y.close()
      z.close()
    }
    let listed = await browser.waitForTabs { $0.starts(with: ["Counter z", "Counter y", "Counter x"]) }
    try require(listed, "New tabs didn't join the shown Space at the top: \(browser.tabTitles)")
    XCTAssertFalse(browser.tabTitles.contains("Counter home"), "Work lists Home's tab")
    browser.tabRow("New Tab")?.click()
    if browser.tabTitles.count > 3 {
      browser.ui.typeKey("w", modifierFlags: .command)
    }
    let three = await browser.waitForTabs { $0 == ["Counter z", "Counter y", "Counter x"] }
    try require(three, "Work doesn't list its three tabs: \(browser.tabTitles)")

    browser.ui.typeKey("2", modifierFlags: .command)
    var active = await browser.waitForActiveRow("Counter y")
    XCTAssertTrue(active, "Cmd+2 didn't select the Space's second row")
    browser.ui.typeKey("3", modifierFlags: .command)
    active = await browser.waitForActiveRow("Counter x")
    XCTAssertTrue(active, "Cmd+3 didn't select the Space's third row")
    // Next Tab at the Space's end goes to its first row, not into Home.
    browser.ui.typeKey(.downArrow, modifierFlags: [.command, .option])
    active = await browser.waitForActiveRow("Counter z")
    XCTAssertTrue(active, "Next Tab didn't wrap within the Space")
    browser.ui.typeKey(.upArrow, modifierFlags: [.command, .option])
    active = await browser.waitForActiveRow("Counter x")
    XCTAssertTrue(active, "Previous Tab didn't wrap within the Space")
    XCTAssertEqual(browser.spaceName, "Work", "A tab command left the Space")

    // Ctrl+Shift+PageUp and PageDown move the active row, stopping at the
    // ends.
    browser.ui.typeKey(.pageUp, modifierFlags: [.control, .shift])
    var moved = await browser.waitForTabs { $0 == ["Counter z", "Counter x", "Counter y"] }
    XCTAssertTrue(moved, "Ctrl+Shift+PageUp didn't move the row up: \(browser.tabTitles)")
    XCTAssertEqual(browser.activeRow, "Counter x", "Moving a row changed the active tab")
    browser.ui.typeKey(.pageDown, modifierFlags: [.control, .shift])
    browser.ui.typeKey(.pageDown, modifierFlags: [.control, .shift])
    moved = await browser.waitForTabs { $0 == ["Counter z", "Counter y", "Counter x"] }
    XCTAssertTrue(moved, "Ctrl+Shift+PageDown didn't move the row down, or went past the end: \(browser.tabTitles)")
  }

  func testRenameIconAndDelete() async throws {
    let (browser, tab) = try await startWithPage("counter.html?a")
    defer { tab.close() }
    try await createSpace("Work", in: browser)

    // Rename Space… turns the name into a field with its text selected.
    browser.element("clair.spaceHeader").rightClick()
    browser.ui.menuItems["Rename Space…"].click()
    let field = browser.element("clair.spaceNameField")
    try require(field.waitForExistence(timeout: 5), "Rename Space… didn't show a field")
    let focused = await Harness.wait(for: 5) { field.value(forKey: "hasKeyboardFocus") as? Bool == true }
    try require(focused, "Rename Space… didn't put the keyboard in the field")
    field.typeKey("a", modifierFlags: .command)
    field.typeText("Research\n")
    var renamed = await browser.waitForSpace("Research")
    XCTAssertTrue(renamed, "Return didn't keep the new name")
    XCTAssertTrue(browser.spacesMenuSpaces.contains("Research"), "The Spaces menu doesn't show the new name")
    // An empty name keeps the earlier one.
    browser.element("clair.spaceHeader").rightClick()
    browser.ui.menuItems["Rename Space…"].click()
    try require(field.waitForExistence(timeout: 5), "Rename Space… didn't show a field again")
    _ = await Harness.wait(for: 5) { field.value(forKey: "hasKeyboardFocus") as? Bool == true }
    field.typeKey("a", modifierFlags: .command)
    field.typeKey(.delete, modifierFlags: [])
    field.typeKey(.return, modifierFlags: [])
    renamed = await browser.waitForSpace("Research")
    XCTAssertTrue(renamed, "An empty name replaced the Space's name")

    // Change Space Icon…: a letter changes nothing; an emoji is kept alone;
    // Delete removes it.
    browser.element("clair.spaceHeader").rightClick()
    browser.ui.menuItems["Change Space Icon…"].click()
    let icon = browser.element("clair.spaceIconField")
    try require(icon.waitForExistence(timeout: 5), "Change Space Icon… didn't show the icon field")
    try await closeEmojiPicker(in: browser)
    icon.typeText("a")
    XCTAssertEqual(icon.value as? String ?? "", "", "A letter became the icon")
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString("x📚✈️", forType: .string)
    icon.typeKey("v", modifierFlags: .command)
    let picked = await Harness.wait(for: 5) { icon.value as? String == "📚" }
    XCTAssertTrue(picked, "The icon isn't the first emoji pasted: \(icon.value ?? "")")
    icon.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(browser.spacesMenuSpaces.contains("📚 Research"), "The Spaces menu doesn't show the icon")
    browser.element("clair.spaceHeader").rightClick()
    browser.ui.menuItems["Change Space Icon…"].click()
    try require(icon.waitForExistence(timeout: 5), "The icon field didn't show again")
    try await closeEmojiPicker(in: browser)
    icon.typeKey(.delete, modifierFlags: [])
    icon.typeKey(.return, modifierFlags: [])
    let removed = await Harness.wait(for: 5) { browser.spacesMenuSpaces.contains("Research") }
    XCTAssertTrue(removed, "Delete didn't remove the icon")

    // Delete Space on a Space with tabs asks, then closes them.
    let doomed = try await browser.open(counter("doomed"))
    defer { doomed.close() }
    browser.element("clair.spaceHeader").rightClick()
    browser.ui.menuItems["Delete Space"].click()
    try require(browser.dialog.waitForExistence(timeout: 10), "Deleting a Space with tabs didn't ask")
    browser.dialogButton("clair.dialogDefault").click()
    let home = await browser.waitForSpace("Home")
    XCTAssertTrue(home, "The window didn't show the Space before the deleted one")
    let closed = await browser.waitForTarget("?doomed", open: false)
    XCTAssertTrue(closed, "The deleted Space's tabs didn't close")
    XCTAssertTrue(browser.switcherItems.isEmpty, "The deleted Space is still in the switcher")

    // With one Space, Delete Space is off.
    browser.element("clair.spaceHeader").rightClick()
    XCTAssertFalse(browser.ui.menuItems["Delete Space"].isEnabled, "The only Space can be deleted")
    browser.ui.typeKey(.escape, modifierFlags: [])
  }

  func testMoveToSpaceKeepsThePage() async throws {
    let (browser, tab) = try await startWithPage("counter.html?stay")
    defer { tab.close() }
    let moving = try await browser.open(counter("moving"))
    defer { moving.close() }
    try await createSpace("Work", in: browser)
    browser.ui.typeKey("1", modifierFlags: .control)
    var shown = await browser.waitForSpace("Home")
    try require(shown, "Ctrl+1 didn't show Home")
    _ = try await moving.evaluate("window.counter = 5; 1")

    // The active tab moves, and the window follows it to Work, the tab
    // still active (add-profiles D9).
    browser.tabRow("Counter moving")?.click()
    let selected = await browser.waitForActiveRow("Counter moving")
    try require(selected, "The tab to move isn't active")
    browser.tabRow("Counter moving")?.rightClick()
    let move = browser.ui.menuItems["Move to Space"]
    move.hover()
    // The submenu's own item: the Spaces menu has one of the same title.
    let work = move.menuItems["Work"]
    try require(work.waitForExistence(timeout: 5), "Move to Space doesn't list Work")
    work.click()
    shown = await browser.waitForSpace("Work")
    XCTAssertTrue(shown, "Moving the active tab didn't show Work: \(browser.spaceName)")
    let followed = await browser.waitForActiveRow("Counter moving")
    XCTAssertTrue(followed, "The moved tab isn't active in Work: \(browser.activeRow ?? "none")")
    browser.ui.typeKey("1", modifierFlags: .control)
    shown = await browser.waitForSpace("Home")
    let gone = await browser.waitForTabs { !$0.contains("Counter moving") }
    XCTAssertTrue(gone, "The moved tab is still in Home")

    browser.ui.typeKey("2", modifierFlags: .control)
    shown = await browser.waitForSpace("Work")
    try require(shown, "Ctrl+2 didn't show Work")
    XCTAssertEqual(browser.tabTitles.first, "Counter moving", "The moved tab isn't first in Work")
    let count = try await moving.evaluate("window.counter") as? Double
    XCTAssertEqual(count, 5, "Moving the tab reloaded its page")
  }

  func testManageSpaces() async throws {
    let (browser, tab) = try await startWithPage("counter.html?a")
    defer { tab.close() }
    try await createSpace("Work", in: browser)
    try await createSpace("Travel", in: browser)
    try browser.chooseSpacesItem("Manage Spaces…")
    try require(browser.dialog.waitForExistence(timeout: 10), "Manage Spaces… didn't open its dialog")
    let name = browser.dialogButton("clair.manageSpacesName")
    XCTAssertEqual(name.value as? String, "Travel", "The dialog didn't open on the window's Space")

    // Renaming shows at once in the sidebar.
    name.click()
    name.typeKey("a", modifierFlags: .command)
    name.typeText("Research")
    let renamed = await browser.waitForSpace("Research")
    XCTAssertTrue(renamed, "Renaming in the dialog didn't show in the sidebar")

    // Add, then Remove a Space without tabs, at once.
    browser.dialogButton("clair.manageSpacesAdd").click()
    let added = await Harness.wait(for: 5) { browser.switcherItems.map(\.label).last == "New Space" }
    XCTAssertTrue(added, "Add didn't add a Space last")
    XCTAssertEqual(name.value as? String, "New Space", "Add didn't select the new Space")
    browser.dialogButton("clair.manageSpacesRemove").click()
    let removed = await Harness.wait(for: 5) { browser.switcherItems.count == 3 }
    XCTAssertTrue(removed, "Remove didn't remove the Space without tabs at once")

    browser.dialogButton("clair.dialogDefault").click()
    let closed = await Harness.wait(for: 5) { !browser.dialog.exists }
    XCTAssertTrue(closed, "Done didn't close the dialog")
  }

  /// `arc-reference.md`'s close sequences: the tab the user came from, then
  /// the row above, then the row below.
  func testTheTabShownAfterAClose() async throws {
    let (browser, tab) = try await startWithPage("counter.html?I")
    defer { tab.close() }
    var sessions: [DevToolsSession] = []
    for name in ["A", "B", "C", "D", "E"] {
      sessions.append(try await browser.open(counter(name)))
    }
    defer { sessions.forEach { $0.close() } }
    // Below them, the new tab page a fresh launch opens with.
    let listed = await browser.waitForTabs {
      $0.starts(with: ["Counter E", "Counter D", "Counter C", "Counter B", "Counter A", "Counter I"])
    }
    try require(listed, "The rows aren't E, D, C, B, A, I: \(browser.tabTitles)")

    func close(expecting title: String, _ message: String) async {
      browser.ui.typeKey("w", modifierFlags: .command)
      let shown = await browser.waitForActiveRow(title)
      XCTAssertTrue(shown, "\(message): \(browser.activeRow ?? "none")")
    }
    browser.tabRow("Counter A")?.click()
    browser.tabRow("Counter C")?.click()
    await close(expecting: "Counter A", "Closing C didn't go back to A, where it was selected from")
    await close(expecting: "Counter B", "After a close, closing A didn't show the row above")
    await close(expecting: "Counter D", "Closing B didn't show the row above")
    await close(expecting: "Counter E", "Closing D didn't show the row above")
    await close(expecting: "Counter I", "Closing the top row didn't show the row below")

    // Closing a Space's last page keeps the window on it, on a new tab page
    // (add-profiles D13).
    try await createSpace("Work", in: browser)
    let page = try await browser.open(counter("page"))
    defer { page.close() }
    browser.tabRow("New Tab")?.click()
    browser.ui.typeKey("w", modifierFlags: .command)
    _ = await browser.waitForTabs { $0 == ["Counter page"] }
    browser.ui.typeKey("w", modifierFlags: .command)
    let stays = await browser.waitForTabs { $0.count == 1 && $0 != ["Counter page"] }
    XCTAssertTrue(stays, "Closing Work's only tab didn't leave a new tab page: \(browser.tabTitles)")
    XCTAssertEqual(browser.spaceName, "Work", "Closing Work's only tab left Work")
  }

  /// A page that asks before it closes: Chromium's confirmation makes its
  /// tab active again, so the tab shown after the close is chosen once the
  /// page agrees (add-spaces D4).
  func testClosingATabThatAsks() async throws {
    let (browser, tab) = try await startWithPage("counter.html?I")
    defer { tab.close() }
    let a = try await browser.open(counter("A"))
    let asking = try await browser.open(url("beforeunload.html"))
    let b = try await browser.open(counter("B"))
    defer {
      a.close()
      asking.close()
      b.close()
    }
    let page = "Clair leave page"
    let listed = await browser.waitForTabs { $0.starts(with: ["Counter B", page, "Counter A", "Counter I"]) }
    try require(listed, "The rows aren't B, the page that asks, A, I: \(browser.tabTitles)")
    browser.tabRow("Counter I")?.click()
    browser.tabRow(page)?.click()
    let selected = await browser.waitForActiveRow(page)
    try require(selected, "The page that asks isn't active: \(browser.activeRow ?? "none")")
    // The page asks only after a click.
    _ = try await asking.evaluate("document.body.id = 'body'; 1")
    try await asking.click("body")

    browser.ui.typeKey("w", modifierFlags: .command)
    let cancel = browser.ui.buttons["Cancel"]
    try require(cancel.waitForExistence(timeout: 15), "Closing the tab didn't ask about the page")
    cancel.click()
    try await Task.sleep(for: .seconds(1))
    XCTAssertEqual(browser.activeRow, page, "Staying on the page showed another tab")

    browser.ui.typeKey("w", modifierFlags: .command)
    let leave = browser.ui.buttons["Leave"]
    try require(leave.waitForExistence(timeout: 15), "Closing the tab again didn't ask about the page")
    leave.click()
    let back = await browser.waitForActiveRow("Counter I")
    XCTAssertTrue(back, "Leaving the page didn't go back to I, where it was selected from: \(browser.activeRow ?? "none")")
    let closed = await browser.waitForTabs { $0.starts(with: ["Counter B", "Counter A", "Counter I"]) }
    XCTAssertTrue(closed, "The page that asked didn't close: \(browser.tabTitles)")
    XCTAssertEqual(browser.spaceName, "Home", "The close left the Space")
  }

  func testQuitAndRelaunchRestoresSpaces() async throws {
    let (browser, first) = try await startWithPage("counter.html?h1")
    let h2 = try await browser.open(counter("h2"))
    try await createSpace("Work", in: browser)
    var work: [DevToolsSession] = []
    for name in ["w1", "w2", "w3"] {
      work.append(try await browser.open(counter(name)))
    }
    // Leave Work with its three tabs: close the new tab page it opened with.
    browser.tabRow("New Tab")?.click()
    if browser.tabTitles.count > 3 {
      browser.ui.typeKey("w", modifierFlags: .command)
    }
    let listed = await browser.waitForTabs { $0 == ["Counter w3", "Counter w2", "Counter w1"] }
    try require(listed, "Work doesn't list its three tabs: \(browser.tabTitles)")
    let workRows = browser.tabTitles
    browser.ui.typeKey("1", modifierFlags: .control)
    _ = await browser.waitForSpace("Home")
    let homeRows = browser.tabTitles
    browser.ui.typeKey("2", modifierFlags: .control)
    _ = await browser.waitForSpace("Work")

    // Let session restore write the tabs, then quit with windows restored
    // (add-profiles D6).
    try await Task.sleep(for: .seconds(3))
    ([first, h2] + work).forEach { $0.close() }
    try await browser.quit()
    try Harness.setRestoreWindows(true)
    try await browser.start()
    try require(browser.nativeWindow.waitForExistence(timeout: 60), "Clair didn't come back")
    let restored = await browser.waitForSpace("Work", seconds: 60)
    try require(restored, "The window doesn't show the Space it showed: \(browser.spaceName)")
    let rowsBack = await browser.waitForTabs(60) { $0 == workRows }
    XCTAssertTrue(rowsBack, "Work's tabs didn't come back in order: \(browser.tabTitles)")
    browser.ui.typeKey("1", modifierFlags: .control)
    _ = await browser.waitForSpace("Home")
    let homeBack = await browser.waitForTabs { $0 == homeRows }
    XCTAssertTrue(homeBack, "Home's tabs didn't come back: \(browser.tabTitles)")

    // Restore Last Closed Tab returns a tab to its Space and shows it.
    browser.ui.typeKey("2", modifierFlags: .control)
    _ = await browser.waitForSpace("Work")
    browser.tabRow("Counter w2")?.click()
    _ = await browser.waitForActiveRow("Counter w2")
    browser.ui.typeKey("w", modifierFlags: .command)
    let closed = await browser.waitForTabs { !$0.contains("Counter w2") }
    try require(closed, "Cmd+W didn't close w2")
    browser.ui.typeKey("1", modifierFlags: .control)
    _ = await browser.waitForSpace("Home")
    browser.ui.typeKey("t", modifierFlags: [.command, .shift])
    let back = await browser.waitForSpace("Work")
    XCTAssertTrue(back, "Restoring the tab didn't show its Space")
    let inWork = await browser.waitForTabs { $0.contains("Counter w2") }
    XCTAssertTrue(inWork, "The restored tab isn't in Work: \(browser.tabTitles)")
  }

  /// D11's default is a default: "Open the New Tab page" still opens one new
  /// tab page.
  func testOnStartupSettingStillApplies() async throws {
    let (browser, tab) = try await startWithPage("counter.html?a")
    let settings = try await browser.open("chrome://settings/onStartup")
    // Chromium's settings page sets the pref as its radio button does.
    _ = try await settings.evaluate(
      "(async () => { await chrome.settingsPrivate.setPref('session.restore_on_startup', 5); return 1; })()")
    try await Task.sleep(for: .seconds(3))
    settings.close()
    tab.close()
    try await browser.quit()
    try await browser.start()
    try require(browser.nativeWindow.waitForExistence(timeout: 60), "Clair didn't come back")
    let one = await Harness.wait(for: 30) {
      let targets = try await browser.pageTargets()
      return targets.count == 1 && targets.allSatisfy { $0.url.hasPrefix("chrome://newtab") }
    }
    XCTAssertTrue(one, "\"Open the New Tab page\" didn't open one new tab page")
    let restored = try await browser.target(endingWith: "?a")
    XCTAssertNil(restored, "The tabs came back though the user chose a new tab page")
  }
}
