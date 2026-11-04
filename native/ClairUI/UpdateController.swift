// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Sparkle
import os

/// Runs Sparkle for the app (design D4): it checks and downloads on its own
/// with no window, and a downloaded update installs when Clair quits.
///
/// Info.plist turns on the automatic checks and downloads and sets their
/// interval (package.sh), so Sparkle asks the user nothing.
final class UpdateController: NSObject, SPUUpdaterDelegate {
  private static let logger = Logger(subsystem: "dev.joshuapark.Clair", category: "Updates")

  private let configuration: UpdateConfiguration
  private let userDriver = UpdateUserDriver()
  private var updater: SPUUpdater?

  /// The update that's downloaded and waiting to install, if any.
  private(set) var waitingUpdate: SUAppcastItem?

  init(configuration: UpdateConfiguration) {
    self.configuration = configuration
    super.init()
    userDriver.onUpdateWaiting = { [weak self] item in
      self?.updateIsWaiting(item)
    }
  }

  /// Starts Sparkle for the running app. If it can't start, for example in a
  /// package with no public key, Clair logs that and runs without updates.
  func start() {
    let bundle = Bundle.main
    let updater = SPUUpdater(
      hostBundle: bundle, applicationBundle: bundle, userDriver: userDriver, delegate: self)
    self.updater = updater
    do {
      try updater.start()
    } catch {
      Self.logger.error("Sparkle didn't start: \(error.localizedDescription, privacy: .public)")
      return
    }
    Self.logger.info(
      "Sparkle started: feed \(updater.feedURL?.absoluteString ?? "none", privacy: .public), automatic checks \(updater.automaticallyChecksForUpdates), automatic downloads \(updater.automaticallyDownloadsUpdates), every \(updater.updateCheckInterval) s"
    )
  }

  private func updateIsWaiting(_ item: SUAppcastItem) {
    waitingUpdate = item
    Self.logger.info("Update \(item.displayVersionString, privacy: .public) is waiting to install on quit")
  }

  // MARK: - SPUUpdaterDelegate

  func feedURLString(for updater: SPUUpdater) -> String? {
    configuration.feedURLOverride
  }

  /// A background download has finished, and Autoupdate is waiting for Clair
  /// to quit. Returning true keeps this cycle open, so Sparkle starts no more
  /// checks and never brings the update up with the user driver on its own.
  func updater(
    _ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
    immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
  ) -> Bool {
    updateIsWaiting(item)
    return true
  }

  func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
    Self.logger.info("No update: \(error.localizedDescription, privacy: .public)")
  }

  func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
    Self.logger.error("Update stopped: \(error.localizedDescription, privacy: .public)")
  }
}
