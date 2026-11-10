// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Testing

@testable import ClairUI

/// The menu bar's Extensions menu (arc-site-control-center design D11).
@MainActor
struct ExtensionsMenuTests {
  func window(_ actions: [FakeExtensionAction]) -> (FakeBrowser, BrowserWindowController) {
    let browser = FakeBrowser()
    let controller = BrowserWindowController(
      browser: browser, preferences: SidebarPreferences(defaults: UserDefaults(suiteName: "ExtensionsMenuTests")!))
    browser.clairWindow = controller
    browser.addTab(title: "Page", url: "https://example.com/")
    browser.setExtensionActions(actions)
    return (browser, controller)
  }

  @Test func itGoesBeforeWindow() {
    let main = NSMenu()
    for title in ["Clair", "File", "Window", "Help"] {
      let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      item.submenu = NSMenu(title: title)
      main.addItem(item)
    }
    let extensions = ExtensionsMenu()
    #expect(extensions.install(in: main))
    #expect(main.items.map(\.title) == ["Clair", "File", "Extensions", "Window", "Help"])
    #expect(!extensions.install(in: main))
  }

  @Test func itListsExtensionsFromAToZThenTheLinks() {
    let (_, controller) = window([
      FakeExtensionAction(id: "z", name: "Zulu"),
      FakeExtensionAction(id: "u", name: "uBlock Origin Lite", pinned: false),
      FakeExtensionAction(id: "v", name: "Violentmonkey", enabled: false),
    ])
    let extensions = ExtensionsMenu()
    extensions.update(from: controller)
    let items = extensions.menu.items
    #expect(
      items.map(\.title) == ["uBlock Origin Lite", "Violentmonkey", "Zulu", "", "Add Extension…", "Manage Extensions…"])
    #expect(items[3].isSeparatorItem)
    #expect(items.filter { !$0.isSeparatorItem }.map(\.isEnabled) == [true, false, true, true, true])
    #expect(items[0].image != nil)
  }

  @Test func choosingAnExtensionOpensItFromTheSiteControls() {
    let (browser, controller) = window([FakeExtensionAction(id: "a", name: "Alpha")])
    let extensions = ExtensionsMenu()
    extensions.update(from: controller)
    extensions.menu.performActionForItem(at: 0)
    #expect(browser.commands.last == "runExtension a \(AnchorKind.siteControls.rawValue)")
  }

  @Test func manageExtensionsOpensChromiumsPage() {
    let (browser, controller) = window([])
    let extensions = ExtensionsMenu()
    extensions.update(from: controller)
    #expect(extensions.menu.items.map(\.title) == ["Add Extension…", "Manage Extensions…"])
    extensions.menu.performActionForItem(at: 1)
    #expect(browser.commands.last?.hasPrefix("open chrome://extensions ") == true)
  }

  @Test func withoutAWindowTheLinksAreUnavailable() {
    let extensions = ExtensionsMenu()
    extensions.update(from: nil)
    #expect(extensions.menu.items.map(\.title) == ["Add Extension…", "Manage Extensions…"])
    #expect(extensions.menu.items.allSatisfy { !$0.isEnabled })
  }
}
