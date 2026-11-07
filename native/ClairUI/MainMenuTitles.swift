// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit

/// Titles of Chromium's menu items that read differently in Clair.
enum MainMenuTitles {
  /// Chromium's IDC_FOCUS_LOCATION, File > Open Location… (Cmd+L), which
  /// opens the command bar on the current URL.
  static let focusLocationTag = 39001
  /// "Location" alone is vague to most people.
  static let focusLocationTitle = "Open Location Bar"

  static func apply(to menu: NSMenu?) {
    guard let menu else { return }
    for item in menu.items {
      if item.tag == focusLocationTag {
        item.title = focusLocationTitle
      }
      apply(to: item.submenu)
    }
  }
}
