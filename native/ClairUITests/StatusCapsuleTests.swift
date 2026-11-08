// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import Testing

@testable import ClairUI

/// When the link status capsule shows and hides (design D18), against a fake
/// clock in seconds.
struct StatusCapsuleTests {
  /// `tick`, outside `#expect`, which can't call a mutating method.
  private func tick(_ state: inout StatusCapsuleState, at time: Double) -> Bool {
    state.tick(at: time)
  }

  @Test func showsAfterResting() {
    var state = StatusCapsuleState()
    state.report("https://a.example/", at: 0)
    #expect(!tick(&state, at: 0.4))
    #expect(state.shownText == nil)
    #expect(tick(&state, at: 0.5))
    #expect(state.shownText == "https://a.example/")
  }

  @Test func leavingBeforeItShowsCancelsIt() {
    var state = StatusCapsuleState()
    state.report("https://a.example/", at: 0)
    state.report(nil, at: 0.3)
    #expect(state.deadline == nil)
    #expect(!tick(&state, at: 1))
    #expect(state.shownText == nil)
  }

  @Test func movingBetweenLinksWhileWaitingShowsTheLatest() {
    var state = StatusCapsuleState()
    state.report("https://a.example/", at: 0)
    state.report("https://b.example/", at: 0.3)
    #expect(tick(&state, at: 0.5))
    #expect(state.shownText == "https://b.example/")
  }

  @Test func newLinkWhileShownUpdatesAtOnce() {
    var state = StatusCapsuleState()
    state.report("https://a.example/", at: 0)
    _ = state.tick(at: 0.5)
    state.report("https://b.example/", at: 1)
    #expect(state.shownText == "https://b.example/")
    #expect(state.deadline == nil)
  }

  @Test func hidesAfterLeaving() {
    var state = StatusCapsuleState()
    state.report("https://a.example/", at: 0)
    _ = state.tick(at: 0.5)
    state.report(nil, at: 1)
    #expect(!tick(&state, at: 1.4))
    #expect(state.shownText == "https://a.example/")
    #expect(tick(&state, at: 1.5))
    #expect(state.shownText == nil)
  }

  @Test func returningToALinkBeforeItHidesKeepsItShown() {
    var state = StatusCapsuleState()
    state.report("https://a.example/", at: 0)
    _ = state.tick(at: 0.5)
    state.report(nil, at: 1)
    state.report("https://b.example/", at: 1.2)
    #expect(!tick(&state, at: 2))
    #expect(state.shownText == "https://b.example/")
  }

  @Test func resetHidesAtOnce() {
    var state = StatusCapsuleState()
    state.report("https://a.example/", at: 0)
    _ = state.tick(at: 0.5)
    state.reset()
    #expect(state.shownText == nil)
    #expect(state.deadline == nil)
  }
}

/// Keys in the popup's text (design D18).
struct NoticeTextTests {
  @Test func markedKeyIsKept() {
    #expect(NoticePopupView.markingKeys(in: "To exit full screen, press |Esc|") == "To exit full screen, press |Esc|")
  }

  @Test func bareEscBecomesAKey() {
    #expect(NoticePopupView.markingKeys(in: "To exit full screen, press Esc") == "To exit full screen, press |Esc|")
    #expect(NoticePopupView.markingKeys(in: "Press and hold Esc to exit") == "Press and hold |Esc| to exit")
  }

  @Test func wordsContainingEscAreLeftAlone() {
    #expect(NoticePopupView.markingKeys(in: "Escape room") == "Escape room")
  }
}
