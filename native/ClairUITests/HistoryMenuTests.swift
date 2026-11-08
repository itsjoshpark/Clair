// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Testing

@testable import ClairUI

/// The back and forward history menu against `FakeBrowser`
/// (arc-navigation-feedback design D3).
@MainActor
struct HistoryMenuTests {
  private static func favicon(_ color: NSColor) -> NSImage {
    NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
      color.setFill()
      rect.fill()
      return true
    }
  }

  private func browserWithBackHistory() -> FakeBrowser {
    let browser = FakeBrowser()
    browser.historyItems[.back] = [
      FakeHistoryItem(id: 0, title: "Page C", url: "https://c.example/", icon: Self.favicon(.red)),
      FakeHistoryItem(id: 1, title: "https://b.example/", url: "https://b.example/"),
      FakeHistoryItem(id: 2, title: "Page A", url: "https://a.example/", icon: Self.favicon(.blue)),
      .showFullHistory(id: 4),
    ]
    return browser
  }

  @Test func listsPagesNearestFirstWithTitlesAndIcons() throws {
    let browser = browserWithBackHistory()
    let builder = try #require(HistoryMenuBuilder(browser: browser, direction: .back))
    #expect(browser.commands == ["historyMenu \(HistoryDirection.back.rawValue)"])
    #expect(builder.menu.items.map(\.title) == ["Page C", "https://b.example/", "Page A"])
    #expect(builder.menu.items.map(\.tag) == [0, 1, 2])
    #expect(builder.menu.items.allSatisfy { $0.image?.size == HistoryMenuBuilder.iconSize })
    #expect(builder.menu.items[0].image !== HistoryMenuBuilder.placeholderIcon)
    #expect(builder.menu.items[1].image === HistoryMenuBuilder.placeholderIcon)
  }

  @Test func lateFaviconUpdatesTheOpenMenuInPlace() throws {
    let browser = browserWithBackHistory()
    let builder = try #require(HistoryMenuBuilder(browser: browser, direction: .back))
    let item = builder.menu.items[1]
    try #require(browser.historyMenu).setIcon(Self.favicon(.green), forItem: 1)
    #expect(builder.menu.items[1] === item)
    #expect(item.image !== HistoryMenuBuilder.placeholderIcon)
    #expect(item.image?.size == HistoryMenuBuilder.iconSize)
  }

  @Test func choosingAnEntryGoesThereInTheTab() throws {
    let browser = browserWithBackHistory()
    let builder = try #require(HistoryMenuBuilder(browser: browser, direction: .back))
    builder.isCommandKeyDown = { false }
    builder.menu.performActionForItem(at: 2)
    let session = try #require(browser.historyMenu)
    #expect(session.opened.map(\.itemID) == [2])
    #expect(session.opened.map(\.disposition) == [.currentTab])
  }

  @Test func commandChoosingOpensABackgroundTab() throws {
    let browser = browserWithBackHistory()
    let builder = try #require(HistoryMenuBuilder(browser: browser, direction: .back))
    builder.isCommandKeyDown = { true }
    builder.menu.performActionForItem(at: 0)
    let session = try #require(browser.historyMenu)
    #expect(session.opened.map(\.itemID) == [0])
    #expect(session.opened.map(\.disposition) == [.newBackgroundTab])
  }

  @Test func noMenuWhenTheTabCannotGoThatWay() {
    let browser = browserWithBackHistory()
    #expect(HistoryMenuBuilder(browser: browser, direction: .forward) == nil)
    #expect(browser.historyMenus.isEmpty)
  }

  @Test func closingWithoutChoosingEndsTheSession() throws {
    let browser = browserWithBackHistory()
    let builder = try #require(HistoryMenuBuilder(browser: browser, direction: .back))
    builder.close()
    let session = try #require(browser.historyMenu)
    #expect(session.isClosed)
    #expect(session.opened.isEmpty)
  }
}
