// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost

/// The menu bar's Extensions menu, left of Window, as in Arc
/// (arc-site-control-center design D11): the main browser window's extensions
/// from A to Z, then "Add Extension…" and "Manage Extensions…".
final class ExtensionsMenu: NSObject, NSMenuDelegate {
  static let title = "Extensions"
  static let iconSize = NSSize(width: 16, height: 16)

  let menu = NSMenu(title: ExtensionsMenu.title)
  /// The window whose extensions the menu lists when it opens.
  var currentController: () -> BrowserWindowController? = { BrowserWindowController.main }
  private weak var controller: BrowserWindowController?

  override init() {
    super.init()
    menu.delegate = self
    menu.autoenablesItems = false
  }

  /// Adds the menu before Window, once.
  @discardableResult
  func install(in mainMenu: NSMenu?) -> Bool {
    guard let mainMenu, !mainMenu.items.contains(where: { $0.submenu === menu }) else { return false }
    let item = NSMenuItem(title: Self.title, action: nil, keyEquivalent: "")
    item.submenu = menu
    let window =
      mainMenu.items.firstIndex { $0.submenu != nil && $0.submenu === NSApp.windowsMenu }
      ?? mainMenu.items.firstIndex { $0.title == "Window" } ?? mainMenu.numberOfItems
    mainMenu.insertItem(item, at: window)
    return true
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    update(from: currentController())
  }

  /// Rebuilds the items from a window's extensions.
  func update(from controller: BrowserWindowController?) {
    self.controller = controller
    menu.removeAllItems()
    for action in Self.ordered(controller?.model.extensionActions ?? []) {
      let item = NSMenuItem(title: action.name, action: #selector(chooseExtension(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = action.extensionID
      item.image = Self.icon(for: action)
      // As a dimmed tile ignores a click (design D4).
      item.isEnabled = action.isEnabled
      menu.addItem(item)
    }
    if menu.numberOfItems > 0 {
      menu.addItem(.separator())
    }
    for (title, url) in [
      ("Add Extension…", SiteControlCenterLink.webStore), ("Manage Extensions…", SiteControlCenterLink.extensions),
    ] {
      let item = NSMenuItem(title: title, action: #selector(openLink(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = url
      item.isEnabled = controller != nil
      menu.addItem(item)
    }
  }

  /// Every extension from A to Z, as people read names.
  static func ordered(_ actions: [any ClairExtensionAction]) -> [any ClairExtensionAction] {
    actions.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  static func icon(for action: any ClairExtensionAction) -> NSImage? {
    guard let icon = action.icon?.copy() as? NSImage else {
      return NSImage(systemSymbolName: "puzzlepiece.extension", accessibilityDescription: nil)
    }
    icon.size = iconSize
    return icon
  }

  /// Runs the action; its popup opens beside the site-controls button, as from
  /// the Site Control Center.
  @objc private func chooseExtension(_ sender: NSMenuItem) {
    guard let extensionID = sender.representedObject as? String else { return }
    controller?.runExtension(extensionID, pinned: false)
  }

  @objc private func openLink(_ sender: NSMenuItem) {
    guard let url = sender.representedObject as? URL else { return }
    controller?.openInNewTab(url)
  }
}
