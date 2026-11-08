// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import Foundation

/// When the link status capsule shows and hides (design D18): it shows once
/// the pointer has rested on links for `showDelay`, and hides `hideDelay`
/// after it leaves them. While it shows, a new link replaces its text at once.
struct StatusCapsuleState: Equatable {
  static let showDelay: TimeInterval = 0.5
  static let hideDelay: TimeInterval = 0.5

  /// What the capsule shows, or nil while it's hidden.
  private(set) var shownText: String?
  /// What Chromium last reported.
  private(set) var reportedText: String?
  /// When the waiting change is due, if one is waiting.
  private(set) var deadline: TimeInterval?

  /// Chromium reported `text` (nil when the pointer left the link) at `now`.
  mutating func report(_ text: String?, at now: TimeInterval) {
    reportedText = text
    switch (shownText, text) {
    case (nil, nil):
      // Left the link before the capsule showed.
      deadline = nil
    case (nil, .some):
      // Moving between links while waiting keeps the wait going.
      if deadline == nil {
        deadline = now + Self.showDelay
      }
    case (.some, .some(let text)):
      shownText = text
      deadline = nil
    case (.some, nil):
      deadline = now + Self.hideDelay
    }
  }

  /// Applies the waiting change if it's due at `now`; returns whether the
  /// capsule changed.
  mutating func tick(at now: TimeInterval) -> Bool {
    guard let deadline, now >= deadline else { return false }
    self.deadline = nil
    shownText = reportedText
    return true
  }

  /// Hides the capsule at once, as when the command bar opens.
  mutating func reset() {
    self = StatusCapsuleState()
  }
}
