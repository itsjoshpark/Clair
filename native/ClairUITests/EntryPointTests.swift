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
    ClairUIMain.start(host: first)
    ClairUIMain.start(host: second)
    let layer = try #require(NativeLayer.current)
    #expect(layer.host === first)
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
