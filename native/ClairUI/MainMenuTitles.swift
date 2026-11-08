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

  /// Edit > Copy URL's action, which the native window's root view answers
  /// through the responder chain, showing Arc's "Copied Current URL".
  static let copyURLAction = #selector(BrowserRootView.copyCurrentURL(_:))

  /// Adds Edit > Copy URL (Shift+Cmd+C) after Copy, as in Arc (design D18),
  /// and returns it. `copy-url-shortcut.patch` frees Shift+Cmd+C from
  /// Chromium's own table, where it inspected an element.
  @discardableResult
  static func addCopyURL(to menu: NSMenu?) -> NSMenuItem? {
    guard let menu else { return nil }
    for item in menu.items {
      guard let submenu = item.submenu else { continue }
      if let copy = submenu.items.firstIndex(where: { $0.action == #selector(NSText.copy(_:)) }) {
        if let existing = submenu.items.first(where: { $0.action == copyURLAction }) {
          return existing
        }
        let copyURL = NSMenuItem(title: "Copy URL", action: copyURLAction, keyEquivalent: "c")
        copyURL.keyEquivalentModifierMask = [.command, .shift]
        submenu.insertItem(copyURL, at: copy + 1)
        return copyURL
      }
      if let found = addCopyURL(to: submenu) {
        return found
      }
    }
    return nil
  }

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
