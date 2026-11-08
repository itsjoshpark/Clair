// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import SwiftUI

/// One open back or forward menu (arc-navigation-feedback design D3): a
/// native menu of the active tab's pages in that direction, nearest first,
/// each with its favicon and title, from Chromium's `BackForwardMenuModel`
/// through a `ClairHistoryMenu` session. Favicons that arrive while the menu
/// is open replace the placeholder in place.
final class HistoryMenuBuilder: NSObject, ClairHistoryMenuDelegate, NSMenuDelegate {
  static let iconSize = NSSize(width: 16, height: 16)
  /// What a page without a favicon yet shows, so titles stay aligned.
  static let placeholderIcon: NSImage = {
    let image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil) ?? NSImage()
    image.size = iconSize
    return image
  }()

  let menu = NSMenu()
  private var session: (any ClairHistoryMenu)?
  /// Whether Cmd is held as an item is chosen; tests replace it.
  var isCommandKeyDown: () -> Bool = { NSApp.currentEvent?.modifierFlags.contains(.command) == true }

  /// Starts a session for the active tab, or returns nil when the tab can't
  /// go that way.
  init?(browser: any ClairBrowser, direction: HistoryDirection) {
    super.init()
    guard let session = browser.startHistoryMenu(direction: direction, delegate: self) else { return nil }
    self.session = session
    menu.autoenablesItems = false
    menu.delegate = self
    rebuild(Self.pages(session.items))
    if menu.items.isEmpty {
      close()
      return nil
    }
  }

  /// The items the menu shows: the tab's pages.
  private static func pages(_ items: [any ClairHistoryItem]) -> [any ClairHistoryItem] {
    items.filter { $0.kind == .page }
  }

  private func rebuild(_ pages: [any ClairHistoryItem]) {
    menu.removeAllItems()
    for page in pages {
      let item = NSMenuItem(title: page.title, action: #selector(choose(_:)), keyEquivalent: "")
      item.target = self
      item.tag = page.itemID
      item.image = Self.icon(page.icon)
      item.toolTip = page.url?.absoluteString
      menu.addItem(item)
    }
  }

  private static func icon(_ favicon: NSImage?) -> NSImage {
    guard let favicon, let copy = favicon.copy() as? NSImage else { return placeholderIcon }
    copy.size = iconSize
    return copy
  }

  // MARK: ClairHistoryMenuDelegate

  func historyMenu(_ menu: any ClairHistoryMenu, itemsDidChange items: [any ClairHistoryItem]) {
    guard session === menu else { return }
    let pages = Self.pages(items)
    if pages.isEmpty {
      // The tab can no longer go that way, or another tab became active.
      self.menu.cancelTracking()
      return
    }
    if pages.map(\.itemID) == self.menu.items.map(\.tag) {
      // A favicon arrived: update the open menu in place.
      for (item, page) in zip(self.menu.items, pages) {
        item.title = page.title
        item.image = Self.icon(page.icon)
      }
    } else {
      rebuild(pages)
    }
  }

  // MARK: Choosing

  @objc func choose(_ sender: NSMenuItem) {
    session?.open(item: sender.tag, disposition: isCommandKeyDown() ? .newBackgroundTab : .currentTab)
    session = nil
  }

  func close() {
    session?.close()
    session = nil
  }

  // MARK: NSMenuDelegate

  func menuDidClose(_ menu: NSMenu) {
    // AppKit sends the chosen item's action after this; end the session once
    // it has had its chance.
    DispatchQueue.main.async { [weak self] in
      self?.close()
    }
  }
}

/// Lies over the back or forward button: a right click or a Control-click
/// opens the history menu under the button. Every other click goes through
/// to the button.
struct HistoryButtonCatcher: NSViewRepresentable {
  let isEnabled: Bool
  let makeMenu: () -> HistoryMenuBuilder?

  func makeNSView(context: Context) -> CatcherView {
    let view = CatcherView()
    updateNSView(view, context: context)
    return view
  }

  func updateNSView(_ view: CatcherView, context: Context) {
    view.isEnabled = isEnabled
    view.makeMenu = makeMenu
  }

  final class CatcherView: NSView {
    var isEnabled = false
    var makeMenu: (() -> HistoryMenuBuilder?)?
    private var openMenu: HistoryMenuBuilder?

    override func hitTest(_ point: NSPoint) -> NSView? {
      guard isEnabled, let event = NSApp.currentEvent else { return nil }
      switch event.type {
      case .rightMouseDown, .rightMouseUp:
        return super.hitTest(point)
      case .leftMouseDown where event.modifierFlags.contains(.control):
        return super.hitTest(point)
      default:
        return nil
      }
    }

    override func rightMouseDown(with event: NSEvent) {
      showMenu()
    }

    override func mouseDown(with event: NSEvent) {
      // Only a Control-click gets here.
      showMenu()
    }

    private func showMenu() {
      guard let builder = makeMenu?() else { return }
      openMenu = builder
      builder.menu.popUp(positioning: nil, at: NSPoint(x: 0, y: isFlipped ? bounds.maxY + 4 : -4), in: self)
    }
  }
}
