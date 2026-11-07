// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import Foundation

/// The sidebar's most recent width and hidden state, which new and restored
/// windows start with (design D12). Chromium's session doesn't record them.
struct SidebarPreferences {
  static let widthKey = "ClairSidebarWidth"
  static let hiddenKey = "ClairSidebarHidden"

  let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// The state a new window starts with.
  var initialState: SidebarState {
    let width = defaults.object(forKey: Self.widthKey) as? Double
    return SidebarState(
      width: width.map { CGFloat($0) } ?? SidebarState.defaultWidth,
      isHidden: defaults.bool(forKey: Self.hiddenKey))
  }

  /// Remembers a window's sidebar for the next new window.
  func remember(_ state: SidebarState) {
    defaults.set(Double(state.width), forKey: Self.widthKey)
    defaults.set(state.isHidden, forKey: Self.hiddenKey)
  }
}
