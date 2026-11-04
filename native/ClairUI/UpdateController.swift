// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Sparkle
import os

/// Runs Sparkle for the app (design D4): it checks and downloads on its own
/// with no window, a downloaded update installs when Clair quits, and the Clair
/// menu's update item reports and installs it.
///
/// Info.plist turns on the automatic checks and downloads and sets their
/// interval (package.sh), so Sparkle asks the user nothing.
///
/// Clair always reopens through Chromium's relaunch, never Sparkle's. Chromium
/// asks about downloads, restores the session and stays in the background when
/// Clair was, and its relauncher waits for the installer. So Sparkle is never
/// told to install: Autoupdate does that when it sees Clair quit.
final class UpdateController: NSObject, SPUUpdaterDelegate {
  private static let logger = Logger(subsystem: "dev.joshuapark.Clair", category: "Updates")
  private static let lastRunVersionKey = "ClairLastRunVersion"

  private let host: any ClairHost
  private let configuration: UpdateConfiguration
  private let prompts: any UpdatePrompting
  private let userDriver = UpdateUserDriver()
  private var updater: SPUUpdater?
  private var startError: (any Error)?
  private lazy var menu = UpdateMenu { [weak self] in
    self?.chooseUpdateItem()
  }

  /// The update that's downloaded and waiting to install, if any.
  private(set) var waitingUpdate: SUAppcastItem?

  /// The version Clair last ran, for a later "Update Complete!" banner. Nil on
  /// the first launch.
  private(set) var previousVersion: String?

  init(
    host: any ClairHost, configuration: UpdateConfiguration,
    prompts: any UpdatePrompting = UpdateAlerts()
  ) {
    self.host = host
    self.configuration = configuration
    self.prompts = prompts
    super.init()
    userDriver.onUpdateWaiting = { [weak self] item, userInitiated in
      self?.updateIsWaiting(item, userInitiated: userInitiated)
    }
    userDriver.onNoUpdate = { [weak self] in
      self?.prompts.showUpToDate(version: Self.runningVersion)
    }
    userDriver.onCheckFailed = { [weak self] error in
      self?.prompts.showCheckFailed(reason: error.localizedDescription)
    }
  }

  /// Adds the menu item and starts Sparkle for the running app. If Sparkle
  /// can't start, for example in a package with no public key, Clair logs that
  /// and the item reports it.
  func start() {
    menu.install(in: NSApp.mainMenu)
    recordRunningVersion(in: .standard)

    let bundle = Bundle.main
    let updater = SPUUpdater(
      hostBundle: bundle, applicationBundle: bundle, userDriver: userDriver, delegate: self)
    self.updater = updater
    do {
      try updater.start()
    } catch {
      startError = error
      Self.logger.error("Sparkle didn't start: \(error.localizedDescription, privacy: .public)")
      return
    }
    Self.logger.info(
      "Sparkle started: feed \(updater.feedURL?.absoluteString ?? "none", privacy: .public), automatic checks \(updater.automaticallyChecksForUpdates), automatic downloads \(updater.automaticallyDownloadsUpdates), every \(updater.updateCheckInterval) s"
    )
  }

  /// The version from an appcast item's display string, "0.1.1 (101)".
  static func shortVersion(fromDisplayString display: String) -> String {
    display.split(separator: " ").first.map(String.init) ?? display
  }

  private static var runningVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
  }

  func recordRunningVersion(in defaults: UserDefaults) {
    previousVersion = defaults.string(forKey: Self.lastRunVersionKey)
    defaults.set(Self.runningVersion, forKey: Self.lastRunVersionKey)
  }

  func updateIsWaiting(_ item: SUAppcastItem, userInitiated: Bool) {
    let alreadyWaiting = waitingUpdate != nil
    waitingUpdate = item
    if !alreadyWaiting {
      Self.logger.info("Update \(item.displayVersionString, privacy: .public) is waiting to install on quit")
      host.updateWillInstallOnQuit()
      menu.setUpdateWaiting(true)
    }
    if userInitiated {
      offerRestart()
    }
  }

  func chooseUpdateItem() {
    if waitingUpdate != nil {
      offerRestart()
    } else if let updater, startError == nil {
      updater.checkForUpdates()
    } else {
      prompts.showCheckFailed(reason: startError?.localizedDescription ?? "The updater isn't running.")
    }
  }

  private func offerRestart() {
    guard let waitingUpdate else {
      return
    }
    let version = Self.shortVersion(fromDisplayString: waitingUpdate.displayVersionString)
    guard prompts.askToRestart(forVersion: version) else {
      return
    }
    if host.silentRelaunchBlockers().contains(.incognitoWindow),
      !prompts.askToCloseIncognitoWindows()
    {
      return
    }
    host.relaunch()
  }

  var menuItemForTesting: NSMenuItem {
    menu.item
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
    updateIsWaiting(item, userInitiated: false)
    return true
  }

  func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
    Self.logger.info("No update: \(error.localizedDescription, privacy: .public)")
  }

  func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
    Self.logger.error("Update stopped: \(error.localizedDescription, privacy: .public)")
  }
}
