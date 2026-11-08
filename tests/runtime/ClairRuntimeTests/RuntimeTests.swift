// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import Foundation
import XCTest

/// The runtime suite (change 1 design D12). tests/runtime/run.sh prepares the
/// packages, test appcasts and web server, and retries a failed test once.
@MainActor
class RuntimeTestCase: XCTestCase {
  var fixture: Fixture!
  var browser: Browser?

  override func setUp() async throws {
    // A failed assertion must not stop an async test: XCTest would raise an
    // exception through the continuation and hang until its time allowance runs
    // out. Steps that later ones depend on use require(), which throws instead.
    fixture = try Fixture.load()
    try Harness.reset()
  }

  override func tearDown() async throws {
    browser?.cleanUp()
    browser = nil
    try Harness.reset()
  }

  func startBrowser(
    defaultDataDirectory: Bool = false, feed: String? = nil, idleSeconds: Int = 3600,
    arguments: [String] = []
  ) async throws -> Browser {
    let browser = try Browser(defaultDataDirectory: defaultDataDirectory)
    self.browser = browser
    try await browser.start(feed: feed, idleSeconds: idleSeconds, arguments: arguments)
    return browser
  }

  var page: String { "\(fixture.baseURL)/pages/index.html" }
  var upToDateFeed: String { "\(fixture.baseURL)/up-to-date/appcast.xml" }
  var updateFeed: String { "\(fixture.baseURL)/update/appcast.xml" }

  /// Keeps Sparkle from checking on its own, so the check under test is the
  /// one the menu item starts.
  func skipAutomaticCheck() throws {
    try Harness.run(
      "/usr/bin/defaults",
      ["write", Harness.bundleID, "SULastCheckTime", "-date", "\(Date.now.description)"])
  }
}

@MainActor
final class AppTests: RuntimeTestCase {
  func testLaunchesAndRendersALocalPage() async throws {
    let browser = try await startBrowser()
    let tab = try await browser.open(page)
    defer { tab.close() }
    let height = try await tab.evaluate(
      "document.getElementById('rendered').getBoundingClientRect().height")
    XCTAssertGreaterThan(height as? Double ?? 0, 0, "The test page has no rendered text")
    let shot = try await tab.send("Page.captureScreenshot")
    XCTAssertFalse(shot["data"] as? String ?? "" == "", "The page has no pixels")
    XCTAssertTrue(browser.ui.windows.firstMatch.waitForExistence(timeout: 30), "Clair shows no window")
  }

  func testApplicationMenuNamesClair() async throws {
    let browser = try await startBrowser(feed: upToDateFeed)
    browser.ui.activate()
    let clair = browser.ui.menuBars.menuBarItems["Clair"]
    try require(clair.waitForExistence(timeout: 30), "There's no Clair menu")
    clair.click()
    for title in ["About Clair", "Hide Clair", "Quit Clair", "Check for Updates…"] {
      XCTAssertTrue(
        browser.clairMenuItem(titled: title).waitForExistence(timeout: 10),
        "The Clair menu has no \(title) item")
    }
    browser.ui.typeKey(.escape, modifierFlags: [])
  }

