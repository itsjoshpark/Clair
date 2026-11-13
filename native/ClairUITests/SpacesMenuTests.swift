// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Testing

@testable import ClairUI

/// The menu bar's Spaces menu (add-spaces D8).
@MainActor
struct SpacesMenuTests {
  func make(_ names: [String] = ["Work", "Travel"], suite: String = #function)
    -> (FakeHost, FakeBrowser, BrowserWindowController, SpacesMenu)
  {
    let (host, browser, controller) = spacesWindow(names, suite: suite)
    let menu = SpacesMenu(spaces: controller.model.spaces)
    menu.currentController = { controller }
    menu.rebuild()
    return (host, browser, controller, menu)
  }

  func item(_ menu: SpacesMenu, _ title: String) -> NSMenuItem? {
    menu.menu.items.first { $0.title == title }
  }

  @Test func listsTheCommandsThenEverySpace() {
    let (_, _, _, menu) = make()
    let titles = menu.menu.items.map { $0.isSeparatorItem ? "-" : $0.title }
    #expect(
      titles == [
        "New Space…", "Rename Space", "Change Profile", "Manage Spaces…", "-", "Next Space", "Previous Space", "-", "Home", "Work",
        "Travel",
      ])
  }

  @Test func shortcutsAreArcs() throws {
    let (_, _, _, menu) = make()
    let next = try #require(item(menu, "Next Space"))
    #expect(next.keyEquivalent == String(Character(UnicodeScalar(UInt16(NSRightArrowFunctionKey))!)))
    #expect(next.keyEquivalentModifierMask == [.command, .option])
    let previous = try #require(item(menu, "Previous Space"))
    #expect(previous.keyEquivalent == String(Character(UnicodeScalar(UInt16(NSLeftArrowFunctionKey))!)))
    #expect(previous.keyEquivalentModifierMask == [.command, .option])
    let spaces = ["Home", "Work", "Travel"].compactMap { item(menu, $0) }
    #expect(spaces.map(\.keyEquivalent) == ["1", "2", "3"])
    #expect(spaces.allSatisfy { $0.keyEquivalentModifierMask == [.control] })
  }

  @Test func onlyTheFirstNineHaveShortcuts() {
    let (_, _, _, menu) = make((2...10).map { "Space \($0)" })
    let spaces = menu.menu.items.suffix(10)
    #expect(spaces.prefix(9).map(\.keyEquivalent) == (1...9).map(String.init))
    #expect(spaces.last?.keyEquivalent == "")
  }

  @Test func theWindowsSpaceIsChecked() {
    let (host, _, controller, menu) = make()
    #expect(item(menu, "Home")?.state == .on)
    #expect(item(menu, "Work")?.state == .off)
    controller.showSpace(host.spaces[1].spaceID)
    menu.menuNeedsUpdate(menu.menu)
    #expect(item(menu, "Home")?.state == .off)
    #expect(item(menu, "Work")?.state == .on)
  }

  @Test func nextAndPreviousWrapAtTheEnds() throws {
    let (host, browser, _, menu) = make()
    let previous = try #require(item(menu, "Previous Space"))
    menu.choose(previous)
    #expect(browser.shownSpaceID == host.spaces[2].spaceID)
    let next = try #require(item(menu, "Next Space"))
    menu.choose(next)
    #expect(browser.shownSpaceID == FakeHost.homeID)
  }

  @Test func aSpacesItemShowsIt() throws {
    let (host, browser, _, menu) = make()
    menu.choose(try #require(item(menu, "Travel")))
    #expect(browser.shownSpaceID == host.spaces[2].spaceID)
  }

  @Test func reorderingRebuildsInTheNewOrder() {
    let (host, _, _, menu) = make()
    host.moveSpace(host.spaces[2].spaceID, to: 0)
    let spaces = menu.menu.items.suffix(3)
    #expect(spaces.map(\.title) == ["Travel", "Home", "Work"])
    #expect(spaces.map(\.keyEquivalent) == ["1", "2", "3"])
  }

  @Test func renamingAndIconsShowAtOnce() {
    let (host, _, _, menu) = make()
    host.renameSpace(host.spaces[1].spaceID, to: "Research")
    host.setIcon("📚", forSpace: host.spaces[1].spaceID)
    #expect(item(menu, "📚 Research") != nil)
  }

  @Test func newSpaceAndRenameReachTheWindow() throws {
    let (_, _, controller, menu) = make()
    menu.choose(try #require(item(menu, "New Space…")))
    #expect(controller.model.newSpaceForm != nil)
    menu.choose(try #require(item(menu, "Rename Space")))
    #expect(controller.model.spaceHeaderEdit == .renaming)
    #expect(controller.model.newSpaceForm == nil)
  }

  @Test func itemsAreOffWithoutAWindowThatShowsSpaces() throws {
    let (_, _, _, menu) = make()
    menu.currentController = { nil }
    #expect(!menu.validateMenuItem(try #require(item(menu, "Next Space"))))
    #expect(!menu.validateMenuItem(try #require(item(menu, "Home"))))
  }

  @Test func nextIsOffWithOneSpace() throws {
    let (_, _, _, menu) = make([])
    #expect(!menu.validateMenuItem(try #require(item(menu, "Next Space"))))
    #expect(menu.validateMenuItem(try #require(item(menu, "New Space…"))))
  }

  @Test func installsAfterView() {
    let main = NSMenu()
    for title in ["Clair", "File", "Edit", "View", "History", "Window"] {
      let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      item.submenu = NSMenu(title: title)
      main.addItem(item)
    }
    let (_, _, _, menu) = make()
    #expect(menu.install(in: main))
    #expect(!menu.install(in: main))
    #expect(main.items.map(\.title) == ["Clair", "File", "Edit", "View", "Spaces", "History", "Window"])
  }
}
