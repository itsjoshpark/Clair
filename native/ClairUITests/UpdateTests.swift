// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import Sparkle
import Testing

@testable import ClairUI

struct UpdateConfigurationTests {
  private let environment = [UpdateConfiguration.feedURLOverrideVariable: "http://localhost:8000/appcast.xml"]

  @Test func releasePackageIgnoresTheOverride() {
    let configuration = UpdateConfiguration(infoDictionary: [:], environment: environment)
    #expect(configuration.feedURLOverride == nil)
  }

  @Test func onlyATrueMarkerCounts() {
    for marker: Any in [false, "YES", 1] {
      let configuration = UpdateConfiguration(
        infoDictionary: [UpdateConfiguration.nonOfficialPackageKey: marker], environment: environment)
      #expect(configuration.feedURLOverride == nil)
    }
  }

  @Test func nonOfficialPackageReadsTheOverride() {
    let configuration = UpdateConfiguration(
      infoDictionary: [UpdateConfiguration.nonOfficialPackageKey: true], environment: environment)
    #expect(configuration.feedURLOverride == "http://localhost:8000/appcast.xml")
  }

  @Test func nonOfficialPackageWithoutAnOverrideUsesInfoPlist() {
    let configuration = UpdateConfiguration(
      infoDictionary: [UpdateConfiguration.nonOfficialPackageKey: true],
      environment: [UpdateConfiguration.feedURLOverrideVariable: ""])
    #expect(configuration.feedURLOverride == nil)
  }
}

struct UpdateUserDriverTests {
  @Test func everyUpdateNotYetInstallingIsAccepted() {
    #expect(UpdateUserDriver.choice(forStage: .notDownloaded, informationOnly: false) == .install)
    #expect(UpdateUserDriver.choice(forStage: .downloaded, informationOnly: false) == .install)
  }

  /// "Install" at this stage would make Sparkle quit Clair right away.
  @Test func anUpdateAlreadyInstallingIsLeftToInstallOnQuit() {
    #expect(UpdateUserDriver.choice(forStage: .installing, informationOnly: false) == .dismiss)
  }

  @Test func informationOnlyUpdatesAreNotInstalled() {
    #expect(UpdateUserDriver.choice(forStage: .notDownloaded, informationOnly: true) == .dismiss)
  }
}

struct UpdateMenuTests {
  private func appMenu() -> (NSMenu, NSMenu) {
    let main = NSMenu()
    let app = NSMenu(title: "Clair")
    app.addItem(withTitle: "About Clair", action: nil, keyEquivalent: "")
    app.addItem(.separator())
    app.addItem(withTitle: "Quit Clair", action: nil, keyEquivalent: "q")
    main.addItem(withTitle: "Clair", action: nil, keyEquivalent: "").submenu = app
    return (main, app)
  }

  @Test func theItemGoesBelowAboutClair() {
    let (main, app) = appMenu()
    let menu = UpdateMenu {}
    menu.install(in: main)
    #expect(app.items.map(\.title) == ["About Clair", "Check for Updates…", "", "Quit Clair"])
  }

  @Test func theItemReadsCheckWithNoBadgeUntilAnUpdateWaits() {
    let menu = UpdateMenu {}
    #expect(menu.item.title == "Check for Updates…")
    #expect(menu.item.badge == nil)
    menu.setUpdateWaiting(true)
    #expect(menu.item.title == "Update Available…")
    #expect(menu.item.badge?.stringValue == "1 update")
    menu.setUpdateWaiting(false)
    #expect(menu.item.title == "Check for Updates…")
    #expect(menu.item.badge == nil)
  }

  @Test func choosingTheItemRunsTheAction() {
    var chosen = 0
    let menu = UpdateMenu { chosen += 1 }
    menu.install(in: appMenu().0)
    NSApplication.shared.sendAction(menu.item.action!, to: menu.item.target, from: menu.item)
    #expect(chosen == 1)
  }
}

final class FakePrompts: UpdatePrompting {
  var restartAnswer = true
  var incognitoAnswer = true
  private(set) var log: [String] = []

