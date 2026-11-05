// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import Testing

@testable import ClairUI

struct AboutInfoTests {
  private let plist: [String: Any] = [
    "CFBundleShortVersionString": "0.1.0",
    "CFBundleVersion": "123",
    "NSHumanReadableCopyright": "Copyright 2026 The Clair Authors. All rights reserved.",
  ]

  private func info(_ plist: [String: Any]) -> AboutInfo {
    AboutInfo(
      value: { plist[$0] }, chromiumVersion: "156.0.8078.79", ungoogledChromiumVersion: "156.0.8078.79-1")
  }

  @Test func showsTheClairVersionAndBuildNumber() {
    #expect(info(plist).version == "Version 0.1.0 (123)")
  }

  @Test func labelsTheEngineVersions() {
    #expect(info(plist).engine == "Chromium Engine Version 156.0.8078.79\n(ungoogled-chromium 156.0.8078.79-1)")
  }

  @Test func readsTheCopyrightFromInfoPlist() {
    #expect(info(plist).copyright == "Copyright 2026 The Clair Authors. All rights reserved.")
    #expect(info([:]).copyright == nil)
  }

  @Test func readsTheHostsVersions() {
    let host = FakeHost(chromiumVersion: "156.0.8078.1", ungoogledChromiumVersion: "156.0.8078.1-2")
    let info = AboutInfo(bundle: .main, host: host)
    #expect(info.engine == "Chromium Engine Version 156.0.8078.1\n(ungoogled-chromium 156.0.8078.1-2)")
  }

  @Test func creditsLinkChromiumItsCreditsOtherCreditsAndTheLicense() {
    let credits = info(plist).credits
    let links = credits.runs.compactMap { run in run.link.map { (String(credits[run.range].characters), $0) } }
    #expect(links.map(\.0) == ["Chromium", "open source software", "open source software", "GPLv3"])
    #expect(links.map(\.1) == AboutLink.allCases.map(\.url))
    #expect(String(credits.characters).hasSuffix("It's free software under the GPLv3, with no warranty."))
  }

  @Test func chromiumsCreditsOpenAsAChromePage() {
    #expect(AboutLink.chromiumCredits.url.absoluteString == "chrome://credits/")
  }
}

@MainActor
struct AboutWindowTests {
  private func appMenu(firstTitle: String = "About Clair") -> (NSMenu, NSMenu) {
    let main = NSMenu()
    let app = NSMenu(title: "Clair")
    app.addItem(withTitle: firstTitle, action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    app.addItem(.separator())
    app.addItem(withTitle: "Quit Clair", action: nil, keyEquivalent: "q")
    main.addItem(withTitle: "Clair", action: nil, keyEquivalent: "").submenu = app
    return (main, app)
  }

  private func controller(host: FakeHost = FakeHost()) -> AboutWindowController {
    AboutWindowController(host: host, info: AboutInfo(bundle: .main, host: host))
  }

  @Test func aboutClairOpensTheWindow() throws {
    let (main, app) = appMenu()
    let about = controller()
    #expect(about.install(in: main))
    let item = try #require(app.items.first)
    #expect(item.target === about)
    #expect(item.action != #selector(NSApplication.orderFrontStandardAboutPanel(_:)))

    #expect(about.window == nil)
    NSApplication.shared.sendAction(try #require(item.action), to: item.target, from: item)
    let window = try #require(about.window)
    #expect(window.isVisible)
    window.close()
  }

  @Test func anUnexpectedMenuIsLeftToChromium() throws {
    let (main, app) = appMenu(firstTitle: "Services")
    let about = controller()
    #expect(!about.install(in: main))
    let item = try #require(app.items.first)
    #expect(item.target == nil)
    #expect(item.action == #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
    #expect(!about.install(in: nil))
  }

  @Test func openingAgainKeepsOneWindow() throws {
    let about = controller()
    about.show()
    let first = try #require(about.window)
    first.close()
    about.show()
    about.show()
    #expect(about.window === first)
    #expect(first.isVisible)
    let open = NSApplication.shared.windows.filter { $0.title == AboutWindowController.windowTitle && $0.isVisible }
    #expect(open.count == 1)
    first.close()
  }

  @Test func theWindowCanOnlyBeClosed() throws {
    let about = controller()
    about.show()
    let window = try #require(about.window)
    #expect(window.styleMask.contains(.closable))
    #expect(!window.styleMask.contains(.miniaturizable))
    #expect(!window.styleMask.contains(.resizable))
    window.close()
  }
}
