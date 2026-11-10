// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import SwiftUI
import Testing

@testable import ClairUI

/// How pinned extensions wrap (arc-site-control-center design D1).
@MainActor
struct PinnedExtensionsGridTests {
  /// A row with room for four tiles across, as Arc's narrower sidebars have.
  static let fourAcross: CGFloat = 171
  /// The default sidebar's row, with room for five.
  static let fiveAcross: CGFloat = 212

  @Test(arguments: [
    (1, 1, 1), (2, 2, 1), (3, 3, 1), (4, 4, 1), (5, 3, 2), (6, 3, 2), (7, 4, 2), (8, 4, 2), (9, 3, 3), (10, 4, 3),
  ])
  func countsAtFourAcross(count: Int, columns: Int, rows: Int) {
    let grid = PinnedExtensionsGrid(count: count, width: Self.fourAcross)
    #expect(grid.columns == columns)
    #expect(grid.rows == rows)
  }

  @Test func tenAtFiveAcross() {
    let grid = PinnedExtensionsGrid(count: 10, width: Self.fiveAcross)
    #expect(grid.columns == 5)
    #expect(grid.rows == 2)
    #expect(grid.tileWidth == 36)
  }

  @Test func aSingleTileFillsTheRow() {
    #expect(PinnedExtensionsGrid(count: 1, width: Self.fiveAcross).tileWidth == Self.fiveAcross)
  }

  @Test func aRowTooNarrowForOneTileStillHasAColumn() {
    let grid = PinnedExtensionsGrid(count: 3, width: 20)
    #expect(grid.columns == 1)
    #expect(grid.rows == 3)
    #expect(grid.tileWidth == 20)
  }

  @Test func aVeryWideRowStaysAtFive() {
    let grid = PinnedExtensionsGrid(count: 10, width: 484)
    #expect(grid.columns == 5)
    #expect(grid.rows == 2)
    #expect(grid.tileWidth == CGFloat(484 - 4 * 8) / 5)
  }

  @Test func theSwitchFromFourToFiveNeedsTwentyNinePointTiles() {
    #expect(PinnedExtensionsGrid(count: 10, width: 176).columns == 4)
    #expect(PinnedExtensionsGrid(count: 10, width: 177).columns == 5)
  }

  @Test func nothingPinnedTakesNoRoom() {
    let grid = PinnedExtensionsGrid(count: 0, width: Self.fiveAcross)
    #expect(grid.rows == 0)
    #expect(grid.height == 0)
  }

  @Test(arguments: [(CGFloat(212), CGFloat(64)), (CGFloat(171), CGFloat(100))])
  func theLayoutReportsItsRowsHeight(width: CGFloat, height: CGFloat) {
    let layout = PinnedExtensionsLayout {
      ForEach(0..<10, id: \.self) { _ in Color.clear }
    }
    let host = NSHostingController(rootView: layout)
    let size = host.sizeThatFits(in: CGSize(width: width, height: 1000))
    #expect(size.width == width)
    #expect(size.height == height)
  }
}

/// The Site Control Center's rules (design D4, D5, D9).
@MainActor
struct SiteControlCenterLogicTests {
  @Test func pinnedComeFirstInTheirOrderThenAToZ() {
    let actions = [
      FakeExtensionAction(id: "z", name: "Zebra", pinned: false),
      FakeExtensionAction(id: "p2", name: "Second", pinned: true),
      FakeExtensionAction(id: "a10", name: "App 10", pinned: false),
      FakeExtensionAction(id: "p1", name: "Alpha", pinned: true),
      FakeExtensionAction(id: "a2", name: "App 2", pinned: false),
    ]
    #expect(SiteControlCenterLogic.ordered(actions).map(\.extensionID) == ["p2", "p1", "a2", "a10", "z"])
  }

  @Test(arguments: ["chrome://settings/", "devtools://devtools/x", "view-source:https://a.com/", "file:///a.txt"])
  func siteInfoIsHiddenOnInternalPages(url: String) {
    #expect(!SiteControlCenterLogic.showsSiteInfo(url: URL(string: url)))
  }

  @Test(arguments: ["http://a.com/", "https://a.com/"])
  func siteInfoShowsOnWebPages(url: String) {
    #expect(SiteControlCenterLogic.showsSiteInfo(url: URL(string: url)))
  }

  @Test func theGridScrollsBeyondEightRows() {
    #expect(!SiteControlCenterLogic.scrolls(tileCount: 1))
    #expect(!SiteControlCenterLogic.scrolls(tileCount: 32))
    #expect(SiteControlCenterLogic.scrolls(tileCount: 33))
    #expect(SiteControlCenterLogic.scrollingGridHeight == 312)
  }

  @Test func theNotSecureIconFollowsChromium() {
    #expect(URLDisplay.showsNotSecure(for: FakeTab(id: 1, url: "http://a.com/", isNotSecure: true)))
    #expect(!URLDisplay.showsNotSecure(for: FakeTab(id: 1, url: "http://localhost/")))
    #expect(!URLDisplay.showsNotSecure(for: nil))
  }

  @Test func theDefaultBadgeIsWhiteOnRed() {
    #expect(ExtensionBadgeColors.background(nil) == .systemRed)
    #expect(ExtensionBadgeColors.text(nil, background: nil) == .white)
  }

  @Test func aBadgeColourGetsTheTextThatContrastsMore() {
    #expect(ExtensionBadgeColors.text(nil, background: .yellow) == .black)
    #expect(ExtensionBadgeColors.text(nil, background: NSColor(srgbRed: 0, green: 0, blue: 0.5, alpha: 1)) == .white)
  }

  @Test func theExtensionsTextColourWins() {
    let blue = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
    #expect(ExtensionBadgeColors.text(blue, background: .yellow) == blue)
    #expect(ExtensionBadgeColors.background(blue) == blue)
  }

  @Test func anUnpinnedActionOpensFromTheSiteControls() {
    let browser = FakeBrowser()
    let controller = BrowserWindowController(
      browser: browser, preferences: SidebarPreferences(defaults: UserDefaults(suiteName: #function)!))
    browser.clairWindow = controller
    controller.runExtension("a", pinned: false)
    controller.runExtension("b", pinned: true)
    #expect(
      browser.commands == [
        "runExtension a \(AnchorKind.siteControls.rawValue)",
        "runExtension b \(AnchorKind.extensionAction.rawValue)",
      ])
  }
}
