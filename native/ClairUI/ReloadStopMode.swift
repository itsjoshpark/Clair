// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import Foundation
import Observation

/// What the reload button shows, following Chromium's Views `ReloadButton`
/// (arc-navigation-feedback design D2). It's free of AppKit: the caller
/// passes the time, and calls `tick(now:)` at `nextDeadline`.
///
/// - When a load ends while the pointer is on stop, the button stays stop but
///   disabled until the pointer leaves or `modeSwitchDelay` passes, so a
///   second click doesn't reload by accident.
/// - Within the double-click interval after a reload click, a load starting
///   under the pointer doesn't turn the button into stop until the interval
///   ends, so a double click doesn't stop the reload it just started.
/// - A forced change, such as a tab switch, applies at once, except that
///   reload turns into stop only once the load has run for `stopDelay`, as
///   in Arc, so a page that loads quickly, or a Peek that opens on one, never
///   flashes stop (add-peek design D12).
struct ReloadStopMode: Equatable {
  enum Mode: Equatable {
    case reload
    case stop
  }

  /// What a click on the button runs.
  enum Command: Equatable {
    case reload
    case stop
  }

  /// Chromium's `mode_switch_timer_delay_`.
  static let modeSwitchDelay: TimeInterval = 1.35
  /// How long a load runs before reload turns into stop: about 770 ms in Arc,
  /// measured from a Peek's Shift+click.
  static let stopDelay: TimeInterval = 0.75

  /// The system's double-click interval.
  let doubleClickInterval: TimeInterval

  private(set) var visible: Mode = .reload
  private(set) var isEnabled = true
  private var intended: Mode = .reload
  private var isHovered = false
  /// When the double-click timer and the stop-to-reload timer fire, while
  /// they run.
  private var doubleClickDeadline: TimeInterval?
  private var modeSwitchDeadline: TimeInterval?
  /// When the active tab's load began, while it loads, and when it has run
  /// for `stopDelay`, while reload waits to turn into stop.
  private var loadStart: TimeInterval?
  private var stopDeadline: TimeInterval?

  init(doubleClickInterval: TimeInterval) {
    self.doubleClickInterval = doubleClickInterval
  }

  /// When `tick(now:)` should next run, or nil while no timer runs.
  var nextDeadline: TimeInterval? {
    [doubleClickDeadline, modeSwitchDeadline, stopDeadline].compactMap { $0 }.min()
  }

  /// The tab's `isLoading` changed, or was posted again.
  mutating func loadingChanged(_ isLoading: Bool, now: TimeInterval) {
    setLoading(isLoading, now: now)
    change(to: isLoading ? .stop : .reload, force: false, now: now)
  }

  /// Another tab became active: show its state at once. A tab that's still
  /// loading shows stop at once while stop shows already, and otherwise once
  /// its load has run `stopDelay` from the switch, since the snapshot doesn't
  /// say when the load began: a Peek's opens with its tab.
  mutating func tabSwitched(isLoading: Bool, now: TimeInterval) {
    if isLoading && visible == .stop {
      loadStart = now - Self.stopDelay
    } else {
      loadStart = nil
      setLoading(isLoading, now: now)
    }
    change(to: isLoading ? .stop : .reload, force: true, now: now)
  }

  private mutating func setLoading(_ isLoading: Bool, now: TimeInterval) {
    if !isLoading {
      loadStart = nil
      stopDeadline = nil
    } else if loadStart == nil {
      loadStart = now
    }
  }

  mutating func pointerEntered() {
    isHovered = true
  }

  mutating func pointerExited(now: TimeInterval) {
    isHovered = false
    change(to: intended, force: true, now: now)
  }

  /// The button was clicked. Returns what to run, or nil when the click does
  /// nothing: the button is disabled, or it's the second click of a reload's
  /// double click.
  mutating func press(now: TimeInterval) -> Command? {
    guard isEnabled else { return nil }
    if visible == .stop {
      // The user has clicked, so the button may change under the pointer.
      change(to: .reload, force: true, now: now)
      return .stop
    }
    if doubleClickDeadline != nil {
      return nil
    }
    // Chromium leaves `intended` alone: the load that starts says stop.
    doubleClickDeadline = now + doubleClickInterval
    return .reload
  }

  /// Runs the timers that are due.
  mutating func tick(now: TimeInterval) {
    if let deadline = doubleClickDeadline, deadline <= now {
      doubleClickDeadline = nil
      change(to: intended, force: false, now: now)
    }
    if let deadline = modeSwitchDeadline, deadline <= now {
      modeSwitchDeadline = nil
      change(to: intended, force: true, now: now)
    }
    if let deadline = stopDeadline, deadline <= now {
      stopDeadline = nil
      change(to: intended, force: false, now: now)
    }
  }

  /// `ReloadButton::ChangeMode`.
  private mutating func change(to mode: Mode, force: Bool, now: TimeInterval) {
    intended = mode
    // Reload waits for a load to run `stopDelay` before turning into stop.
    if mode == .stop, visible == .reload, let loadStart, now - loadStart < Self.stopDelay {
      stopDeadline = loadStart + Self.stopDelay
      return
    }
    let safe = mode == .stop ? doubleClickDeadline == nil : visible != .stop
    if force || !isHovered || safe {
      doubleClickDeadline = nil
      modeSwitchDeadline = nil
      visible = mode
      isEnabled = true
    } else if visible != .reload {
      // Held as a disabled stop until the pointer leaves or the delay ends.
      isEnabled = false
      if modeSwitchDeadline == nil {
        modeSwitchDeadline = now + Self.modeSwitchDelay
      }
    }
  }
}

/// The window's `ReloadStopMode`, with a timer for its deadlines and the
/// system clock.
@MainActor
@Observable
final class ReloadStopState {
  private(set) var mode: ReloadStopMode
  @ObservationIgnored private var timer: Timer?
  @ObservationIgnored private let clock: () -> TimeInterval

  init(doubleClickInterval: TimeInterval, clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime })
  {
    mode = ReloadStopMode(doubleClickInterval: doubleClickInterval)
    self.clock = clock
  }

  func loadingChanged(_ isLoading: Bool) { update { $0.loadingChanged(isLoading, now: $1) } }
  func tabSwitched(isLoading: Bool) { update { $0.tabSwitched(isLoading: isLoading, now: $1) } }
  func pointerEntered() { update { mode, _ in mode.pointerEntered() } }
  func pointerExited() { update { $0.pointerExited(now: $1) } }

  func press() -> ReloadStopMode.Command? {
    var command: ReloadStopMode.Command?
    update { command = $0.press(now: $1) }
    return command
  }

  private func update(_ change: (inout ReloadStopMode, TimeInterval) -> Void) {
    var next = mode
    change(&next, clock())
    if next != mode {
      mode = next
    }
    schedule()
  }

  private func schedule() {
    timer?.invalidate()
    timer = nil
    guard let deadline = mode.nextDeadline else { return }
    let timer = Timer(timeInterval: max(0, deadline - clock()), repeats: false) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.update { $0.tick(now: $1) }
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }
}
