// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import ClairHost
import os

/// The running native layer. Chromium starts it once per launch, and it keeps
/// the host for as long as the app runs.
final class NativeLayer {
  static let logger = Logger(subsystem: "dev.joshuapark.Clair", category: "ClairUI")

  /// The layer Chromium started, if it has.
  private(set) static var current: NativeLayer?

  let host: any ClairHost

  init(host: any ClairHost) {
    self.host = host
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
    logger.info(
      "ClairUI started with Chromium \(host.chromiumVersion, privacy: .public) (ungoogled-chromium \(host.ungoogledChromiumVersion, privacy: .public))"
    )
    return layer
  }
}
