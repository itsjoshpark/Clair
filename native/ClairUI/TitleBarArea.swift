// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import SwiftUI

/// What a double-click on a window's title bar does, as set in System
/// Settings › Desktop & Dock.
enum TitleBarDoubleClickAction {
  case zoom
  case fill
  case minimize
  case none

  init(preference: String?, legacyMinimize: Bool) {
    switch preference {
    case "Minimize": self = .minimize
    case "None": self = .none
    case "Fill": self = .fill
    case nil: self = legacyMinimize ? .minimize : .zoom
    default: self = .zoom
    }
  }

  /// The user's setting, from the global domain.
  static func current(defaults: UserDefaults = .standard) -> Self {
    Self(
      preference: defaults.string(forKey: "AppleActionOnDoubleClick"),
      legacyMinimize: defaults.bool(forKey: "AppleMiniaturizeOnDoubleClick"))
  }

  /// AppKit's Window › Fill, which has no public API.
  private static let fillSelector = Selector(("_zoomFill:"))

  func perform(on window: NSWindow) {
    switch self {
    case .zoom:
      window.performZoom(nil)
    case .fill:
      if window.responds(to: Self.fillSelector) {
        window.perform(Self.fillSelector, with: nil)
      } else {
        window.performZoom(nil)
      }
    case .minimize:
      window.performMiniaturize(nil)
    case .none:
      break
    }
  }
}

/// Part of the window's header that acts as its title bar: the inset above
/// the card and the sidebar's top row. The title bar is transparent, so
/// AppKit leaves double-clicks there alone; this view moves the window on a
/// press and calls `onDoubleClick` on a double-click.
final class TitleBarAreaView: NSView {
  var onDoubleClick: () -> Void = {}

  /// Moves the window itself rather than letting AppKit's title bar do it,
  /// so the double-click reaches `mouseDown`.
  override var mouseDownCanMoveWindow: Bool { false }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func mouseDown(with event: NSEvent) {
    if event.clickCount == 2 {
      onDoubleClick()
    } else if let window, !window.styleMask.contains(.fullScreen) {
      window.performDrag(with: event)
    }
  }
}

/// `TitleBarAreaView` for SwiftUI.
struct TitleBarArea: NSViewRepresentable {
  var onDoubleClick: () -> Void

  func makeNSView(context: Context) -> TitleBarAreaView {
    let view = TitleBarAreaView()
    view.onDoubleClick = onDoubleClick
    return view
  }

  func updateNSView(_ view: TitleBarAreaView, context: Context) {
    view.onDoubleClick = onDoubleClick
  }
}
