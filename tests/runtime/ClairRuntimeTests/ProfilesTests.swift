// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import Foundation
import XCTest

extension Browser {
  /// Opens Settings on its Profiles page.
  func openProfilesPage() throws {
    ui.typeKey(",", modifierFlags: .command)
    let page = ui.toolbars.buttons["Profiles"]
    try require(page.waitForExistence(timeout: 15), "Settings has no Profiles page")
    page.click()
    try require(ui.windows["Profiles"].waitForExistence(timeout: 10), "The Profiles page didn't open")
  }

  /// The Profiles list's rows, in order, as "name" or "name, 2 Spaces".
  var profileRows: [XCUIElement] {
    ui.windows["Profiles"].descendants(matching: .any).matching(identifier: "clair.profileRow").allElementsBoundByIndex
  }

  func profileRow(_ name: String) -> XCUIElement? {
    profileRows.first { $0.label.hasPrefix(name) }
  }

  func settingsElement(_ identifier: String) -> XCUIElement {
    ui.windows["Profiles"].descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  /// A part of the dialog on any window (DialogTests' `dialog`).
  func dialogElement(_ identifier: String) -> XCUIElement {
    dialog.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  /// The menu item titled `title` in the menu that's open, not one of the
  /// same title in a closed menu, such as Spaces › Change Profile's.
  func openMenuItem(_ title: String) async throws -> XCUIElement {
    var found: XCUIElement?
    let shown = await Harness.wait(for: 5) {
      found = self.ui.menuItems.matching(NSPredicate(format: "title == %@", title)).allElementsBoundByIndex
        .first(where: \.isHittable)
      return found != nil
    }
    try require(shown, "No open menu has \(title)")
    return found!
  }

  /// Types `name` into the open dialog's field and presses its default
  /// button.
  func answerDialog(field: String, with name: String) throws {
    let input = dialogElement(field)
    try require(input.waitForExistence(timeout: 10), "The dialog has no field \(field)")
    input.click()
    input.typeKey("a", modifierFlags: .command)
    input.typeText(name)
    dialogElement("clair.dialogDefault").click()
  }

  /// Adds a profile from Settings › Profiles, which must be open.
  func addProfile(_ name: String) async throws {
    settingsElement("clair.profilesAdd").click()
    try require(dialog.waitForExistence(timeout: 10), "Add didn't ask for a name")
    let create = dialogElement("clair.dialogDefault")
    XCTAssertFalse(create.isEnabled, "Create Profile is on before a name is typed")
    try answerDialog(field: "clair.newProfileName", with: name)
    let listed = await Harness.wait(for: 30) { self.profileRow(name) != nil }
    try require(listed, "\(name) isn't in the Profiles list")
  }

  /// Creates a Space from the Spaces menu on `profile`, chosen in the form's
  /// popup, and waits for the window to show it.
  func createSpace(_ name: String, profile: String? = nil) async throws {
    try chooseSpacesItem("New Space…")
    let field = element("clair.newSpaceName")
    try require(field.waitForExistence(timeout: 10), "The New Space form didn't open")
    field.click()
    field.typeText(name)
    if let profile {
      let popup = element("clair.profilePopup")
      try require(popup.waitForExistence(timeout: 5), "The form has no profile popup")
      popup.click()
      try await openMenuItem(profile).click()
    }
    element("clair.createSpace").click()
    let shown = await waitForSpace(name, seconds: 30)
    try require(shown, "The window doesn't show the new Space \(name): \(spaceName)")
    ui.typeKey(.escape, modifierFlags: [])
  }

  /// Chooses `profile` in the Space header's Set Profile menu.
  func setProfileFromHeader(_ profile: String) async throws {
    element("clair.spaceHeader").rightClick()
    let menu = try await openMenuItem("Set Profile")
    menu.hover()
    try await openMenuItem(profile).click()
  }

  /// Whether `tab`'s page sees the cookie the cookie page sets.
  func hasCookie(_ tab: DevToolsSession) async throws -> Bool {
    try await tab.evaluate("window.hasCookie()") as? Bool ?? false
  }

  /// The native windows on screen.
  var visibleNativeWindowCount: Int {
    ui.windows.containing(.any, identifier: "clair.sidebar").count
  }
}

/// Profiles (add-profiles task 3.9), driven through Settings, the Space
/// menus and the New Space form, with the counter page, whose state shows
/// that a tab kept its page, and the cookie page, whose cookie shows which
/// profile a page uses.
@MainActor
final class ProfilesTests: NativeWindowTestCase {
  /// Chromium's name for the first profile.
  static let defaultProfile = "Your Clair"

  func counter(_ name: String) -> String { url("counter.html?\(name)") }
  func cookie(_ name: String) -> String { url("cookie.html?\(name)") }

  /// Starts with Home on the default profile, a "Work" profile and a Space
  /// "Work" using it, shown.
  func startWithWorkProfile() async throws -> (Browser, DevToolsSession) {
    try Harness.setRestoreWindows(false)
    let (browser, tab) = try await startWithPage("counter.html?home")
    try browser.openProfilesPage()
    try await browser.addProfile("Work")
    browser.ui.windows["Profiles"].typeKey("w", modifierFlags: .command)
    browser.nativeWindow.click()
    try await browser.createSpace("Work", profile: "Work")
    return (browser, tab)
  }

  func testProfilesInSettingsAndTheMenuBar() async throws {
    try Harness.setRestoreWindows(false)
    let (browser, tab) = try await startWithPage("counter.html?a")
    defer { tab.close() }
    // The menu bar has no Profiles menu, and the Clair menu no "Warn Before
    // Quitting".
    XCTAssertFalse(browser.ui.menuBars.menuBarItems["Profiles"].exists, "The menu bar has a Profiles menu")
    browser.ui.menuBars.menuBarItems["Clair"].click()
    XCTAssertFalse(
      browser.ui.menuBars.menuItems.matching(NSPredicate(format: "title BEGINSWITH %@", "Warn Before Quitting"))
        .firstMatch.exists,
      "The Clair menu has Warn Before Quitting")
    browser.ui.typeKey(.escape, modifierFlags: [])

    try browser.openProfilesPage()
    XCTAssertEqual(browser.profileRows.count, 1, "There isn't one profile at first")
    // The only profile, which Home uses, can't be removed.
    XCTAssertFalse(browser.settingsElement("clair.profilesRemove").isEnabled, "Remove is on for the last profile")

    try await browser.addProfile("Client")
    XCTAssertTrue(browser.profileRow("Client")?.isSelected == true, "The new profile isn't selected")
    XCTAssertTrue(browser.settingsElement("clair.profilesRemove").isEnabled, "Remove is off for a profile no Space uses")
    XCTAssertTrue(
      browser.settingsElement("clair.profileLinksNote").exists, "The link rows aren't explained for a profile without a Space")

    // Rename.
    browser.settingsElement("clair.profilesRename").click()
    try require(browser.dialog.waitForExistence(timeout: 10), "Rename didn't open its dialog")
    try browser.answerDialog(field: "clair.renameProfileName", with: "Office")
    let renamed = await Harness.wait(for: 15) { browser.profileRow("Office") != nil }
    XCTAssertTrue(renamed, "The profile wasn't renamed")

    // The default profile, which Home uses, can't be removed.
    browser.profileRows.first?.click()
    XCTAssertFalse(browser.settingsElement("clair.profilesRemove").isEnabled, "Remove is on for a profile a Space uses")

    // Remove, after typing the name.
    let folders = try FileManager.default.contentsOfDirectory(atPath: browser.dataDirectory.path)
    browser.profileRow("Office")?.click()
    browser.settingsElement("clair.profilesRemove").click()
    try require(browser.dialog.waitForExistence(timeout: 10), "Remove didn't ask")
    let field = browser.dialogElement("clair.deleteProfileName")
    field.click()
    field.typeText("office 2")
    XCTAssertFalse(browser.dialogElement("clair.dialogDefault").isEnabled, "Delete is on for a wrong name")
    field.typeKey("a", modifierFlags: .command)
    field.typeText("Office")
    XCTAssertTrue(browser.dialogElement("clair.dialogDefault").isEnabled, "Delete is off for the name")
    browser.dialogElement("clair.dialogDefault").click()
    let removed = await Harness.wait(for: 30) { browser.profileRow("Office") == nil }
    XCTAssertTrue(removed, "The profile wasn't removed")
    let created = folders.filter { $0.hasPrefix("Profile ") }
    let gone = await Harness.wait(for: 60) {
      let now = try FileManager.default.contentsOfDirectory(atPath: browser.dataDirectory.path)
      return created.allSatisfy { !now.contains($0) }
    }
    XCTAssertTrue(gone, "The removed profile's data folder is still there")
  }

  func testNoProfilePickerWithTwoProfiles() async throws {
    let (browser, tab) = try await startWithWorkProfile()
    tab.close()
    try await Task.sleep(for: .seconds(3))
    try await browser.quit()
    try await browser.start()
    try require(browser.nativeWindow.waitForExistence(timeout: 60), "No browser window opened with two profiles")
    let picker = try await browser.pageTargets().contains { $0.url.hasPrefix("chrome://profile-picker") }
    XCTAssertFalse(picker, "Chromium's profile picker showed at launch")
  }

  func testIsolationAndSwitching() async throws {
    let (browser, home) = try await startWithWorkProfile()
    defer { home.close() }
    let frame = browser.nativeWindow.frame
    let sidebarWidth = browser.sidebar.frame.width

    // Home sets a cookie.
    browser.ui.typeKey("1", modifierFlags: .control)
    _ = await browser.waitForSpace("Home")
    let setter = try await browser.open(cookie("set"))
    defer { setter.close() }
    let set = await Harness.wait(for: 15) { try await browser.hasCookie(setter) }
    try require(set, "The cookie page didn't set its cookie")

    // Work, of another profile, doesn't see it, in the same window.
    browser.ui.typeKey("2", modifierFlags: .control)
    let work = await browser.waitForSpace("Work")
    try require(work, "Ctrl+2 didn't show Work")
    XCTAssertEqual(browser.visibleNativeWindowCount, 1, "Switching profile showed a second window")
    XCTAssertEqual(browser.nativeWindow.frame, frame, "Switching profile changed the window's frame")
    XCTAssertEqual(browser.sidebar.frame.width, sidebarWidth, "Switching profile changed the sidebar's width")
    let other = try await browser.open(cookie("work"))
    defer { other.close() }
    let leaked = try await browser.hasCookie(other)
    XCTAssertFalse(leaked, "A Space of another profile sees the cookie")

    // A third Space on the default profile sees it.
    try await browser.createSpace("Errands", profile: Self.defaultProfile)
    let same = try await browser.open(cookie("errands"))
    defer { same.close() }
    let seen = await Harness.wait(for: 15) { try await browser.hasCookie(same) }
    XCTAssertTrue(seen, "Another Space of the same profile doesn't see the cookie")
    XCTAssertEqual(browser.visibleNativeWindowCount, 1, "Switching back showed a second window")
  }

  func testSettingASpacesProfile() async throws {
    let (browser, home) = try await startWithWorkProfile()
    defer { home.close() }
    // Work shows a new tab page, so it asks; Cancel changes nothing.
    try await browser.setProfileFromHeader(Self.defaultProfile)
    try require(browser.dialog.waitForExistence(timeout: 10), "A Space with a tab didn't ask")
    browser.dialogElement("clair.dialogCancel").click()
    XCTAssertEqual(browser.tabTitles.count, 1, "Cancel changed Work's tabs")

    // Home, with tabs, one of which asks before leaving: confirming reopens
    // them in Work, in order, without the page asking.
    browser.ui.typeKey("1", modifierFlags: .control)
    _ = await browser.waitForSpace("Home")
    let asks = try await browser.open(url("beforeunload.html"))
    // The page asks only after a click.
    _ = try await asks.evaluate("document.body.id = 'body'; 1")
    try await asks.click("body")
    let checker = try await browser.open(cookie("check"))
    let before = browser.tabTitles
    asks.close()
    checker.close()
    try await browser.setProfileFromHeader("Work")
    try require(browser.dialog.waitForExistence(timeout: 10), "A Space with tabs didn't ask")
    browser.dialogElement("clair.dialogDefault").click()
    let reopened = await browser.waitForTabs(30) { $0 == before }
    XCTAssertTrue(reopened, "Home doesn't list the same tabs in order: \(browser.tabTitles) vs \(before)")
    XCTAssertFalse(browser.dialog.exists, "A page asked before leaving")
    XCTAssertEqual(browser.spaceName, "Home", "The window left Home")
    let moved = try await browser.target(endingWith: "?check")
    try require(moved != nil, "The cookie page didn't come back")
    let session = try await browser.session(onTarget: moved!.id)
    defer { session.close() }
    let counter = try await browser.target(endingWith: "?home")
    XCTAssertNotNil(counter, "The counter page didn't come back")
  }

  func testManageSpacesStaysOpenWhenTheShownSpaceChangesProfile() async throws {
    let (browser, home) = try await startWithWorkProfile()
    defer { home.close() }
    browser.ui.typeKey("1", modifierFlags: .control)
    _ = await browser.waitForSpace("Home")
    try browser.chooseSpacesItem("Manage Spaces…")
    try require(browser.dialog.waitForExistence(timeout: 10), "Manage Spaces didn't open")
    let popup = browser.dialogElement("clair.profilePopup")
    popup.click()
    try await browser.openMenuItem("Work").click()
    try require(
      browser.dialogElement("clair.dialogDefault").waitForExistence(timeout: 10), "Changing Home's profile didn't ask")
    browser.dialogElement("clair.dialogDefault").click()
    let back = await Harness.wait(for: 15) { browser.dialog.exists && browser.dialogElement("clair.manageSpacesList").exists }
    XCTAssertTrue(back, "Manage Spaces didn't stay open")

    // A Space Manage Spaces adds has no tab: its profile changes at once.
    browser.dialogElement("clair.manageSpacesAdd").click()
    let added = await Harness.wait(for: 10) {
      browser.dialog.descendants(matching: .any).matching(identifier: "clair.manageSpacesRow").count == 3
    }
    try require(added, "Add didn't add a Space")
    browser.dialogElement("clair.profilePopup").click()
    try await browser.openMenuItem(Self.defaultProfile).click()
    let asked = browser.dialogElement("clair.manageSpacesList").waitForExistence(timeout: 3)
    XCTAssertTrue(asked, "Changing an empty Space's profile asked")
    browser.ui.typeKey(.escape, modifierFlags: [])
  }

  func testMoveToSpaceAcrossProfiles() async throws {
    let (browser, home) = try await startWithWorkProfile()
    defer { home.close() }
    browser.ui.typeKey("1", modifierFlags: .control)
    _ = await browser.waitForSpace("Home")
    let moving = try await browser.open(counter("moving"))
    let staying = try await browser.open(counter("staying"))
    defer {
      moving.close()
      staying.close()
    }
    _ = try await moving.evaluate("window.counter = 5; 1")

    // Another tab: the window stays, and a notice says where it went.
    browser.tabRow("Counter staying")?.click()
    _ = await browser.waitForActiveRow("Counter staying")
    try await moveRow("Counter home", to: "Work", in: browser)
    let notice = browser.ui.staticTexts["Tab was moved to Work"].waitForExistence(timeout: 10)
    XCTAssertTrue(notice, "Moving another tab showed no notice")
    XCTAssertEqual(browser.spaceName, "Home", "Moving another tab left Home")

    // The active tab: the window follows it, reopened at the top of Work.
    browser.tabRow("Counter moving")?.click()
    _ = await browser.waitForActiveRow("Counter moving")
    try await moveRow("Counter moving", to: "Work", in: browser)
    let followed = await browser.waitForSpace("Work", seconds: 30)
    XCTAssertTrue(followed, "Moving the active tab didn't show Work")
    let active = await browser.waitForActiveRow("Counter moving")
    XCTAssertTrue(active, "The moved tab isn't active in Work: \(browser.activeRow ?? "none")")
    XCTAssertEqual(browser.tabTitles.first, "Counter moving", "The moved tab isn't at the top of Work")
    let target = try await browser.target(endingWith: "?moving")
    try require(target != nil, "The moved tab isn't open")
    let reopened = try await browser.session(onTarget: target!.id)
    defer { reopened.close() }
    let count = try await reopened.evaluate("window.counter") as? Double
    XCTAssertEqual(count, 0, "The tab kept its page across profiles")
  }

  func moveRow(_ title: String, to space: String, in browser: Browser) async throws {
    browser.tabRow(title)?.rightClick()
    let move = try await browser.openMenuItem("Move to Space")
    move.hover()
    try await browser.openMenuItem(space).click()
  }

  func testTheEmptiedSpace() async throws {
    let (browser, home) = try await startWithWorkProfile()
    defer { home.close() }
    // Work's only row is a new tab page: closing it closes the window.
    let windowsBefore = try await browser.windowCount()
    browser.ui.typeKey("w", modifierFlags: .command)
    let closed = await Harness.wait(for: 30) { try await browser.windowCount() < windowsBefore }
    XCTAssertTrue(closed, "Closing an emptied Space's new tab page didn't close the window")
  }

  func testRelaunchWithRestoringOff() async throws {
    let (browser, home) = try await startWithWorkProfile()
    let work = try await browser.open(counter("work"))
    // A second window, last active, on Home.
    let other = try await browser.open(counter("other"), newWindow: true)
    _ = await Harness.wait(for: 30) { browser.visibleNativeWindowCount == 2 }
    browser.ui.typeKey("1", modifierFlags: .control)
    try await Task.sleep(for: .seconds(3))
    [home, work, other].forEach { $0.close() }
    try await browser.quit()
    try Harness.setRestoreWindows(false)
    try await browser.start()
    try require(browser.nativeWindow.waitForExistence(timeout: 60), "Clair didn't come back")
    let one = await Harness.wait(for: 30) { browser.visibleNativeWindowCount == 1 }
    XCTAssertTrue(one, "Clair didn't come back as one window: \(browser.visibleNativeWindowCount)")
    let onHome = await browser.waitForSpace("Home", seconds: 30)
    XCTAssertTrue(onHome, "The window doesn't show the Space last shown: \(browser.spaceName)")
    let listed = await browser.waitForTabs(30) { $0.contains("Counter home") && $0.contains("Counter other") }
    XCTAssertTrue(listed, "Home doesn't list its tabs: \(browser.tabTitles)")
    XCTAssertTrue(
      browser.element("clair.commandBarField").waitForExistence(timeout: 10), "The window didn't open the command bar")
    browser.ui.typeKey(.escape, modifierFlags: [])
    browser.ui.typeKey("2", modifierFlags: .control)
    let workBack = await browser.waitForTabs(30) { $0.contains("Counter work") }
    XCTAssertTrue(workBack, "Work doesn't list its tab: \(browser.tabTitles)")

    // A second launch lists one new tab page, not two.
    browser.ui.typeKey("1", modifierFlags: .control)
    try await Task.sleep(for: .seconds(3))
    try await browser.quit()
    try await browser.start()
    try require(browser.nativeWindow.waitForExistence(timeout: 60), "Clair didn't come back again")
    _ = await browser.waitForSpace("Home", seconds: 30)
    let newTabPages = await Harness.wait(for: 30) {
      try await browser.pageTargets().filter { $0.url.hasPrefix("chrome://newtab") }.count == 1
    }
    XCTAssertTrue(newTabPages, "New tab pages left open at quit came back")
  }

  func testRelaunchWithRestoringOn() async throws {
    let (browser, home) = try await startWithWorkProfile()
    let work = try await browser.open(counter("work"))
    browser.tabRow("Counter work")?.click()
    _ = await browser.waitForActiveRow("Counter work")
    let other = try await browser.open(counter("other"), newWindow: true)
    _ = await Harness.wait(for: 30) { browser.visibleNativeWindowCount == 2 }
    try await Task.sleep(for: .seconds(3))
    [home, work, other].forEach { $0.close() }
    try await browser.quit()
    try Harness.setRestoreWindows(true)
    try await browser.start()
    let two = await Harness.wait(for: 60) { browser.visibleNativeWindowCount == 2 }
    XCTAssertTrue(two, "Both windows didn't come back: \(browser.visibleNativeWindowCount)")
    let windows = browser.nativeWindows
    let rows = windows.map { $0.activeRow ?? "" }.sorted()
    XCTAssertEqual(rows, ["Counter other", "Counter work"], "The windows don't show their tabs: \(rows)")
  }

  func testDownloadSettingsAndLinksPerProfile() async throws {
    let (browser, home) = try await startWithWorkProfile()
    defer { home.close() }
    try browser.openProfilesPage()
    browser.profileRow("Work")?.click()
    let popup = browser.settingsElement("clair.downloadLocation")
    try require(popup.waitForExistence(timeout: 10), "The page has no Download location")
    // ungoogled-chromium asks where to save by default: Work saves to its
    // folder instead, and the default profile goes on asking.
    popup.click()
    try await browser.openMenuItem("Downloads").click()
    try await Task.sleep(for: .seconds(1))

    // Search Engine opens Chromium's page in a Space of Work.
    let links = browser.ui.windows["Profiles"].descendants(matching: .any).matching(identifier: "clair.profileLink")
      .allElementsBoundByIndex
    try require(links.count == 4, "The page doesn't have four link rows")
    links[0].click()
    let opened = await browser.waitForTarget("chrome://settings/search", seconds: 30)
    XCTAssertTrue(opened, "Search Engine didn't open chrome://settings/search")
    let shown = await browser.waitForSpace("Work", seconds: 15)
    XCTAssertTrue(shown, "The settings page isn't in a Space of Work: \(browser.spaceName)")
    XCTAssertFalse(browser.ui.windows["Profiles"].exists, "Settings didn't close")

    // Asking applies to Work only.
    let searchTarget = try await browser.target(endingWith: "/search")
    try require(searchTarget != nil, "The settings tab isn't open")
    let workSettings = try await browser.session(onTarget: searchTarget!.id)
    defer { workSettings.close() }
    let asks = try await workSettings.evaluate(
      "(async () => (await new Promise(r => chrome.settingsPrivate.getPref('download.prompt_for_download', r))).value)()")
    XCTAssertEqual(asks as? Bool, false, "Choosing the folder didn't apply to Work")
    browser.ui.typeKey("1", modifierFlags: .control)
    _ = await browser.waitForSpace("Home")
    let homeSettings = try await browser.open("chrome://settings/downloads")
    defer { homeSettings.close() }
    try await Task.sleep(for: .seconds(2))
    let homeAsks = try await homeSettings.evaluate(
      "(async () => (await new Promise(r => chrome.settingsPrivate.getPref('download.prompt_for_download', r))).value)()")
    XCTAssertEqual(homeAsks as? Bool, true, "Work's folder applied to the default profile")
  }

  func testWarnBeforeQuittingOff() async throws {
    try Harness.setRestoreWindows(false)
    let (browser, tab) = try await startWithPage("counter.html?a")
    tab.close()
    browser.ui.typeKey(",", modifierFlags: .command)
    let advanced = browser.ui.toolbars.buttons["Advanced"]
    try require(advanced.waitForExistence(timeout: 15), "Settings has no Advanced page")
    advanced.click()
    let warn = browser.ui.switches["clair.warnBeforeQuittingToggle"]
    try require(warn.waitForExistence(timeout: 10), "The Advanced page has no Warn before quitting toggle")
    XCTAssertEqual(warn.value as? Int, 1, "Warn before quitting isn't on by default")
    let restore = browser.ui.switches["clair.restoreWindowsToggle"]
    XCTAssertEqual(restore.value as? Int, 0, "Restoring windows isn't off by default")
    warn.click()
    browser.nativeWindow.click()
    browser.ui.typeKey("q", modifierFlags: .command)
    let quit = await Harness.wait(for: 15) { try browser.runningProcessID() == nil }
    XCTAssertTrue(quit, "Cmd+Q didn't quit at once with the warning off")
  }
}
