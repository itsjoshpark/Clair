// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import Foundation
import XCTest

extension Browser {
  /// The dialog showing on any window (add-clair-dialogs).
  var dialog: XCUIElement {
    ui.descendants(matching: .any).matching(identifier: "clair.dialog").firstMatch
  }

  func dialogButton(_ identifier: String) -> XCUIElement {
    dialog.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }
}

/// Clair's own dialogs (add-clair-dialogs task 2.2), through an extension's
/// install dialog: it shows as a sheet and blocks its own window only.
@MainActor
final class DialogTests: NativeWindowTestCase {
  /// Lets the test server's CRX ask to install (ungoogled-chromium's flag).
  static let installArguments = ["--extension-mime-request-handling=always-prompt-for-install"]
  static let extensionName = "Clair Install Prompt Test"

  private func askToInstall(from tab: DevToolsSession, browser: Browser) async throws {
    _ = try await tab.evaluate("location.href = '\(fixture.baseURL)/install-prompt.crx'; 1")
    try require(browser.dialog.waitForExistence(timeout: 30), "The CRX didn't ask to install")
  }

  func testInstallDialogBlocksOnlyItsWindow() async throws {
    let (browser, other) = try await startWithPage("index.html?other", arguments: Self.installArguments)
    let tab = try await browser.open(url("find.html"))
    defer {
      other.close()
      tab.close()
    }
    let two = await browser.waitForTabs { $0.count >= 2 }
    try require(two, "The sidebar doesn't list two tabs: \(browser.tabTitles)")
    // The page has focus, and counts the keys it gets.
    browser.cardPoint(0.5, 0.5).click()
    _ = try await tab.evaluate("window.keys = 0; addEventListener('keydown', () => window.keys++, true); 1")

    try await askToInstall(from: tab, browser: browser)
    let dialog = browser.dialog
    XCTAssertEqual(dialog.elementType, .sheet, "The dialog isn't a sheet of its window")
    XCTAssertTrue(
      dialog.staticTexts["Add “\(Self.extensionName)” to Clair?"].exists, "The dialog's title is wrong")
    XCTAssertTrue(browser.dialogButton("clair.dialogTitle").exists, "The dialog's title has no identifier")
    XCTAssertTrue(browser.dialogButton("clair.dialogCancel").exists, "The dialog has no Cancel button")
    XCTAssertTrue(browser.dialogButton("clair.dialogDefault").exists, "The dialog has no Add Extension button")

    // A click on another tab's row does nothing.
    guard let row = browser.tabRows.first(where: { $0.label == "Clair runtime test page" }) else {
      throw HarnessError("No row for the other tab: \(browser.tabTitles)")
    }
    row.click()
    try await Task.sleep(for: .seconds(1))
    let otherVisibility = try await browser.visibility(of: other)
    XCTAssertEqual(otherVisibility, "hidden", "A click behind the dialog selected a tab")
    XCTAssertTrue(dialog.exists, "A click behind the dialog closed it")

    // Typing doesn't reach the page.
    browser.ui.typeText("abc")
    let keys = try await tab.evaluate("window.keys") as? Double
    XCTAssertEqual(keys, 0, "Typing behind the dialog reached the page")
    XCTAssertTrue(dialog.exists, "Typing closed the dialog")

    // Another window still works.
    let second = try await browser.open(url("link.html"), newWindow: true)
    defer { second.close() }
    // The window whose sidebar lists the link page.
    let secondWindow = browser.ui.windows.containing(
      NSPredicate(format: "identifier == 'clair.tabRow' AND label == 'Clair link page'")
    ).firstMatch
    try require(secondWindow.waitForExistence(timeout: 30), "The second window didn't open")
    secondWindow.click()
    secondWindow.typeKey("t", modifierFlags: .command)
    let field = secondWindow.descendants(matching: .any).matching(identifier: "clair.commandBarField").firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 10), "The other window doesn't respond while the dialog shows")
    browser.ui.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(dialog.exists, "Esc in the other window closed the dialog")
  }

  func testEscCancelsAndReturnInstalls() async throws {
    let (browser, tab) = try await startWithPage("find.html", arguments: Self.installArguments)
    defer { tab.close() }
    browser.cardPoint(0.5, 0.5).click()

    // Esc cancels, and focus goes back to the page.
    try await askToInstall(from: tab, browser: browser)
    browser.ui.typeKey(.escape, modifierFlags: [])
    let closed = await Harness.wait(for: 10) { !browser.dialog.exists }
    try require(closed, "Esc didn't close the dialog")
    let focused = await Harness.wait(for: 10) { try await tab.evaluate("document.hasFocus()") as? Bool == true }
    XCTAssertTrue(focused, "The page didn't get focus back")
    XCTAssertFalse(browser.element("clair.extensionAction").exists, "Esc installed the extension")

    // Return installs, and the new extension's button is pinned. A new tab
    // asks, since Chromium holds back a second download from the same page.
    let again = try await browser.open(url("find.html?again"))
    defer { again.close() }
    try await askToInstall(from: again, browser: browser)
    browser.ui.typeKey(.return, modifierFlags: [])
    let installed = browser.element("clair.extensionAction").waitForExistence(timeout: 30)
    XCTAssertTrue(installed, "Return didn't install the extension")
    XCTAssertFalse(browser.dialog.exists, "The dialog stayed open")
  }
}
