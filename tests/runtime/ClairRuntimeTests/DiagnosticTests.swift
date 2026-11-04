import AppKit
import Foundation
import XCTest

@MainActor
final class DiagnosticTests: XCTestCase {
  private func report(_ label: String, _ ui: XCUIApplication) {
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: Harness.bundleID)
    print("DIAG \(label): state=\(ui.state.rawValue) nsrunning=\(running.map { "\($0.processIdentifier) \($0.bundleURL?.path ?? "?") reg=\($0.activationPolicy.rawValue)" })")
    print("DIAG \(label): windows=\(ui.windows.count) menubars=\(ui.menuBars.count) items=\(ui.menuBars.menuItems.count)")
    print("DIAG \(label): pgrep=\((try? Harness.run("/usr/bin/pgrep", ["-lx", "Clair"]).output) ?? "")")
  }

  private func clone() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appending(path: "diag-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let app = dir.appending(path: "Clair.app")
    try FileManager.default.copyItem(at: Fixture.directory.appending(path: "Clair.app"), to: app)
    return app
  }

  private func data() -> String {
    FileManager.default.temporaryDirectory.appending(path: "diag-data-\(UUID().uuidString)").path
  }

  override func setUp() async throws {
    try Harness.reset()
  }

  func testA_direct() async throws {
    let app = try clone()
    let p = Process()
    p.executableURL = app.appending(path: "Contents/MacOS/Clair")
    p.arguments = ["--no-first-run", "--no-default-browser-check", "--use-mock-keychain", "--user-data-dir=\(data())", "about:blank"]
    p.environment = ProcessInfo.processInfo.environment.filter { ["HOME", "PATH", "TMPDIR", "USER", "LOGNAME"].contains($0.key) }
    try p.run()
    try await Task.sleep(for: .seconds(15))
    let ui = XCUIApplication(bundleIdentifier: Harness.bundleID)
    report("direct bundleID", ui)
    report("direct url", XCUIApplication(url: app))
  }

  func testB_open() async throws {
    let app = try clone()
    let r = try Harness.run("/usr/bin/open", ["-n", app.path, "--args", "--no-first-run", "--no-default-browser-check", "--use-mock-keychain", "--user-data-dir=\(data())", "about:blank"])
    print("DIAG open: \(r)")
    try await Task.sleep(for: .seconds(15))
    let ui = XCUIApplication(bundleIdentifier: Harness.bundleID)
    report("open bundleID", ui)
    ui.activate()
    report("open after activate", ui)
    report("open url", XCUIApplication(url: app))
  }

  func testC_xcuiLaunch() async throws {
    let app = try clone()
    let ui = XCUIApplication(url: app)
    ui.launchArguments = ["--no-first-run", "--no-default-browser-check", "--use-mock-keychain", "--user-data-dir=\(data())", "--remote-debugging-port=9333", "about:blank"]
    ui.launch()
    try await Task.sleep(for: .seconds(10))
    report("launch", ui)
    report("launch other handle", XCUIApplication(bundleIdentifier: Harness.bundleID))
    let (json, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:9333/json/list")!)
    print("DIAG launch targets: \(String(decoding: json, as: UTF8.self))")
    print("DIAG launch ps: \(try Harness.run("/bin/ps", ["-axo", "pid,command"]).output.split(separator: "\n").filter { $0.contains("MacOS/Clair") })")
    ui.terminate()
  }

  override func tearDown() async throws {
    try Harness.reset()
  }
}
