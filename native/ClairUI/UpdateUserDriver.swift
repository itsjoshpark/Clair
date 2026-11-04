// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import Foundation
import Sparkle

/// Sparkle's user interface, with no windows: it accepts every update it's
/// offered and reports when one is ready. Clair never replies "install" once
/// an update is ready, because that would make Sparkle quit and reopen the app
/// itself. Left alone, Autoupdate installs the update when Clair next quits.
final class UpdateUserDriver: NSObject, SPUUserDriver {
  /// Called when an update has been downloaded and Autoupdate is waiting for
  /// Clair to quit.
  var onUpdateWaiting: ((SUAppcastItem) -> Void)?

  /// The update Sparkle last offered, until it's ready or the cycle ends.
  private var offeredUpdate: SUAppcastItem?

  /// What to answer when Sparkle offers an update at `stage`.
  static func choice(forStage stage: SPUUserUpdateStage, informationOnly: Bool) -> SPUUserUpdateChoice {
    if informationOnly {
      return .dismiss
    }
    switch stage {
    case .notDownloaded, .downloaded:
      return .install
    case .installing:
      // Autoupdate is already waiting for Clair to quit, and replying
      // "install" would quit Clair now.
      return .dismiss
    @unknown default:
      return .dismiss
    }
  }

  func show(
    _ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void
  ) {
    // Info.plist's SUEnableAutomaticChecks means Sparkle never asks this. If
    // it does, the answer is the same as Info.plist's.
    reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
  }

  func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}

  func showUpdateFound(
    with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
    reply: @escaping (SPUUserUpdateChoice) -> Void
  ) {
    offeredUpdate = appcastItem
    if state.stage == .installing {
      onUpdateWaiting?(appcastItem)
    }
    reply(Self.choice(forStage: state.stage, informationOnly: appcastItem.isInformationOnlyUpdate))
  }

  func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

  func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

  func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
    acknowledgement()
  }

  func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
    acknowledgement()
  }

  func showDownloadInitiated(cancellation: @escaping () -> Void) {}

  func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}

  func showDownloadDidReceiveData(ofLength length: UInt64) {}

  func showDownloadDidStartExtractingUpdate() {}

  func showExtractionReceivedProgress(_ progress: Double) {}

  func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
    if let offeredUpdate {
      onUpdateWaiting?(offeredUpdate)
    }
    reply(.dismiss)
  }

  func showInstallingUpdate(
    withApplicationTerminated applicationTerminated: Bool,
    retryTerminatingApplication: @escaping () -> Void
  ) {}

  func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
    acknowledgement()
  }

  func dismissUpdateInstallation() {
    offeredUpdate = nil
  }
}
