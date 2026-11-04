// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import Foundation
import Sparkle

/// Sparkle's user interface, with no windows: it accepts every update it's
/// offered and reports what happened. Clair never replies "install" once an
/// update is ready, because that would make Sparkle quit and reopen the app
/// itself. Left alone, Autoupdate installs the update when Clair next quits.
///
/// Reports run from the main queue after Sparkle's call returns, because they
/// may show a modal alert.
final class UpdateUserDriver: NSObject, SPUUserDriver {
  /// An update has been downloaded and Autoupdate is waiting for Clair to quit.
  /// The flag says whether the user asked for this check.
  var onUpdateWaiting: ((SUAppcastItem, Bool) -> Void)?
  /// A check the user asked for found nothing newer.
  var onNoUpdate: (() -> Void)?
  /// A check the user asked for, or the download it started, failed.
  var onCheckFailed: ((any Error) -> Void)?

  /// The update Sparkle last offered, until it's ready or the cycle ends.
  private var offeredUpdate: SUAppcastItem?
  /// Whether the check in progress is one the user asked for.
  private var userInitiated = false

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

  func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
    userInitiated = true
  }

  func showUpdateFound(
    with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
    reply: @escaping (SPUUserUpdateChoice) -> Void
  ) {
    offeredUpdate = appcastItem
    userInitiated = userInitiated || state.userInitiated
    if state.stage == .installing {
      reportUpdateWaiting(appcastItem)
    }
    reply(Self.choice(forStage: state.stage, informationOnly: appcastItem.isInformationOnlyUpdate))
  }

  func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

  func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

  func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
    if userInitiated {
      report { [onNoUpdate] in onNoUpdate?() }
    }
    acknowledgement()
  }

  func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
    if userInitiated {
      report { [onCheckFailed] in onCheckFailed?(error) }
    }
    acknowledgement()
  }

  func showDownloadInitiated(cancellation: @escaping () -> Void) {}

  func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}

  func showDownloadDidReceiveData(ofLength length: UInt64) {}

  func showDownloadDidStartExtractingUpdate() {}

  func showExtractionReceivedProgress(_ progress: Double) {}

  func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
    if let offeredUpdate {
      reportUpdateWaiting(offeredUpdate)
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
    userInitiated = false
  }

  func showUpdateInFocus() {}

  private func reportUpdateWaiting(_ item: SUAppcastItem) {
    report { [onUpdateWaiting, userInitiated] in onUpdateWaiting?(item, userInitiated) }
  }

  private func report(_ action: @escaping @MainActor () -> Void) {
    DispatchQueue.main.async {
      action()
    }
  }
}
