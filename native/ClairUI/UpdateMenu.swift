// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit

/// The one update item in the Clair menu.
final class UpdateMenu: NSObject {
  static let checkTitle = "Check for Updates…"
  static let availableTitle = "Update Available…"
  static let badgeText = "1 update"

  let item = NSMenuItem(title: UpdateMenu.checkTitle, action: #selector(choose), keyEquivalent: "")
  private let onChoose: () -> Void

  init(onChoose: @escaping () -> Void) {
    self.onChoose = onChoose
    super.init()
    item.target = self
  }

  /// Adds the item below About Clair, the first item of the application menu.
  func install(in mainMenu: NSMenu?) {
    guard let appMenu = mainMenu?.items.first?.submenu else {
      NativeLayer.logger.error("There's no application menu to add the update item to")
      return
    }
    appMenu.insertItem(item, at: min(1, appMenu.numberOfItems))
  }

  func setUpdateWaiting(_ waiting: Bool) {
    item.title = waiting ? Self.availableTitle : Self.checkTitle
    item.badge = waiting ? NSMenuItemBadge(string: Self.badgeText) : nil
  }

  @objc private func choose() {
    onChoose()
  }
}
// Throwaway: a Swift-only pull request for task 11.1. Never merged.
