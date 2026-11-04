// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import Foundation
import Sparkle
import Testing

@testable import ClairUI

struct UpdateConfigurationTests {
  private let environment = [UpdateConfiguration.feedURLOverrideVariable: "http://localhost:8000/appcast.xml"]

  @Test func releasePackageIgnoresTheOverride() {
    let configuration = UpdateConfiguration(infoDictionary: [:], environment: environment)
    #expect(configuration.feedURLOverride == nil)
  }

  @Test func onlyATrueMarkerCounts() {
    for marker: Any in [false, "YES", 1] {
      let configuration = UpdateConfiguration(
        infoDictionary: [UpdateConfiguration.nonOfficialPackageKey: marker], environment: environment)
      #expect(configuration.feedURLOverride == nil)
    }
  }

  @Test func nonOfficialPackageReadsTheOverride() {
    let configuration = UpdateConfiguration(
      infoDictionary: [UpdateConfiguration.nonOfficialPackageKey: true], environment: environment)
    #expect(configuration.feedURLOverride == "http://localhost:8000/appcast.xml")
  }

  @Test func nonOfficialPackageWithoutAnOverrideUsesInfoPlist() {
    let configuration = UpdateConfiguration(
      infoDictionary: [UpdateConfiguration.nonOfficialPackageKey: true],
      environment: [UpdateConfiguration.feedURLOverrideVariable: ""])
    #expect(configuration.feedURLOverride == nil)
  }
}

struct UpdateUserDriverTests {
  @Test func everyUpdateNotYetInstallingIsAccepted() {
    #expect(UpdateUserDriver.choice(forStage: .notDownloaded, informationOnly: false) == .install)
    #expect(UpdateUserDriver.choice(forStage: .downloaded, informationOnly: false) == .install)
  }

  /// "Install" at this stage would make Sparkle quit Clair right away.
  @Test func anUpdateAlreadyInstallingIsLeftToInstallOnQuit() {
    #expect(UpdateUserDriver.choice(forStage: .installing, informationOnly: false) == .dismiss)
  }

  @Test func informationOnlyUpdatesAreNotInstalled() {
    #expect(UpdateUserDriver.choice(forStage: .notDownloaded, informationOnly: true) == .dismiss)
  }
}
