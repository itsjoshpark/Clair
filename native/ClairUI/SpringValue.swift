// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import CoreGraphics
import Foundation
import SwiftUI

/// A number that follows its target with a spring, stepped by a display link
/// (design D12). A new target mid-flight keeps the current velocity, so a
/// quick second Cmd+S turns the motion around smoothly.
struct SpringValue {
  /// Tuned against Arc, whose sidebar slides in or out in about 0.15 s with
  /// hardly any bounce.
  static let spring = Spring(response: 0.2, dampingRatio: 0.9)
  /// The revealed sidebar's: Arc slides it in within about 0.1 s, with a
  /// slight overshoot.
  static let revealSpring = Spring(response: 0.14, dampingRatio: 0.8)

  let spring: Spring

  private(set) var value: CGFloat
  private(set) var target: CGFloat
  private(set) var isMoving = false
  private var from: CGFloat
  private var initialVelocity: CGFloat = 0
  private var start: TimeInterval = 0

  init(_ value: CGFloat, spring: Spring = SpringValue.spring) {
    self.spring = spring
    self.value = value
    target = value
    from = value
  }

  /// Starts moving towards `newTarget` at `time` (seconds, any monotonic clock).
  mutating func animate(to newTarget: CGFloat, at time: TimeInterval) {
    guard newTarget != target else { return }
    initialVelocity = isMoving ? velocity(at: time) : 0
    from = value
    target = newTarget
    start = time
    isMoving = true
  }

  /// Goes to `newTarget` at once.
  mutating func jump(to newTarget: CGFloat) {
    value = newTarget
    target = newTarget
    from = newTarget
    initialVelocity = 0
    isMoving = false
  }

  /// Moves to where the spring is at `time`; returns whether it still moves.
  @discardableResult
  mutating func step(at time: TimeInterval) -> Bool {
    guard isMoving else { return false }
    let elapsed = max(0, time - start)
    if elapsed >= spring.settlingDuration {
      jump(to: target)
      return false
    }
    value = from + spring.value(target: target - from, initialVelocity: initialVelocity, time: elapsed)
    return true
  }

  private func velocity(at time: TimeInterval) -> CGFloat {
    spring.velocity(target: target - from, initialVelocity: initialVelocity, time: max(0, time - start))
  }
}
