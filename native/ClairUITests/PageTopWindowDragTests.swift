// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import Testing

@testable import ClairUI

/// The core rule for dragging the window from the top of the page
/// (browser-window spec, "Dragging the window from the top of the page").
/// The owner keeps these to the core rule; the rest is checked by hand.
struct PageTopWindowDragTests {
  @Test func dragUnderTheArrowMovesTheWindow() {
    var rule = PageTopWindowDrag()
    let press = rule.handle(.init(kind: .press, number: 7, cursorIsArrow: true), isEnabled: true)
    let drag = rule.handle(.init(kind: .drag, number: 7, cursorIsArrow: true), isEnabled: true)
    let laterDrag = rule.handle(.init(kind: .drag, number: 7, cursorIsArrow: true), isEnabled: true)
    #expect(!press && drag && !laterDrag)
  }

  @Test func dragUnderAnotherCursorStaysWithThePage() {
    var rule = PageTopWindowDrag()
    _ = rule.handle(.init(kind: .press, number: 7, cursorIsArrow: false), isEnabled: true)
    let overText = rule.handle(.init(kind: .drag, number: 7, cursorIsArrow: false), isEnabled: true)
    // The page set its own cursor on the first movement.
    _ = rule.handle(.init(kind: .press, number: 8, cursorIsArrow: true), isEnabled: true)
    let cursorChanged = rule.handle(.init(kind: .drag, number: 8, cursorIsArrow: false), isEnabled: true)
    #expect(!overText && !cursorChanged)
  }

  @Test func clickDoesNotArmALaterPress() {
    var rule = PageTopWindowDrag()
    _ = rule.handle(.init(kind: .press, number: 7, cursorIsArrow: true), isEnabled: true)
    // A later press below the strip, dragged up into it, belongs to the page.
    _ = rule.handle(.init(kind: .press, number: 8, isInStrip: false, cursorIsArrow: true), isEnabled: true)
    let drag = rule.handle(.init(kind: .drag, number: 8, cursorIsArrow: true), isEnabled: true)
    #expect(!drag && rule.armedPress == nil)
  }
}
