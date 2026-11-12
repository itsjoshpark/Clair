// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import Testing

@testable import ClairUI

@MainActor
struct SettingsWindowTests {
  private let defaults: UserDefaults = {
    let name = "ClairUITests.Settings.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
  }()

  /// Chromium's application menu, with its Settings item as main_menu_builder.mm makes it.
  private func appMenu(settingsTag: Int = SettingsWindowController.menuTag) -> (NSMenu, NSMenuItem) {
    let main = NSMenu()
    let app = NSMenu(title: "Clair")
    app.addItem(withTitle: "About Clair", action: nil, keyEquivalent: "")
    app.addItem(.separator())
    let settings = app.addItem(
      withTitle: "Preferences...", action: NSSelectorFromString("showPreferences:"), keyEquivalent: ",")
    settings.tag = settingsTag
    app.addItem(withTitle: "Quit Clair", action: nil, keyEquivalent: "q")
    main.addItem(withTitle: "Clair", action: nil, keyEquivalent: "").submenu = app
    return (main, settings)
  }

  private func choose(_ item: NSMenuItem) throws {
    NSApplication.shared.sendAction(try #require(item.action), to: item.target, from: item)
  }

  @Test func settingsOpensClairsWindow() throws {
    let (main, item) = appMenu()
    let settings = SettingsWindowController(host: FakeHost(), defaults: defaults)
    #expect(settings.install(in: main))
    #expect(item.title == "Settings…")
    #expect(item.keyEquivalent == ",")
    #expect(item.target === settings)

    #expect(settings.window == nil)
    try choose(item)
    let window = try #require(settings.window)
    #expect(window.isVisible)
    #expect(window.title == "General")

    window.close()
    try choose(item)
    #expect(settings.window === window)
    #expect(window.isVisible)
    window.close()
  }

  @Test func aMenuWithoutTheItemIsLeftToChromium() throws {
    let (main, item) = appMenu(settingsTag: 0)
    let settings = SettingsWindowController(host: FakeHost(), defaults: defaults)
    #expect(!settings.install(in: main))
    #expect(item.title == "Preferences...")
    #expect(item.target == nil)
  }

  @Test func opensOnThePageLastShown() throws {
    defaults.set(SettingsPage.advanced.rawValue, forKey: SettingsPage.key)
    let settings = SettingsWindowController(host: FakeHost(), defaults: defaults)
    settings.show()
    let window = try #require(settings.window)
    #expect(window.title == "Advanced")
    let tabs = try #require(window.contentViewController as? NSTabViewController)
    #expect(tabs.tabViewItems.map(\.label) == ["General", "Links", "Advanced"])

    tabs.selectedTabViewItemIndex = 0
    #expect(window.title == "General")
    #expect(SettingsPage.stored(in: defaults) == .general)
    window.close()
  }

  @Test func aMissingOrUnknownPageOpensGeneral() {
    #expect(SettingsPage.stored(in: defaults) == .general)
    defaults.set("privacy", forKey: SettingsPage.key)
    #expect(SettingsPage.stored(in: defaults) == .general)
  }

  @Test func linksSitsBetweenGeneralAndAdvanced() {
    #expect(SettingsPage.allCases == [.general, .links, .advanced])
    #expect(SettingsPage.links.label == "Links")
  }

  @Test func peekOnShiftClickIsOnUntilTurnedOff() {
    #expect(PeekPreference(defaults: defaults).isEnabled)
    defaults.set(false, forKey: PeekPreference.key)
    #expect(!PeekPreference(defaults: defaults).isEnabled)
    defaults.set(true, forKey: PeekPreference.key)
    #expect(PeekPreference(defaults: defaults).isEnabled)
  }

  @Test func theWindowAnswersFromThePreferenceLive() {
    let browser = FakeBrowser()
    let controller = BrowserWindowController(
      browser: browser, spaces: browser.spaces, preferences: SidebarPreferences(defaults: defaults),
      peekPreference: PeekPreference(defaults: defaults))
    #expect(controller.opensPeekOnShiftClick)
    defaults.set(false, forKey: PeekPreference.key)
    #expect(!controller.opensPeekOnShiftClick)
  }

  @Test func linksOpensOnItsPage() throws {
    defaults.set(SettingsPage.links.rawValue, forKey: SettingsPage.key)
    let settings = SettingsWindowController(host: FakeHost(), defaults: defaults)
    settings.show()
    let window = try #require(settings.window)
    #expect(window.title == "Links")
    window.close()
  }

  @Test func moreSettingsOpensChromiumsSettingsAndCloses() throws {
    let host = FakeHost()
    let settings = SettingsWindowController(host: host, defaults: defaults)
    settings.show()
    let window = try #require(settings.window)
    settings.openMoreSettings()
    #expect(host.openedURLs.map(\.absoluteString) == ["chrome://settings"])
    #expect(!window.isVisible)
  }
}
