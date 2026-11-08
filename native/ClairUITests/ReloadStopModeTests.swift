// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import Foundation
import Testing

@testable import ClairUI

/// The reload button's hold, as Chromium's Views `ReloadButton` does it
/// (arc-navigation-feedback design D2).
@MainActor
struct ReloadStopModeTests {
  private func loading(hovered: Bool) -> ReloadStopMode {
    var mode = ReloadStopMode(doubleClickInterval: 0.5)
    mode.loadingChanged(true, now: 0)
    if hovered {
      mode.pointerEntered()
    }
    return mode
  }

  @Test func followsLoadingWithoutThePointer() {
    var mode = loading(hovered: false)
    #expect(mode.visible == .stop)
    mode.loadingChanged(false, now: 1)
    #expect(mode.visible == .reload)
    #expect(mode.isEnabled)
    #expect(mode.nextDeadline == nil)
  }

  @Test func holdsStopUnderThePointerUntilItLeaves() {
    var mode = loading(hovered: true)
    mode.loadingChanged(false, now: 1)
    #expect(mode.visible == .stop)
    #expect(!mode.isEnabled)
    #expect(mode.press(now: 1.1) == nil)
    mode.pointerExited(now: 1.2)
    #expect(mode.visible == .reload)
    #expect(mode.isEnabled)
    #expect(mode.nextDeadline == nil)
  }

  @Test func holdEndsAfterTheModeSwitchDelay() {
    var mode = loading(hovered: true)
    mode.loadingChanged(false, now: 1)
    #expect(mode.nextDeadline == 1 + ReloadStopMode.modeSwitchDelay)
    // Repeated posts of the same state don't restart the timer.
    mode.loadingChanged(false, now: 2)
    #expect(mode.nextDeadline == 1 + ReloadStopMode.modeSwitchDelay)
    mode.tick(now: 2.3)
    #expect(mode.visible == .stop)
    mode.tick(now: 1 + ReloadStopMode.modeSwitchDelay)
    #expect(mode.visible == .reload)
    #expect(mode.isEnabled)
  }

  @Test func loadStartingAgainEndsTheHold() {
    var mode = loading(hovered: true)
    mode.loadingChanged(false, now: 1)
    mode.loadingChanged(true, now: 1.5)
    #expect(mode.visible == .stop)
    #expect(mode.isEnabled)
    #expect(mode.nextDeadline == nil)
  }

  @Test func clickingStopStopsAndShowsReloadUnderThePointer() {
    var mode = loading(hovered: true)
    #expect(mode.press(now: 1) == .stop)
    #expect(mode.visible == .reload)
    #expect(mode.isEnabled)
  }

  @Test func doubleClickOnReloadDoesNotStop() {
    var mode = ReloadStopMode(doubleClickInterval: 0.5)
    mode.pointerEntered()
    #expect(mode.press(now: 0) == .reload)
    // The load the click started says stop, within the double-click interval.
    mode.loadingChanged(true, now: 0.05)
    #expect(mode.visible == .reload)
    // The second click of the double click does nothing.
    #expect(mode.press(now: 0.2) == nil)
    #expect(mode.nextDeadline == 0.5)
    mode.tick(now: 0.5)
    #expect(mode.visible == .stop)
  }

  @Test func doubleClickIntervalDoesNotDelayStopWithoutThePointer() {
    var mode = ReloadStopMode(doubleClickInterval: 0.5)
    #expect(mode.press(now: 0) == .reload)
    mode.loadingChanged(true, now: 0.05)
    #expect(mode.visible == .stop)
  }

  @Test func tabSwitchAppliesAtOnce() {
    var mode = loading(hovered: true)
    mode.loadingChanged(false, now: 1)
    #expect(!mode.isEnabled)
    mode.tabSwitched(isLoading: false, now: 1.1)
    #expect(mode.visible == .reload)
    #expect(mode.isEnabled)
    mode.tabSwitched(isLoading: true, now: 1.2)
    #expect(mode.visible == .stop)
  }
}