  func showUpToDate(version: String) { log.append("up to date") }
  func showCheckFailed(reason: String) { log.append("failed: \(reason)") }
  func askToRestart(forVersion version: String) -> Bool {
    log.append("restart \(version)")
    return restartAnswer
  }
  func askToCloseIncognitoWindows() -> Bool {
    log.append("incognito")
    return incognitoAnswer
  }
}

struct UpdateControllerTests {
  private let host = FakeHost()
  private let prompts = FakePrompts()
  private let item = SUAppcastItem.empty()

  private func controller() -> UpdateController {
    UpdateController(
      host: host, configuration: UpdateConfiguration(infoDictionary: [:], environment: [:]),
      prompts: prompts)
  }

  @Test func aBackgroundUpdateChangesTheMenuAndAsksNothing() {
    let updates = controller()
    updates.updateIsWaiting(item, userInitiated: false)
    #expect(updates.menuItemForTesting.title == "Update Available…")
    #expect(updates.menuItemForTesting.badge?.stringValue == "1 update")
    #expect(prompts.log.isEmpty)
    #expect(host.relaunchCount == 0)
  }

  @Test func chromiumHearsOfAWaitingUpdateOnce() {
    let updates = controller()
    updates.updateIsWaiting(item, userInitiated: false)
    updates.updateIsWaiting(item, userInitiated: false)
    #expect(host.updateWillInstallOnQuitCount == 1)
  }

  @Test func aCheckTheUserAskedForOffersTheRestart() {
    let updates = controller()
    prompts.restartAnswer = false
    updates.updateIsWaiting(item, userInitiated: true)
    #expect(prompts.log.count == 1)
    #expect(prompts.log[0].hasPrefix("restart"))
  }

  @Test func laterKeepsTheUpdateWaiting() {
    let updates = controller()
    prompts.restartAnswer = false
    updates.updateIsWaiting(item, userInitiated: false)
    updates.chooseUpdateItem()
    #expect(host.relaunchCount == 0)
    #expect(updates.waitingUpdate != nil)
    #expect(updates.menuItemForTesting.title == "Update Available…")
  }

  @Test func restartAndUpdateGoesThroughChromium() {
    let updates = controller()
    updates.updateIsWaiting(item, userInitiated: false)
    updates.chooseUpdateItem()
    #expect(host.relaunchCount == 1)
    #expect(!prompts.log.contains("incognito"))
  }

  @Test func incognitoWindowsAskFirst() {
    let updates = controller()
    host.blockers = [.incognitoWindow]
    prompts.incognitoAnswer = false
    updates.updateIsWaiting(item, userInitiated: false)
    updates.chooseUpdateItem()
    #expect(prompts.log.last == "incognito")
    #expect(host.relaunchCount == 0)

    prompts.incognitoAnswer = true
    updates.chooseUpdateItem()
    #expect(host.relaunchCount == 1)
  }

  /// Chromium's quit flow asks about downloads itself.
  @Test func otherBlockersDontAsk() {
    let updates = controller()
    host.blockers = [.downloadInProgress, .audibleTab, .capturingTab]
    updates.updateIsWaiting(item, userInitiated: false)
    updates.chooseUpdateItem()
    #expect(!prompts.log.contains("incognito"))
    #expect(host.relaunchCount == 1)
  }

  @Test func aCheckWithNoUpdaterReportsAFailure() {
    let updates = controller()
    updates.chooseUpdateItem()
    #expect(prompts.log.count == 1)
    #expect(prompts.log[0].hasPrefix("failed"))
  }

  @Test func shortVersionDropsTheBuild() {
    #expect(UpdateController.shortVersion(fromDisplayString: "0.1.1 (101)") == "0.1.1")
    #expect(UpdateController.shortVersion(fromDisplayString: "0.1.1") == "0.1.1")
  }

  @Test func theLastRunVersionIsKept() throws {
    let defaults = try #require(UserDefaults(suiteName: "ClairUITests.\(UUID())"))
    let first = controller()
    first.recordRunningVersion(in: defaults)
    #expect(first.previousVersion == nil)
    let second = controller()
    second.recordRunningVersion(in: defaults)
    #expect(second.previousVersion != nil)
  }
}