  func testUsesClairsDataDirectoryAndKeychainItem() async throws {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let support = home.appending(path: "Library/Application Support")
    let browser = try await startBrowser(defaultDataDirectory: true, feed: upToDateFeed)
    // Saving a cookie makes Chromium fetch its storage key.
    let tab = try await browser.open(page)
    defer { tab.close() }
    _ = try await tab.evaluate("document.cookie = 'clair=1; max-age=3600'; document.cookie")

    let profile = support.appending(path: "Clair/Default")
    let hasProfile = await Harness.wait(for: 60) {
      FileManager.default.fileExists(atPath: profile.path)
    }
    XCTAssertTrue(hasProfile, "No profile at \(profile.path)")
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: home.appending(path: "Library/Caches/Clair").path),
      "No ~/Library/Caches/Clair")
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: support.appending(path: "Chromium").path),
      "Clair created a Chromium data directory")

    let hasItem = await Harness.wait(for: 60) {
      try Harness.run("/usr/bin/security", ["find-generic-password", "-s", "Clair Safe Storage"]).status == 0
    }
    XCTAssertTrue(hasItem, "No \"Clair Safe Storage\" keychain item")
    let chromiumItem = try Harness.run(
      "/usr/bin/security", ["find-generic-password", "-s", "Chromium Safe Storage"])
    XCTAssertNotEqual(chromiumItem.status, 0, "A \"Chromium Safe Storage\" keychain item exists")

    // A service name that isn't in the binary can't be read either.
    let framework = browser.appPath.appending(
      path: "Contents/Frameworks/Clair Framework.framework/Clair Framework")
    let binary = try Data(contentsOf: framework, options: .mappedIfSafe)
    XCTAssertNil(
      binary.range(of: Data("Chromium Safe Storage".utf8)),
      "The engine still names the \"Chromium Safe Storage\" keychain item")
    XCTAssertNotNil(binary.range(of: Data("Clair Safe Storage".utf8)))
  }

  func testUserAgentReportsTheEngineVersion() async throws {
    let browser = try await startBrowser()
    let tab = try await browser.open(page)
    defer { tab.close() }
    let userAgent = try await tab.evaluate("navigator.userAgent") as? String ?? ""
    let major = fixture.chromiumVersion.split(separator: ".").first.map(String.init) ?? ""
    XCTAssertTrue(userAgent.contains("Chrome/\(major)."), "Unexpected user agent: \(userAgent)")
    XCTAssertFalse(userAgent.contains(fixture.version), "The user agent names Clair's version: \(userAgent)")
    XCTAssertFalse(userAgent.contains("Clair"), "The user agent names Clair: \(userAgent)")
  }

  func testSettingsHelpPageShowsBothVersions() async throws {
    let browser = try await startBrowser()
    let tab = try await browser.open("about:blank")
    defer { tab.close() }
    // chrome:// URLs work only through a navigation, and Settings pages keep
    // their text in shadow roots.
    try await tab.navigate(to: "chrome://settings/help")
    let script = """
      (() => {
        const walk = (root) => {
          let text = '';
          for (const node of root.querySelectorAll('*')) {
            if (node.shadowRoot) text += walk(node.shadowRoot) + ' ';
            if (!node.children.length) text += node.textContent + ' ';
          }
          return text;
        };
        return walk(document);
      })()
      """
    let expected = [
      "Version \(fixture.version) (\(fixture.build)) (Official Build) (arm64)",
      "Engine: Chromium \(fixture.chromiumVersion) (ungoogled-chromium \(fixture.ungoogledVersion))",
    ]
    var text = ""
    let shown = await Harness.wait(for: 30) {
      text = (try await tab.evaluate(script) as? String ?? "")
        .split(whereSeparator: \.isWhitespace).joined(separator: " ")
      return expected.allSatisfy(text.contains)
    }
    XCTAssertTrue(shown, "chrome://settings/help doesn't show \(expected). It reads: \(text)")
  }

  func testFirstRunPageNamesClairAndItsDataFolder() async throws {
    let browser = try await startBrowser()
    let tab = try await browser.open("about:blank")
    defer { tab.close() }
    try await tab.navigate(to: "chrome://ungoogled-first-run")
    let title = try await tab.evaluate("document.title") as? String
    XCTAssertEqual(title, "Welcome to Clair")
    let text = try await tab.evaluate("document.documentElement.textContent") as? String ?? ""
    XCTAssertTrue(text.contains("~/Library/Application Support/Clair/Dictionaries/"), text)
    XCTAssertFalse(text.contains("Application Support/Chromium"), text)
    XCTAssertFalse(text.contains("first run page"), text)
  }
}

@MainActor
final class UpdateMenuTests: RuntimeTestCase {
  func testCheckReportsUpToDate() async throws {
    try skipAutomaticCheck()
    let browser = try await startBrowser(feed: upToDateFeed)
    try browser.chooseUpdateItem(titled: "Check for Updates…")
    try browser.requireAlert(titled: "Clair is up to date")
    try browser.clickAlertButton("OK")
  }

