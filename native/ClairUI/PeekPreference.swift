// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import Foundation
import Observation

/// Whether Shift+clicking a link opens a Peek (add-peek design D10). On
/// unless the user turned it off on Settings' Links page; Chromium reads it
/// each time a link opens, so a change applies to open windows at once.
struct PeekPreference {
  static let key = "ClairPeekOnShiftClick"

  let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    defaults.register(defaults: [Self.key: true])
  }

  var isEnabled: Bool {
    defaults.bool(forKey: Self.key)
  }
}

/// When the Peek's Close button shows Confirm (add-peek design D6): for as
/// long as Chromium says another Esc closes the Peek, after the page kept one.
@Observable
final class PeekConfirmState {
  private(set) var isShowing = false
  private var hideTask: Task<Void, Never>?
  /// Waits out Confirm's time; tests replace it so they don't depend on the
  /// clock.
  @ObservationIgnored var wait: (TimeInterval) async -> Void = { duration in
    try? await Task.sleep(for: .seconds(duration))
  }

  func show(for duration: TimeInterval) {
    isShowing = true
    hideTask?.cancel()
    let wait = self.wait
    hideTask = Task { [weak self] in
      await wait(duration)
      guard !Task.isCancelled else { return }
      self?.isShowing = false
    }
  }

  func hide() {
    hideTask?.cancel()
    hideTask = nil
    isShowing = false
  }
}
