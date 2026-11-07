// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit

/// Whether a drag from the top of the page moves the window (design D4 of
/// `drag-window-from-page-top`). Read at each press, so a change applies to
/// open windows at once. The Settings window will show it as "Allow window
/// dragging from the top of webpages".
struct WindowDragPreference {
  static let key = "ClairDragWindowFromPageTop"

  let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    defaults.register(defaults: [Self.key: true])
  }

  var isEnabled: Bool {
    defaults.bool(forKey: Self.key)
  }
}

/// When a drag from the top of the page moves the window (design D1), as in
/// Arc: a press in the strip under the arrow cursor arms it, and the press's
/// first drag moves the window if the cursor is still the arrow. Any other
/// cursor (the I-beam over text, the hand over links, a page's own cursor)
/// leaves the drag to the page.
struct PageTopWindowDrag {
  /// Arc's strip: a press 58 pt below the page's top moves its window, one at
  /// 59 pt doesn't.
  static let stripHeight: CGFloat = 59

  /// A left mouse event seen by the strip's hit test.
  struct Event {
    enum Kind {
      case press
      case drag
    }

    var kind: Kind
    /// Shared by a press and its drags.
    var number: Int
    var isInStrip = true
    var clickCount = 1
    var hasModifiers = false
    var cursorIsArrow: Bool
  }

  /// The press whose first drag moves the window.
  private(set) var armedPress: Int?

  /// Takes in an event and says whether the window should move now. Both
  /// AppKit and Chromium hit-test a press, so a press may come in twice.
  mutating func handle(_ event: Event, isEnabled: Bool) -> Bool {
    switch event.kind {
    case .press:
      let arms = isEnabled && event.isInStrip && event.clickCount == 1 && !event.hasModifiers && event.cursorIsArrow
      armedPress = arms ? event.number : nil
      return false
    case .drag:
      guard let press = armedPress, press == event.number else { return false }
      armedPress = nil
      return isEnabled && event.cursorIsArrow
    }
  }
}

/// After the window server takes a window drag, drags that still reach the
/// app mean it didn't start: they're kept from the page, and so is the
/// release if they went more than 1 pt, so the page neither selects nor
/// clicks (design D1, step 3).
struct WindowDragSafetyNet {
  private(set) var distance = CGVector.zero

  mutating func drag(dx: CGFloat, dy: CGFloat) {
    distance.dx += abs(dx)
    distance.dy += abs(dy)
  }

  var keepsRelease: Bool {
    hypot(distance.dx, distance.dy) > 1
  }
}

/// A transparent strip over the top of the page (design D1 and D2). It never
/// takes a press: Chromium's page view hit-tests the window for every mouse
/// event, so the strip's hit test sees the press and its first drag, and
/// feeds them to `PageTopWindowDrag`.
final class PageTopDragStrip: NSView {
  /// Whether dragging from the top of the page is on for this window now.
  var isEnabled: () -> Bool = { false }
  /// Moves the window, from the drag event that started it.
  var onDragWindow: (NSEvent) -> Void = { _ in }

  private static let modifiers: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
  private var rule = PageTopWindowDrag()

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard !isHidden, let event = NSApp.currentEvent, event.window === window else { return nil }
    let kind: PageTopWindowDrag.Event.Kind
    switch event.type {
    case .leftMouseDown: kind = .press
    case .leftMouseDragged: kind = .drag
    default: return nil
    }
    let observed = PageTopWindowDrag.Event(
      kind: kind,
      number: event.eventNumber,
      isInStrip: bounds.contains(convert(event.locationInWindow, from: nil)),
      clickCount: event.clickCount,
      hasModifiers: !event.modifierFlags.intersection(Self.modifiers).isEmpty,
      cursorIsArrow: NSCursor.current === NSCursor.arrow)
    if rule.handle(observed, isEnabled: isEnabled()) {
      onDragWindow(event)
    }
    return nil
  }
}