  func testCheckReportsReadyAndItemChanges() async throws {
    try skipAutomaticCheck()
    let browser = try await startBrowser(feed: updateFeed)
    try browser.chooseUpdateItem(titled: "Check for Updates…")
    let ready = "Clair \(fixture.updateVersion) is ready"
    try browser.requireAlert(titled: ready, within: 180)
    try browser.clickAlertButton("Later")
    XCTAssertTrue(
      browser.updateItemExists(titled: "Update Available…", within: 30),
      "The update item doesn't read \"Update Available…\"")
    try browser.chooseUpdateItem(titled: "Update Available…")
    try browser.requireAlert(titled: ready)
    try browser.clickAlertButton("Later")
  }

  /// Restart and Update goes through ClairHost's relaunch: the same windows and
  /// tabs come back, in the new version.
  func testRelaunchRestoresWindowsAndTabs() async throws {
    try skipAutomaticCheck()
    let browser = try await startBrowser(feed: updateFeed)
    let first = try await browser.open("\(page)?first")
    let second = try await browser.open("\(page)?second")
    let third = try await browser.open("\(page)?third", newWindow: true)
    defer {
      first.close()
      second.close()
      third.close()
    }
    let windowsBefore = try await browser.windowCount()
    try require(windowsBefore >= 2, "The second window didn't open")
    let before = try await browser.pageTargets().map(\.url).filter { $0.contains("?") }

    try browser.chooseUpdateItem(titled: "Check for Updates…")
    let ready = "Clair \(fixture.updateVersion) is ready"
    try browser.requireAlert(titled: ready, within: 180)
    let oldProcess = try browser.runningProcessID()
    let beside = try browser.itemsBesideApp()
    try browser.clickAlertButton("Restart and Update")

    try await waitForRelaunch(of: browser, from: oldProcess)
    XCTAssertEqual(browser.installedVersion, fixture.updateVersion, "The update didn't install")
    assertUpdateLeftNothingBeside(browser, before: beside)
    var after: [String] = []
    let restored = await Harness.wait(for: 60) {
      after = try await browser.pageTargets().map(\.url).filter { $0.contains("?") }
      return Set(after) == Set(before)
    }
    XCTAssertTrue(restored, "Tabs before the relaunch: \(before). After: \(after)")
    let windowsAfter = try await browser.windowCount()
    XCTAssertEqual(windowsAfter, windowsBefore, "The windows didn't come back")
  }
}

extension RuntimeTestCase {
  /// Waits for a new Clair process that answers over DevTools.
  func waitForRelaunch(of browser: Browser, from oldProcess: Int32?, within seconds: TimeInterval = 180) async throws {
    let relaunched = await Harness.wait(for: seconds) {
      guard let process = try browser.runningProcessID(), process != oldProcess else {
        return false
      }
      return try await !browser.pageTargets().isEmpty
    }
    try require(relaunched, "Clair didn't relaunch within \(Int(seconds)) seconds")
  }

  /// Checks that the update replaced only Clair.app: nothing from its DMG, such
  /// as the window's layout files or the Applications link, landed beside it.
  func assertUpdateLeftNothingBeside(_ browser: Browser, before: Set<String>) {
    do {
      let added = try browser.itemsBesideApp().subtracting(before)
      XCTAssertEqual(added.sorted(), [], "The update left these beside Clair.app")
    } catch {
      XCTFail("Couldn't list what's beside Clair.app: \(error)")
    }
  }
}

/// The waiting update installs after an idle period, unless something would be
/// interrupted (D4). Nothing here touches the mouse or keyboard except to open
/// and close the incognito window, since input restarts the idle clock.
@MainActor
final class IdleInstallTests: RuntimeTestCase {
  private let idleSeconds = 20

  override func setUp() async throws {
    // These wait out the idle timer and a relaunch, about two minutes, past
    // run.sh's default allowance.
    executionTimeAllowance = 300
    try await super.setUp()
  }

