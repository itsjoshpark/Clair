// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Foundation
import os

/// The running native layer. Chromium starts it once per launch, and it keeps
/// the host for as long as the app runs.
final class NativeLayer {
  static let logger = Logger(subsystem: "dev.joshuapark.Clair", category: "ClairUI")

  /// The layer Chromium started, if it has.
  private(set) static var current: NativeLayer?

  let host: any ClairHost

  /// Sparkle, once the layer is running inside Clair.app.
  private(set) var updates: UpdateController?

  /// The About window behind "About Clair", once the layer is running inside
  /// Clair.app.
  private(set) var about: AboutWindowController?

  init(host: any ClairHost) {
    self.host = host
  }

  /// Runs what only makes sense inside the app: not in a unit test's process,
  /// whose main bundle isn't Clair.
  private func startInApp() {
    guard Bundle.main.bundleIdentifier == "dev.joshuapark.Clair" else {
      return
    }
    let about = AboutWindowController(host: host, info: AboutInfo(bundle: .main, host: host))
    about.install(in: NSApp.mainMenu)
    self.about = about
    MainMenuTitles.apply(to: NSApp.mainMenu)

    let updates = UpdateController(host: host, configuration: .current)
    updates.start()
    self.updates = updates
  }

  /// Starts the native layer with Chromium's host. A second call keeps the
  /// first layer and its host.
  @discardableResult
  static func start(host: any ClairHost) -> NativeLayer {
    if let current {
      logger.error("ClairUI was started twice; keeping the first host")
      return current
    }
    let layer = NativeLayer(host: host)
    current = layer
    layer.startInApp()
    logger.info(
      "ClairUI started with Chromium \(host.chromiumVersion, privacy: .public) (ungoogled-chromium \(host.ungoogledChromiumVersion, privacy: .public))"
    )
    return layer
  }
}
