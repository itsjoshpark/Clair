// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import ClairHost
import Foundation
import Testing

@testable import ClairUI

/// How Chromium finds and starts the native layer (`ClairHost.h`).
@MainActor
struct EntryPointTests {
  let bundle = Bundle(for: ClairUIMain.self)

  @Test func principalClassIsTheEntryPoint() throws {
    let principal = try #require(bundle.principalClass as? NSObject.Type)
    #expect(NSStringFromClass(principal) == "ClairUIMain")
    #expect(principal.conforms(to: ClairUIEntryPoint.self))
  }

  @Test func bundleIdentifierIsUnderClairs() {
    #expect(bundle.bundleIdentifier == "dev.joshuapark.Clair.ClairUI")
  }

  @Test func startKeepsTheFirstHost() throws {
    let first = FakeHost()
    let second = FakeHost(chromiumVersion: "157.0.0.0")
    // Another test may have started the layer already; either way, a later
    // call keeps the host it has.
    ClairUIMain.start(host: first)
    let kept = try #require(NativeLayer.current).host
    ClairUIMain.start(host: second)
    let layer = try #require(NativeLayer.current)
    #expect(layer.host === kept)
    #expect(layer.host !== second)
  }

  @Test(arguments: [ProfileKind.regular, .incognito, .guest])
  func windowForEveryBrowser(kind: ProfileKind) throws {
    // The window reads its tabs from the running layer's host.
    let layer = NativeLayer.current ?? NativeLayer.start(host: FakeHost())
    let host = try #require(layer.host as? FakeHost)
    let browser = FakeBrowser(host: host, profileKind: kind)
    browser.addTab(title: "Example", url: "https://example.com/")
    let clairWindow = ClairUIMain.window(for: browser)
    let controller = try #require(clairWindow as? BrowserWindowController)
    let window = browser.window

    #expect(controller.window === window)
    #expect(window.styleMask.contains(.fullSizeContentView))
    #expect(window.titlebarAppearsTransparent)
    #expect(window.titleVisibility == .hidden)
    #expect(window.toolbar == nil)
    #expect(window.appearance?.name == (kind == .incognito ? .darkAqua : nil))
    #expect(controller.model.profileKind == kind)
    #expect(controller.model.tabs.map(\.title) == ["Example"])
    #expect(controller.model.activeTabID == browser.activeTabID)
  }

  @Test func layerReachesChromiumOnlyThroughTheHost() {
    let host = FakeHost()
    host.blockers = [.downloadInProgress, .audibleTab]
    let layer = NativeLayer(host: host)
    #expect(layer.host.silentRelaunchBlockers() == [.downloadInProgress, .audibleTab])
    layer.host.relaunch()
    #expect(host.relaunchCount == 1)
  }
}
