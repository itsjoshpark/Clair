// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import XCTest

/// Drives Arc or Clair from a command file, for side-by-side comparisons
/// (tests/probe/README.md). One long-running test polls `$PROBE_DIR/cmd`,
/// runs its lines in order, and writes their output to `$PROBE_DIR/out`,
/// ending with `done <n>`. A bad line writes `error: …` and the probe carries
/// on. `probe.sh` starts it and sends the lines.
@MainActor
final class Probe: XCTestCase {
  enum ProbeError: Error, CustomStringConvertible {
    case usage(String)

    var description: String {
      switch self {
      case .usage(let message): message
      }
    }
  }

  private let environment = ProcessInfo.processInfo.environment
  private var app = XCUIApplication(bundleIdentifier: "company.thebrowser.Browser")

  func testProbe() throws {
    let directory = try XCTUnwrap(environment["PROBE_DIR"], "set PROBE_DIR (TEST_RUNNER_PROBE_DIR)")
    let commandURL = URL(fileURLWithPath: directory).appendingPathComponent("cmd")
    let outURL = URL(fileURLWithPath: directory).appendingPathComponent("out")
    let hours = Double(environment["PROBE_HOURS"] ?? "") ?? 3
    let deadline = Date().addingTimeInterval(hours * 3600)
    var sequence = 0
    try? "ready\n".write(to: outURL, atomically: true, encoding: .utf8)
    while Date() < deadline {
      guard let text = try? String(contentsOf: commandURL, encoding: .utf8), !text.isEmpty else {
        Thread.sleep(forTimeInterval: 0.1)
        continue
      }
      try? FileManager.default.removeItem(at: commandURL)
      var out = ""
      var quit = false
      for line in text.split(separator: "\n").map(String.init) where !line.isEmpty {
        do {
          if line == "quit" {
            quit = true
            break
          }
          out += try run(line)
        } catch {
          out += "error: \(line): \(error)\n"
        }
      }
      sequence += 1
      out += "done \(sequence)\n"
      try? out.write(to: outURL, atomically: true, encoding: .utf8)
      if quit { return }
    }
  }

  /// Runs one line and returns its output.
  private func run(_ line: String) throws -> String {
    let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
    let rest = parts.count > 1 ? parts[1] : ""
    let words = rest.split(separator: " ").map(String.init)
    let window = app.windows.firstMatch
    func number(_ index: Int) throws -> Double {
      guard index < words.count, let value = Double(words[index]) else {
        throw ProbeError.usage("expected a number as argument \(index + 1)")
      }
      return value
    }
    func point(_ index: Int) throws -> XCUICoordinate {
      window.coordinate(withNormalizedOffset: .zero)
        .withOffset(CGVector(dx: try number(index), dy: try number(index + 1)))
    }
    func modifiers(_ index: Int) throws -> XCUIElement.KeyModifierFlags {
      index < words.count ? try Self.modifiers(words[index]) : []
    }

    switch parts[0] {
    case "app":
      guard !rest.isEmpty else { throw ProbeError.usage("app <bundle id>") }
      app = XCUIApplication(bundleIdentifier: rest)
    case "activate":
      app.activate()
    case "click":
      let target = try point(0)
      let flags = try modifiers(2)
      XCUIElement.perform(withKeyModifiers: flags) { target.click() }
    case "rclick":
      try point(0).rightClick()
    case "hover":
      try point(0).hover()
    case "scroll":
      try point(0).scroll(byDeltaX: 0, deltaY: try number(2))
    case "drag":
      // At a hand's speed, so the app sees the drag move rather than jump.
      try point(0).press(
        forDuration: 0.3, thenDragTo: try point(2), withVelocity: .slow, thenHoldForDuration: 0.3)
    case "key":
      guard let name = words.first else { throw ProbeError.usage("key <name> [mods]") }
      app.typeKey(try Self.key(name), modifierFlags: try modifiers(1))
    case "type":
      app.typeText(rest)
    case "paste":
      // Puts the text on the pasteboard and presses Cmd+V: typeText isn't
      // reliable for emoji.
      guard !rest.isEmpty else { throw ProbeError.usage("paste <text>") }
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(rest, forType: .string)
      app.typeKey("v", modifierFlags: .command)
    case "tree":
      return app.debugDescription + "\n"
    case "frame":
      return "\(window.frame)\n"
    case "sleep":
      guard let seconds = Double(rest) else { throw ProbeError.usage("sleep <seconds>") }
      Thread.sleep(forTimeInterval: seconds)
    case "menu":
      // An open menu's item when several share the title, as a menu bar
      // item and a context or pop-up menu's can.
      let items = app.menuItems.matching(NSPredicate(format: "title == %@", rest)).allElementsBoundByIndex
      guard let item = items.first(where: { $0.isHittable }) ?? items.first else {
        throw ProbeError.usage("no menu item titled \(rest)")
      }
      item.click()
    default:
      throw ProbeError.usage("unknown command")
    }
    return ""
  }

  /// `shift,cmd,opt,ctrl` in any combination.
  private static func modifiers(_ list: String) throws -> XCUIElement.KeyModifierFlags {
    var flags: XCUIElement.KeyModifierFlags = []
    for name in list.split(separator: ",") {
      switch name {
      case "shift": flags.insert(.shift)
      case "cmd": flags.insert(.command)
      case "opt": flags.insert(.option)
      case "ctrl": flags.insert(.control)
      default: throw ProbeError.usage("unknown modifier \(name)")
      }
    }
    return flags
  }

  /// A named key, or a single character.
  private static func key(_ name: String) throws -> String {
    let named: [String: XCUIKeyboardKey] = [
      "return": .return, "escape": .escape, "tab": .tab, "space": .space, "delete": .delete,
      "forwarddelete": .forwardDelete, "up": .upArrow, "down": .downArrow, "left": .leftArrow,
      "right": .rightArrow, "home": .home, "end": .end, "pageup": .pageUp, "pagedown": .pageDown,
    ]
    if let key = named[name] { return key.rawValue }
    guard name.count == 1 else { throw ProbeError.usage("unknown key \(name)") }
    return name
  }
}
