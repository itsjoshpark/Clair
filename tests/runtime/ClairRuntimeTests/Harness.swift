// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import Foundation
import XCTest

/// What tests/runtime/run.sh prepared: `CLAIR_RUNTIME_DIR` holds Clair.app and
/// config.json.
struct Fixture: Decodable {
  let version: String
  let build: String
  let updateVersion: String
  let updateBuild: String
  let chromiumVersion: String
  let ungoogledVersion: String
  let baseURL: String

  static let directory: URL = {
    guard let path = ProcessInfo.processInfo.environment["CLAIR_RUNTIME_DIR"] else {
      fatalError("CLAIR_RUNTIME_DIR isn't set; run tests/runtime/run.sh")
    }
    return URL(fileURLWithPath: path)
  }()

  static func load() throws -> Fixture {
    let data = try Data(contentsOf: directory.appending(path: "config.json"))
    return try JSONDecoder().decode(Fixture.self, from: data)
  }
}

@MainActor
enum Harness {
  static let bundleID = "dev.joshuapark.Clair"

  /// Runs a tool to the end and returns its status and output.
  @discardableResult
  static func run(_ tool: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
  }

  /// Waits for a condition, checking every half second. Returns whether it held.
  static func wait(
    for seconds: TimeInterval, until condition: () async throws -> Bool
  ) async -> Bool {
    let deadline = Date.now.addingTimeInterval(seconds)
    while Date.now < deadline {
      if (try? await condition()) == true {
        return true
      }
      try? await Task.sleep(for: .milliseconds(500))
    }
    return (try? await condition()) == true
  }

  /// Clears what an earlier test left behind: running copies of Clair and
  /// Autoupdate, Sparkle's state, and Clair's data. run.sh refuses to run
  /// anywhere this could reach someone's real data.
  static func reset() throws {
    for name in ["Clair", "Autoupdate", "Updater"] {
      try run("/usr/bin/pkill", ["-9", "-x", name])
    }
    try run("/usr/bin/defaults", ["delete", bundleID])
    let home = FileManager.default.homeDirectoryForCurrentUser
    for path in [
      "Library/Application Support/Clair",
      "Library/Caches/Clair",
      "Library/Caches/\(bundleID)",
      "Library/HTTPStorages/\(bundleID)",
      "Library/Preferences/\(bundleID).plist",
    ] {
      try? FileManager.default.removeItem(at: home.appending(path: path))
    }
    let downloads = home.appending(path: "Downloads")
    for file in (try? FileManager.default.contentsOfDirectory(atPath: downloads.path)) ?? []
    where file.hasSuffix(".crdownload") || file.hasPrefix("slow") {
      try? FileManager.default.removeItem(at: downloads.appending(path: file))
    }
    try run("/usr/bin/security", ["delete-generic-password", "-s", "Clair Safe Storage"])
  }
}

/// A private copy of the package, started by path, so an update can replace it
/// and a test can't affect the next one.
///
/// It's started directly rather than with XCUIApplication.launch(), which adds
/// `-ApplePersistenceIgnoreState YES`: Chromium would open "YES" as a URL. The
/// accessibility queries find it through its bundle identifier, which keeps
/// working after a relaunch.
@MainActor
final class Browser {
  let workDirectory: URL
  let userDataDirectory: URL?
  let appPath: URL
  let ui = XCUIApplication(bundleIdentifier: Harness.bundleID)
  private var process: Process?

