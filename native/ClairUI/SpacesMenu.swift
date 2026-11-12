// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost

/// The menu bar's Spaces menu, after View (add-spaces design D8): New Space…,
/// Rename Space, Manage Spaces…, Next Space (Opt+Cmd+Right), Previous Space
/// (Opt+Cmd+Left), then one item per Space, Ctrl+1 to Ctrl+9 for the first
/// nine, with a checkmark on the main window's. It's rebuilt whenever the
/// Spaces change, so the shortcuts follow their order. Its items act on the
/// main window and are off without a window that shows Spaces.
final class SpacesMenu: NSObject, NSMenuDelegate, NSMenuItemValidation, SpacesModelListener {
  static let title = "Spaces"

  let menu = NSMenu(title: SpacesMenu.title)
  let spaces: SpacesModel
  /// The window the items act on.
  var currentController: () -> BrowserWindowController? = { BrowserWindowController.main }

  enum Command: Int {
    case newSpace = 1
    case rename
    case manage
    case next
    case previous
    case space
  }

  init(spaces: SpacesModel) {
    self.spaces = spaces
    super.init()
    menu.delegate = self
    spaces.addListener(self)
    rebuild()
  }

  /// Adds the menu after View, once.
  @discardableResult
  func install(in mainMenu: NSMenu?) -> Bool {
    guard let mainMenu, !mainMenu.items.contains(where: { $0.submenu === menu }) else { return false }
    let item = NSMenuItem(title: Self.title, action: nil, keyEquivalent: "")
    item.submenu = menu
    let view = mainMenu.items.firstIndex { $0.submenu?.title == "View" || $0.title == "View" }
    mainMenu.insertItem(item, at: view.map { $0 + 1 } ?? min(mainMenu.numberOfItems, 4))
    return true
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    rebuild()
  }

  /// Rebuilds the items from the Spaces, with the main window's checked.
  func rebuild() {
    menu.removeAllItems()
    let shown = currentController()?.model.shownSpaceID
    add("New Space…", .newSpace)
    add("Rename Space", .rename)
    add("Manage Spaces…", .manage)
    menu.addItem(.separator())
    add("Next Space", .next, key: Self.arrow(NSRightArrowFunctionKey), modifiers: [.command, .option])
    add("Previous Space", .previous, key: Self.arrow(NSLeftArrowFunctionKey), modifiers: [.command, .option])
    if !spaces.spaces.isEmpty {
      menu.addItem(.separator())
    }
    for (index, space) in spaces.spaces.enumerated() {
      let item = add(
        SpacesLogic.label(of: space), .space, key: index < 9 ? String(index + 1) : "",
        modifiers: index < 9 ? [.control] : [])
      item.representedObject = space.spaceID
      item.state = space.spaceID == shown ? .on : .off
    }
  }

  @discardableResult
  private func add(
    _ title: String, _ command: Command, key: String = "", modifiers: NSEvent.ModifierFlags = []
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: key)
    item.keyEquivalentModifierMask = modifiers
    item.target = self
    item.tag = command.rawValue
    menu.addItem(item)
    return item
  }

  private static func arrow(_ key: Int) -> String {
    String(Character(UnicodeScalar(UInt16(key))!))
  }

  func validateMenuItem(_ item: NSMenuItem) -> Bool {
    guard let controller = currentController(), controller.model.showsSpaces else { return false }
    switch Command(rawValue: item.tag) {
    case .next, .previous: return controller.model.spaces.spaces.count > 1
    case .rename: return controller.model.shownSpace != nil
    default: return true
    }
  }

  @objc func choose(_ sender: NSMenuItem) {
    guard let controller = currentController(), controller.model.showsSpaces else { return }
    switch Command(rawValue: sender.tag) {
    case .newSpace: controller.beginNewSpace()
    case .rename: controller.beginRenamingSpace()
    case .manage: controller.manageSpaces()
    case .next: controller.showSpace(step: 1)
    case .previous: controller.showSpace(step: -1)
    case .space:
      if let spaceID = sender.representedObject as? SpaceID {
        controller.showSpace(spaceID)
      }
    case nil: break
    }
  }

  // MARK: SpacesModelListener

  func spacesDidChange() {
    rebuild()
  }

  func spaceTabsDidChange(_ spaceID: SpaceID) {}
  func spaceTabDidChange(_ tab: any ClairTab) {}
}
