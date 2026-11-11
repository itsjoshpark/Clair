// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import Foundation
import Testing

@testable import ClairUI

/// Reload turning into stop only once a load has run a while, as in Arc
/// (add-peek design D12).
@MainActor
struct ReloadStopTests {
  typealias Mode = ReloadStopMode
  private let delay = ReloadStopMode.stopDelay

  @Test func aQuickLoadNeverShowsStop() {
    var mode = Mode(doubleClickInterval: 0.5)
    mode.loadingChanged(true, now: 10)
    #expect(mode.visible == .reload)
    #expect(mode.nextDeadline == 10 + delay)
    mode.loadingChanged(false, now: 10.3)
    #expect(mode.nextDeadline == nil)
    mode.tick(now: 10 + delay)
    #expect(mode.visible == .reload)
  }

  @Test func aSlowLoadShowsStopAfterTheDelayAndReloadWhenItEnds() {
    var mode = Mode(doubleClickInterval: 0.5)
    mode.loadingChanged(true, now: 10)
    // Posted again while it waits: the delay still runs from the start.
    mode.loadingChanged(true, now: 10.4)
    mode.tick(now: 10 + delay - 0.01)
    #expect(mode.visible == .reload)
    mode.tick(now: 10 + delay)
    #expect(mode.visible == .stop)
    mode.loadingChanged(false, now: 12)
    #expect(mode.visible == .reload)
  }

  @Test func aPeekOpeningOnALoadingPageWaitsToo() {
    var mode = Mode(doubleClickInterval: 0.5)
    mode.tabSwitched(isLoading: true, now: 10)
    #expect(mode.visible == .reload)
    mode.tick(now: 10 + delay)
    #expect(mode.visible == .stop)
  }

  @Test func switchingBetweenLoadingTabsKeepsStop() {
    var mode = Mode(doubleClickInterval: 0.5)
    mode.loadingChanged(true, now: 10)
    mode.tick(now: 10 + delay)
    mode.tabSwitched(isLoading: true, now: 12)
    #expect(mode.visible == .stop)
    mode.tabSwitched(isLoading: false, now: 13)
    #expect(mode.visible == .reload)
    #expect(mode.nextDeadline == nil)
  }

  @Test func leavingTheButtonDoesNotSkipTheDelay() {
    var mode = Mode(doubleClickInterval: 0.5)
    mode.pointerEntered()
    mode.loadingChanged(true, now: 10)
    mode.pointerExited(now: 10.2)
    #expect(mode.visible == .reload)
    mode.tick(now: 10 + delay)
    #expect(mode.visible == .stop)
  }
}
