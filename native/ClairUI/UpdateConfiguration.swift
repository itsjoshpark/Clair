// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import Foundation

/// How this package's updater is set up. Release packages use only what
/// package.sh wrote into Info.plist. A non-official package, which package.sh
/// marks when it signs ad hoc, may also take overrides from the environment,
/// so tests can use a local appcast.
struct UpdateConfiguration: Equatable {
  /// The Info.plist key package.sh sets on packages it signs ad hoc. Release
  /// packages don't have it, and adding it would break their signature.
  static let nonOfficialPackageKey = "ClairNonOfficialPackage"
  static let feedURLOverrideVariable = "CLAIR_TEST_FEED_URL"

  /// The appcast to use instead of Info.plist's `SUFeedURL`.
  let feedURLOverride: String?

  init(infoDictionary: [String: Any], environment: [String: String]) {
    guard infoDictionary[Self.nonOfficialPackageKey] as? Bool == true else {
      feedURLOverride = nil
      return
    }
    let feedURL = environment[Self.feedURLOverrideVariable] ?? ""
    feedURLOverride = feedURL.isEmpty ? nil : feedURL
  }

  static var current: UpdateConfiguration {
    UpdateConfiguration(
      infoDictionary: Bundle.main.infoDictionary ?? [:],
      environment: ProcessInfo.processInfo.environment
    )
  }
}