  /// With `defaultDataDirectory`, Clair runs with its real data directory and
  /// keychain. Otherwise it gets a throwaway directory and a mock keychain.
  init(defaultDataDirectory: Bool = false) throws {
    workDirectory = FileManager.default.temporaryDirectory.appending(
      path: "clair-runtime-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    appPath = workDirectory.appending(path: "Clair.app")
    // A clone on APFS, so it's instant.
    try FileManager.default.copyItem(at: Fixture.directory.appending(path: "Clair.app"), to: appPath)
    userDataDirectory = defaultDataDirectory ? nil : workDirectory.appending(path: "data")
    try Harness.run(
      "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
      ["-f", appPath.path])
  }

  /// The directory Clair writes DevToolsActivePort into.
  var dataDirectory: URL {
    userDataDirectory
      ?? FileManager.default.homeDirectoryForCurrentUser.appending(
        path: "Library/Application Support/Clair")
  }

  /// Starts Clair and waits until it answers over DevTools.
  func start(
    feed: String? = nil, idleSeconds: Int = 3600, arguments: [String] = []
  ) async throws {
    var launchArguments = [
      "--no-first-run", "--no-default-browser-check", "--remote-debugging-port=0",
      "--autoplay-policy=no-user-gesture-required", "--enable-logging=stderr",
    ]
    if let userDataDirectory {
      launchArguments += ["--user-data-dir=\(userDataDirectory.path)", "--use-mock-keychain"]
    }
    let process = Process()
    process.executableURL = appPath.appending(path: "Contents/MacOS/Clair")
    process.arguments = launchArguments + arguments
    var environment = ProcessInfo.processInfo.environment.filter {
      ["HOME", "PATH", "TMPDIR", "USER", "LOGNAME"].contains($0.key)
    }
    environment["CLAIR_TEST_UPDATE_IDLE_SECONDS"] = String(idleSeconds)
    if let feed {
      environment["CLAIR_TEST_FEED_URL"] = feed
    }
    process.environment = environment
    // run.sh uploads these logs when the suite fails.
    let logs = Fixture.directory.appending(path: "logs")
    try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    let log = logs.appending(path: "clair-\(UUID().uuidString).log")
    FileManager.default.createFile(atPath: log.path, contents: nil)
    let logHandle = try FileHandle(forWritingTo: log)
    process.standardOutput = logHandle
    process.standardError = logHandle
    try process.run()
    self.process = process
    let answered = await Harness.wait(for: 120) {
      _ = try await self.devToolsPort()
      return try await !self.pageTargets().isEmpty
    }
    XCTAssertTrue(answered, "Clair didn't answer over DevTools within two minutes")
  }

  func stop() {
    process?.terminate()
    process = nil
  }

  func cleanUp() {
    stop()
    try? FileManager.default.removeItem(at: workDirectory)
  }

  /// The installed package's version, as Sparkle would have left it.
  var installedVersion: String? {
    let plist = NSDictionary(contentsOf: appPath.appending(path: "Contents/Info.plist"))
    return plist?["CFBundleShortVersionString"] as? String
  }

  /// The ID of the running Clair process, wherever it was started from.
  func runningProcessID() throws -> Int32? {
    let result = try Harness.run("/usr/bin/pgrep", ["-x", "Clair"])
    return result.output.split(separator: "\n").first.flatMap { Int32($0) }
  }

  // MARK: - DevTools

  func devToolsPort() async throws -> Int {
    let file = dataDirectory.appending(path: "DevToolsActivePort")
    let contents = try String(contentsOf: file, encoding: .utf8)
    guard let line = contents.split(separator: "\n").first, let port = Int(line) else {
      throw HarnessError("No port in \(file.path)")
    }
    return port
  }

  struct Target: Decodable {
    let id: String
    let type: String
    let url: String
    let webSocketDebuggerUrl: String?
  }

  /// The open tabs, apart from DevTools' own targets.
  func pageTargets() async throws -> [Target] {
    let port = try await devToolsPort()
    let url = URL(string: "http://127.0.0.1:\(port)/json/list")!
    let (data, _) = try await URLSession.shared.data(from: url)
    return try JSONDecoder().decode([Target].self, from: data).filter { $0.type == "page" }
  }

  /// Opens a new tab, or a new window, at a URL and returns a session on it.
  func open(_ url: String, newWindow: Bool = false) async throws -> DevToolsSession {
    let browser = try await browserSession()
    defer { browser.close() }
    let result = try await browser.send(
      "Target.createTarget", ["url": "about:blank", "newWindow": newWindow])
    guard let targetID = result["targetId"] as? String else {
      throw HarnessError("Target.createTarget returned no targetId")
    }
    let page = try await session(onTarget: targetID)
    if url != "about:blank" {
      try await page.navigate(to: url)
    }
    return page
  }

  func session(onTarget id: String) async throws -> DevToolsSession {
    let port = try await devToolsPort()
    return try DevToolsSession(url: URL(string: "ws://127.0.0.1:\(port)/devtools/page/\(id)")!)
  }

  func browserSession() async throws -> DevToolsSession {
    let port = try await devToolsPort()
    let url = URL(string: "http://127.0.0.1:\(port)/json/version")!
    let (data, _) = try await URLSession.shared.data(from: url)
    let version = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    guard let socket = (version?["webSocketDebuggerUrl"] as? String).flatMap(URL.init(string:)) else {
      throw HarnessError("/json/version has no webSocketDebuggerUrl")
    }
    return try DevToolsSession(url: socket)
  }

  /// The number of distinct browser windows with a tab open.
  func windowCount() async throws -> Int {
    let browser = try await browserSession()
    defer { browser.close() }
    var windows = Set<Int>()
    for target in try await pageTargets() {
      let result = try await browser.send("Browser.getWindowForTarget", ["targetId": target.id])
      if let window = result["windowId"] as? Int {
        windows.insert(window)
      }
    }
    return windows.count
  }

  // MARK: - The Clair menu

  func clairMenuItem(titled title: String) -> XCUIElement {
    ui.menuBars.menuItems.matching(NSPredicate(format: "title == %@", title)).firstMatch
  }

  /// The update item. Its accessibility name includes the badge while an update
  /// is waiting, so this matches on how the title begins.
  func updateItem(titled prefix: String) -> XCUIElement {
    ui.menuBars.menuItems.matching(NSPredicate(format: "title BEGINSWITH %@", prefix)).firstMatch
  }

  func chooseUpdateItem(titled prefix: String) {
    ui.activate()
    let clair = ui.menuBars.menuBarItems["Clair"]
    XCTAssertTrue(clair.waitForExistence(timeout: 30), "There's no Clair menu")
    clair.click()
    let item = updateItem(titled: prefix)
    XCTAssertTrue(item.waitForExistence(timeout: 10), "The Clair menu has no \(prefix) item")
    item.click()
  }

  /// Whether the update item reads this way, without opening the menu or
  /// causing any input that would restart the idle clock.
  func updateItemExists(titled prefix: String, within seconds: TimeInterval) -> Bool {
    updateItem(titled: prefix).waitForExistence(timeout: seconds)
  }

  /// The update alert with this title, once it's showing.
  func alert(titled title: String, within seconds: TimeInterval = 60) -> XCUIElement? {
    let text = ui.staticTexts[title]
    return text.waitForExistence(timeout: seconds) ? text : nil
  }

  func clickAlertButton(_ title: String) {
    let button = ui.buttons[title]
    XCTAssertTrue(button.waitForExistence(timeout: 10), "The alert has no \(title) button")
    button.click()
  }
}

struct HarnessError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) {
    self.description = description
  }
}

