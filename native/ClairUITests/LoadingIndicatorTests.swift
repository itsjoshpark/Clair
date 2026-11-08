// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import Foundation
import Testing

@testable import ClairUI

/// Arc's timed loading capsule (arc-navigation-feedback design D4).
@MainActor
struct LoadingIndicatorTests {
  typealias Model = LoadingIndicatorModel

  private func loading(at start: TimeInterval = 10) -> Model {
    var model = Model()
    model.loadingChanged(true, now: start)
    return model
  }

  @Test func drawsNothingWhileIdle() {
    #expect(Model().frame(at: 5) == nil)
    #expect(!Model().isAnimating(at: 5))
  }

  @Test func pulsesFromTheStartOfAVisibleLoad() throws {
    let model = loading()
    let start = try #require(model.frame(at: 10))
    #expect(start.width == Model.pulseWidth)
    #expect(start.fillOpacity == 0)
    #expect(start.trackOpacity == 0)
    // The peak, half way through the visible part of the first pulse.
    let peak = try #require(model.frame(at: 10 + Model.pulseVisible / 2))
    #expect(abs(peak.fillOpacity - Model.pulseOpacity) < 0.001)
    #expect(abs(peak.width - Model.pulsePeakWidth) < 0.001)
    // Hidden between pulses, then the second pulse.
    #expect(try #require(model.frame(at: 10 + 1.5)).fillOpacity == 0)
    #expect(try #require(model.frame(at: 10 + Model.pulseCycle + Model.pulseVisible / 2)).fillOpacity > 0.7)
    #expect(model.isAnimating(at: 11))
  }

  @Test func repeatedPostsDoNotRestartTheLoad() throws {
    var model = loading()
    model.loadingChanged(true, now: 11)
    #expect(model.loadStart == 10)
  }

  @Test func switchesToTheSweepAfterTwoPulses() throws {
    let model = loading()
    let sweepStart = 10 + Model.pulseCycle * Double(Model.pulses)
    let widened = try #require(model.frame(at: sweepStart + Model.widening))
    #expect(widened.width == Model.trackWidth)
    #expect(abs(widened.trackOpacity - Model.trackOpacity) < 0.001)
    // The fill grows from the left, then its left edge follows.
    let growing = try #require(model.frame(at: sweepStart + Model.sweepGrow / 2))
    #expect(growing.fillStart == 0)
    #expect(growing.fillEnd > 0.3 && growing.fillEnd < 0.7)
    let retracting = try #require(model.frame(at: sweepStart + Model.sweepGrow + Model.sweepRetract / 2))
    #expect(retracting.fillEnd == 1)
    #expect(retracting.fillStart > 0.3 && retracting.fillStart < 0.7)
    // Then the track stays empty until the next sweep.
    let empty = try #require(model.frame(at: sweepStart + Model.sweepCycle - 0.1))
    #expect(empty.fillOpacity == 0)
    #expect(empty.width == Model.trackWidth)
    let next = try #require(model.frame(at: sweepStart + Model.sweepCycle * 3 + Model.sweepGrow / 2))
    #expect(next.fillEnd > 0.3 && next.fillEnd < 0.7)
  }

  @Test func finishingFlashesThenShrinksAway() throws {
    var model = loading()
    model.loadingChanged(false, now: 16)
    let flash = try #require(model.frame(at: 16))
    #expect(flash.fillStart == 0 && flash.fillEnd == 1)
    #expect(flash.fillOpacity == Model.fillOpacity)
    #expect(flash.width == Model.trackWidth)
    let shrinking = try #require(model.frame(at: 16 + Model.finish / 2))
    #expect(shrinking.width < flash.width)
    #expect(shrinking.fillOpacity < flash.fillOpacity)
    #expect(model.frame(at: 16 + Model.finish) == nil)
    #expect(!model.isAnimating(at: 16 + Model.finish))
  }

  @Test func stoppingFinishesTheSameWay() throws {
    // A stopped load reports isLoading false, as a finished one does.
    var model = loading()
    model.loadingChanged(false, now: 11)
    let flash = try #require(model.frame(at: 11))
    #expect(flash.fillOpacity == Model.fillOpacity)
    #expect(flash.width < Model.pulsePeakWidth + 0.001)
  }

  @Test func aLoadThatEndsAtOnceDrawsNothing() {
    var model = loading()
    model.loadingChanged(false, now: 10.05)
    #expect(model.frame(at: 10.05) == nil)
    #expect(!model.isAnimating(at: 10.05))
  }

  @Test func tabSwitchShowsTheNewTabAtOnce() throws {
    var model = loading()
    // To an idle tab: nothing, with no finish animation.
    model.tabSwitched(isLoading: false, now: 15)
    #expect(model.frame(at: 15) == nil)
    // To a loading tab: it pulses from the switch.
    model.tabSwitched(isLoading: true, now: 20)
    #expect(model.loadStart == 20)
    #expect(try #require(model.frame(at: 20 + Model.pulseVisible / 2)).fillOpacity > 0.7)
  }
}
