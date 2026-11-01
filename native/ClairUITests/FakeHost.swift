// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import ClairHost
import Foundation

/// A stand-in for Chromium's implementation of `ClairHost`.
final class FakeHost: NSObject, ClairHost {
  let chromiumVersion: String
  let ungoogledChromiumVersion: String
  var blockers: RelaunchBlockers = []
  private(set) var relaunchCount = 0

  init(chromiumVersion: String = "156.0.8078.73", ungoogledChromiumVersion: String = "156.0.8078.73-1") {
    self.chromiumVersion = chromiumVersion
    self.ungoogledChromiumVersion = ungoogledChromiumVersion
  }

  func silentRelaunchBlockers() -> RelaunchBlockers {
    blockers
  }

  func relaunch() {
    relaunchCount += 1
  }
}