/// A Chrome DevTools Protocol connection to one target.
@MainActor
final class DevToolsSession {
  private let task: URLSessionWebSocketTask
  private var lastID = 0

  init(url: URL) throws {
    task = URLSession.shared.webSocketTask(with: url)
    task.maximumMessageSize = 64 * 1024 * 1024
    task.resume()
  }

  func close() {
    task.cancel(with: .normalClosure, reason: nil)
  }

  @discardableResult
  func send(_ method: String, _ parameters: [String: Any] = [:]) async throws -> [String: Any] {
    lastID += 1
    let id = lastID
    let message: [String: Any] = ["id": id, "method": method, "params": parameters]
    let data = try JSONSerialization.data(withJSONObject: message)
    try await task.send(.string(String(decoding: data, as: UTF8.self)))
    while true {
      let reply = try await task.receive()
      let text: Data
      switch reply {
      case .string(let string): text = Data(string.utf8)
      case .data(let data): text = data
      @unknown default: continue
      }
      guard let object = try JSONSerialization.jsonObject(with: text) as? [String: Any],
        object["id"] as? Int == id
      else {
        continue
      }
      if let error = object["error"] as? [String: Any] {
        throw HarnessError("\(method) failed: \(error)")
      }
      return object["result"] as? [String: Any] ?? [:]
    }
  }

  /// Navigates and waits until the document has loaded.
  func navigate(to url: String) async throws {
    let result = try await send("Page.navigate", ["url": url])
    if let error = result["errorText"] as? String {
      throw HarnessError("Navigating to \(url) failed: \(error)")
    }
    let loaded = await Harness.wait(for: 60) {
      try await self.evaluate("document.readyState") as? String == "complete"
    }
    if !loaded {
      throw HarnessError("\(url) didn't finish loading")
    }
  }

  /// Evaluates an expression as a user gesture, and returns its value.
  func evaluate(_ expression: String) async throws -> Any? {
    let result = try await send(
      "Runtime.evaluate",
      [
        "expression": expression, "returnByValue": true, "awaitPromise": true,
        "userGesture": true,
      ])
    if let exception = result["exceptionDetails"] {
      throw HarnessError("\(expression) threw: \(exception)")
    }
    return (result["result"] as? [String: Any])?["value"]
  }
}