  /// Starts Clair and waits until a background check has an update waiting.
  private func startWithWaitingUpdate() async throws -> Browser {
    let browser = try await startBrowser(feed: updateFeed, idleSeconds: idleSeconds)
    try require(
      browser.updateItemExists(titled: "Update Available…", within: 180),
      "No update was waiting after three minutes")
    return browser
  }

  /// Checks that Clair stays as it is for three idle periods.
  private func assertStaysRunning(_ browser: Browser, reason: String) async throws {
    let process = try browser.runningProcessID()
    try await Task.sleep(for: .seconds(idleSeconds * 3))
    // A relaunch here makes the rest of the test pointless, so this stops it.
    try require(try browser.runningProcessID() == process, "Clair relaunched despite \(reason)")
    try require(browser.installedVersion == fixture.version, "The update installed despite \(reason)")
  }

  /// Checks that Clair installs the update once nothing stands in the way.
  private func assertInstalls(_ browser: Browser, from process: Int32?) async throws {
    let beside = try browser.itemsBesideApp()
    try await waitForRelaunch(of: browser, from: process)
    XCTAssertEqual(browser.installedVersion, fixture.updateVersion, "The update didn't install")
    assertUpdateLeftNothingBeside(browser, before: beside)
  }

  func testInstallsAndRelaunchesWhenIdle() async throws {
    let browser = try await startWithWaitingUpdate()
    let tab = try await browser.open("\(page)?idle")
    tab.close()
    let process = try browser.runningProcessID()
    try await assertInstalls(browser, from: process)
    let restored = await Harness.wait(for: 60) {
      try await browser.pageTargets().contains { $0.url.hasSuffix("?idle") }
    }
    XCTAssertTrue(restored, "The tab didn't come back after the idle install")
  }

  func testDownloadInProgressPreventsIdleInstall() async throws {
    let browser = try await startWithWaitingUpdate()
    // ungoogled-chromium asks where to save every download, and a save panel
    // would leave the download waiting. This setting lasts as long as the session.
    let folder = browser.workDirectory.appending(path: "downloads")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let session = try await browser.browserSession()
    defer { session.close() }
    try await session.send(
      "Browser.setDownloadBehavior", ["behavior": "allow", "downloadPath": folder.path])

    let tab = try await browser.open(page)
    defer { tab.close() }
    _ = try await tab.evaluate("location.href = '/slow-download'; 1")
    let started = await Harness.wait(for: 30) { !folder.contents.isEmpty }
    try require(started, "The download didn't start")
    try await assertStaysRunning(browser, reason: "a download in progress")

    let process = try browser.runningProcessID()
    let finish = URL(string: "\(fixture.baseURL)/slow-download/finish")!
    _ = try await URLSession.shared.data(from: finish)
    try await assertInstalls(browser, from: process)
  }

  func testIncognitoWindowPreventsIdleInstall() async throws {
    let browser = try await startWithWaitingUpdate()
    browser.ui.activate()
    try require(browser.ui.windows.firstMatch.waitForExistence(timeout: 30), "Clair shows no window")
    browser.ui.typeKey("n", modifierFlags: [.command, .shift])
    let opened = await Harness.wait(for: 30) { browser.ui.windows.count >= 2 }
    try require(opened, "No incognito window opened")
    try await assertStaysRunning(browser, reason: "an incognito window")

    let process = try browser.runningProcessID()
    browser.ui.typeKey("w", modifierFlags: [.command, .shift])
    try await assertInstalls(browser, from: process)
  }

  func testAudibleTabPreventsIdleInstall() async throws {
    let browser = try await startWithWaitingUpdate()
    let tab = try await browser.open("\(fixture.baseURL)/pages/audio.html")
    defer { tab.close() }
    let state = try await tab.evaluate("startTone()") as? String
    try require(state == "running", "The test tone didn't start")
    try await assertStaysRunning(browser, reason: "an audible tab")

    let process = try browser.runningProcessID()
    _ = try await tab.evaluate("stopTone()")
    try await assertInstalls(browser, from: process)
  }
}

extension URL {
  fileprivate var contents: [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
  }
}
