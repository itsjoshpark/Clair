// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import CoreGraphics
import Foundation

/// When to try installing a waiting update while the user is away (design D4):
/// once the Mac has had no input for the threshold, then after every further
/// threshold, until there's input again.
struct IdleInstallSchedule: Equatable {
  /// 30 minutes. Arc's thresholds weren't recorded, so this is Clair's choice.
  static let defaultThreshold: TimeInterval = 30 * 60

  let threshold: TimeInterval
  private var nextAttempt: TimeInterval

  init(threshold: TimeInterval) {
    self.threshold = threshold
    nextAttempt = threshold
  }

  /// Whether to try now, given how long the Mac has had no input.
  mutating func shouldAttempt(idleFor idle: TimeInterval) -> Bool {
    guard idle >= threshold else {
      nextAttempt = threshold
      return false
    }
    guard idle >= nextAttempt else {
      return false
    }
    nextAttempt = idle + threshold
    return true
  }
}

/// Watches the system idle time while an update is waiting.
final class IdleInstaller {
  private var schedule: IdleInstallSchedule
  private let attempt: () -> Void
  private var timer: Timer?

  init(threshold: TimeInterval, attempt: @escaping () -> Void) {
    schedule = IdleInstallSchedule(threshold: threshold)
    self.attempt = attempt
  }

  /// The time since the last keyboard, mouse or trackpad input.
  private static var systemIdleTime: TimeInterval {
    // kCGAnyInputEventType isn't imported into Swift.
    guard let anyInput = CGEventType(rawValue: ~0) else {
      return 0
    }
    return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
  }

  /// Starts watching. The timer runs only in the default run loop mode, so it
  /// doesn't fire while an alert is open, including Clair's own "ready" alert.
  func start() {
    guard timer == nil else {
      return
    }
    timer = Timer.scheduledTimer(withTimeInterval: min(30, schedule.threshold / 2), repeats: true) {
      [weak self] _ in
      MainActor.assumeIsolated {
        self?.check()
      }
    }
  }

  private func check() {
    if schedule.shouldAttempt(idleFor: Self.systemIdleTime) {
      attempt()
    }
  }
}
