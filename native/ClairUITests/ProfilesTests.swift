// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Foundation
import Testing

@testable import ClairUI

/// A window on a fake host with a "Work" profile and a "Work" Space using it,
/// beside "Home" on the default profile.
@MainActor
func profilesWindow(tabs: Int = 1, suite: String = #function)
  -> (FakeHost, FakeBrowser, BrowserWindowController, work: SpaceID, workProfile: ProfileID)
{
  let (host, browser, controller) = spacesWindow([], tabs: tabs, suite: suite)
  let workProfile = host.addProfile("Work")
  let work = host.createSpace(named: "Work", icon: nil, profile: workProfile)!
  return (host, browser, controller, work, workProfile)
}

/// The fake engine's profile rules (add-profiles D1, D7, D9, D13), which the
/// tests of ClairUI rely on.
@MainActor
struct FakeProfilesTests {
  @Test func aSpaceHasAProfile() {
    let host = FakeHost()
    #expect(host.spaces[0].profileID == FakeHost.defaultProfileID)
    #expect(host.profiles.map(\.name) == ["Default"])
    let work = host.addProfile("Work")
    let space = host.createSpace(named: "Work", icon: nil, profile: work)
    #expect(host.spaces.last?.profileID == work)
    #expect(space != nil)
    #expect(host.createSpace(named: "Gone", icon: nil, profile: "Profile 99") == nil)
  }

  @Test func profilesAreCreatedRenamedAndDeleted() {
    let host = FakeHost()
    let observer = RecordingSpacesObserver()
    host.addObserver(observer)
    var created: ProfileID?
    host.createProfile(named: "  ") { created = $0 }
    #expect(created == nil)
    host.createProfile(named: " Client ") { created = $0 }
    let client = try! #require(created)
    #expect(host.profiles.map(\.name) == ["Default", "Client"])
    host.renameProfile(client, to: "Office")
    #expect(host.profiles.last?.name == "Office")
    // D7: a profile a Space uses stays.
    host.deleteProfile(FakeHost.defaultProfileID)
    #expect(host.profiles.count == 2)
    host.deleteProfile(client)
    #expect(host.profiles.map(\.name) == ["Default"])
    #expect(observer.calls == ["profiles Default,Client", "profiles Default,Office", "profiles Default"])
  }

  /// D9: the Space's tabs reopen at their URLs, in order, without Peeks, and
  /// the window shows the one reopened from its active tab.
  @Test func settingTheProfileReopensTheTabs() {
    let host = FakeHost()
    let work = host.addProfile("Work")
    let browser = FakeBrowser(host: host)
    let window = RecordingWindow()
    browser.clairWindow = window
    let c = browser.addTab(title: "C", url: "https://c.example/")
    let b = browser.addTab(title: "B", url: "https://b.example/")
    let a = browser.addTab(title: "A", url: "https://a.example/")
    browser.activate(tab: b.tabID)
    browser.openPeek(of: b.tabID, title: "Peek", url: "https://peek.example/")
    host.setProfile(work, forSpace: FakeHost.homeID)
    let list = host.list(FakeHost.homeID)
    #expect(host.spaces[0].profileID == work)
    #expect(list.map(\.urlText) == ["https://a.example/", "https://b.example/", "https://c.example/"])
    #expect(list.allSatisfy { $0.peekParentID == ClairTabIDNone && $0.peekID == ClairTabIDNone })
    #expect(Set(list.map(\.tabID)).isDisjoint(with: [a.tabID, b.tabID, c.tabID]))
    #expect(browser.activeTabID == list[1].tabID)
    #expect(browser.shownSpaceID == FakeHost.homeID)
    // The same profile again changes nothing.
    let commands = host.commands.count
    host.setProfile(work, forSpace: FakeHost.homeID)
    #expect(host.list(FakeHost.homeID).map(\.tabID) == list.map(\.tabID))
    #expect(host.commands.count == commands + 1)
  }

  /// D9: moving a tab to a Space of another profile reopens it at the top.
  @Test func movingAcrossProfilesReopensTheTab() {
    let host = FakeHost()
    let workProfile = host.addProfile("Work")
    let work = host.createSpace(named: "Work", icon: nil, profile: workProfile)!
    let browser = FakeBrowser(host: host)
    let other = browser.addTab(title: "Other", url: "https://other.example/")
    let docs = browser.addTab(title: "Docs", url: "https://docs.example/")
    browser.openPeek(of: docs.tabID, url: "https://peek.example/")
    host.move(tab: docs.tabID, toSpace: work)
    let moved = host.list(work)
    #expect(moved.map(\.urlText) == ["https://docs.example/"])
    #expect(moved[0].tabID != docs.tabID)
    #expect(host.list(FakeHost.homeID).map(\.tabID) == [other.tabID])
    // The window followed its active tab.
    #expect(browser.shownSpaceID == work)
    #expect(browser.activeTabID == moved[0].tabID)
  }

  /// D9: moving another tab leaves the window where it is.
  @Test func movingAnInactiveTabLeavesTheWindow() {
    let host = FakeHost()
    let workProfile = host.addProfile("Work")
    let work = host.createSpace(named: "Work", icon: nil, profile: workProfile)!
    let browser = FakeBrowser(host: host)
    let maps = browser.addTab(title: "Maps", url: "https://maps.example/")
    let docs = browser.addTab(title: "Docs", url: "https://docs.example/")
    host.move(tab: maps.tabID, toSpace: work)
    #expect(browser.shownSpaceID == FakeHost.homeID)
    #expect(browser.activeTabID == docs.tabID)
    #expect(host.list(work).map(\.urlText) == ["https://maps.example/"])
  }

  /// Within a profile, the tab keeps its page: its ID stays.
  @Test func movingWithinAProfileKeepsThePage() {
    let host = FakeHost()
    let work = host.addSpaces("Work")[0]
    let browser = FakeBrowser(host: host)
    browser.addTab(title: "Other")
    let docs = browser.addTab(title: "Docs")
    host.move(tab: docs.tabID, toSpace: work)
    #expect(host.list(work).map(\.tabID) == [docs.tabID])
    #expect(browser.shownSpaceID == work)
    #expect(browser.activeTabID == docs.tabID)
  }

  @Test func downloadSettingsArePerProfile() {
    let host = FakeHost()
    let work = host.addProfile("Work")
    host.setAsksWhereToSave(true, forProfile: work)
    var read: (URL?, Bool)?
    host.downloadSettings(forProfile: work) { read = ($0, $1) }
    #expect(read?.1 == true)
    host.downloadSettings(forProfile: FakeHost.defaultProfileID) { read = ($0, $1) }
    #expect(read?.0?.lastPathComponent == "Downloads")
    #expect(read?.1 == false)
    host.setDownloadDirectory(URL(fileURLWithPath: "/Users/test/Documents"), forProfile: work)
    host.downloadSettings(forProfile: work) { read = ($0, $1) }
    #expect(read?.0?.lastPathComponent == "Documents")
    #expect(read?.1 == false)
    host.downloadSettings(forProfile: "Profile 99") { read = ($0, $1) }
    #expect(read?.0 == nil)
  }
}

/// The model's profile calls (add-profiles D1, D7).
@MainActor
struct SpacesModelProfileTests {
  @Test func theModelFollowsTheHostsProfiles() {
    let host = FakeHost()
    let model = SpacesModel(host: host)
    #expect(model.profiles.map(\.name) == ["Default"])
    let work = host.addProfile("Work")
    #expect(model.profiles.map(\.name) == ["Default", "Work"])
    #expect(model.spaceCount(ofProfile: work) == 0)
    _ = host.createSpace(named: "Work", icon: nil, profile: work)
    #expect(model.spaceCount(ofProfile: work) == 1)
    #expect(model.spaceCount(ofProfile: FakeHost.defaultProfileID) == 1)
  }

  @Test func onlyAProfileNoSpaceUsesCanBeDeleted() {
    let host = FakeHost()
    let model = SpacesModel(host: host)
    #expect(!model.canDeleteProfile(FakeHost.defaultProfileID))
    let client = host.addProfile("Client")
    #expect(model.canDeleteProfile(client))
    model.deleteProfile(client)
    #expect(model.profiles.map(\.name) == ["Default"])
  }

  @Test func aProfileChangeAsksOnlyWithTabs() throws {
    let (host, browser, controller, work, workProfile) = profilesWindow()
    let model = controller.model.spaces
    #expect(model.profileChange(of: work, to: workProfile) == nil)
    #expect(try #require(model.profileChange(of: work, to: FakeHost.defaultProfileID)).needsConfirmation == false)
    let home = try #require(model.profileChange(of: FakeHost.homeID, to: workProfile))
    #expect(home.needsConfirmation)
    #expect(home.tabCount == 1)
    _ = (host, browser)
  }

  @Test func renamingIgnoresEmptyAndSameNames() {
    let host = FakeHost()
    let model = SpacesModel(host: host)
    model.renameProfile(FakeHost.defaultProfileID, to: "  ")
    model.renameProfile(FakeHost.defaultProfileID, to: " Default ")
    #expect(!host.commands.contains { $0.hasPrefix("renameProfile") })
    model.renameProfile(FakeHost.defaultProfileID, to: " Personal ")
    #expect(host.profiles[0].name == "Personal")
  }
}

/// The profile popup in the New Space form and Manage Spaces (add-profiles
/// D12; profiles spec, "Choosing a profile for a new Space").
@MainActor
struct ProfilePopupTests {
  @Test func thePopupListsEveryProfileThenNewProfile() {
    let profiles: [any ClairProfile] = [
      FakeProfile(id: "Default", name: "Default"), FakeProfile(id: "Profile 1", name: "Work"),
    ]
    let items = SpacesLogic.profileMenu(profiles, checked: "Profile 1")
    #expect(items.map { $0?.title } == ["Default", "Work", nil, "New Profile…"])
    #expect(items.map { $0?.isChecked } == [false, true, nil, false])
    #expect(items.last??.command == .newProfile)
  }

  @Test func theFormPreselectsTheShownSpacesProfile() {
    let (_, _, controller, work, workProfile) = profilesWindow()
    controller.beginNewSpace()
    #expect(controller.model.newSpaceForm?.profileID == FakeHost.defaultProfileID)
    controller.showSpace(work)
    controller.beginNewSpace()
    #expect(controller.model.newSpaceForm?.profileID == workProfile)
  }

  @Test func theFormCreatesTheSpaceOnTheChosenProfile() {
    let (host, browser, controller, _, workProfile) = profilesWindow()
    controller.beginNewSpace()
    controller.model.newSpaceForm?.profileID = workProfile
    controller.createSpace(named: "Client", icon: nil, profile: workProfile)
    #expect(host.spaces.last?.name == "Client")
    #expect(host.spaces.last?.profileID == workProfile)
    #expect(browser.shownSpaceID == host.spaces.last?.spaceID)
  }

  @Test func aSpaceCreatedWithoutAChoiceTakesTheShownSpacesProfile() {
    let (host, _, controller, work, workProfile) = profilesWindow()
    controller.showSpace(work)
    controller.createSpace(named: "More work", icon: nil, profile: nil)
    #expect(host.spaces.last?.profileID == workProfile)
  }

  @Test func newProfileFromTheFormIsChosen() throws {
    let (host, _, controller, _, _) = profilesWindow()
    controller.beginNewSpace()
    controller.newProfileForNewSpace()
    let dialog = try #require(controller.dialogs.showing)
    #expect(dialog.page.title == "Create a new Profile")
    let field = try #require(dialog.page.buttons.last)
    #expect(!field.isEnabled)
    try typeName("Client", in: dialog)
    dialog.answer(.accepted)
    #expect(host.profiles.last?.name == "Client")
    #expect(controller.model.newSpaceForm?.profileID == host.profiles.last?.profileID)
  }

  @Test func manageSpacesAddsOnTheSelectedSpacesProfile() {
    let (host, _, controller, work, workProfile) = profilesWindow()
    let state = ManageSpacesState(spaces: controller.model.spaces, selecting: work)
    state.add()
    #expect(host.spaces.last?.name == "New Space")
    #expect(host.spaces.last?.profileID == workProfile)
  }
}

/// Types into a profile dialog's field, as its binding does.
@MainActor
func typeName(_ text: String, in dialog: ClairDialog) throws {
  let state = try #require(ProfileDialogTests.state(of: dialog))
  state.text = text
}

/// Set Profile, Change Profile and their confirmation (add-profiles D10;
/// profiles spec, "Changing a Space's profile").
@MainActor
struct SetProfileTests {
  @Test func anEmptySpaceChangesAtOnce() {
    let (host, _, controller, work, _) = profilesWindow()
    controller.setProfile(FakeHost.defaultProfileID, forSpace: work)
    #expect(controller.dialogs.showing == nil)
    #expect(host.profile(ofSpace: work) == FakeHost.defaultProfileID)
  }

  @Test func aSpaceWithTabsAsksFirst() throws {
    let (host, browser, controller, _, workProfile) = profilesWindow(tabs: 2)
    let before = host.list(FakeHost.homeID).map(\.urlText)
    controller.setProfile(workProfile, forSpace: FakeHost.homeID)
    let dialog = try #require(controller.dialogs.showing)
    #expect(dialog.page.title == "Switch to your “Work” Profile?")
    #expect(dialog.page.message?.contains("“Home” Space") == true)
    #expect(dialog.page.buttons.map(\.title) == ["Cancel", "Switch it up"])
    #expect(host.profile(ofSpace: FakeHost.homeID) == FakeHost.defaultProfileID)
    dialog.answer(.accepted)
    #expect(host.profile(ofSpace: FakeHost.homeID) == workProfile)
    #expect(host.list(FakeHost.homeID).map(\.urlText) == before)
    #expect(browser.shownSpaceID == FakeHost.homeID)
  }

  @Test func cancelChangesNothing() throws {
    let (host, _, controller, _, workProfile) = profilesWindow(tabs: 2)
    let before = host.list(FakeHost.homeID).map(\.tabID)
    controller.setProfile(workProfile, forSpace: FakeHost.homeID)
    try #require(controller.dialogs.showing).answer(.cancelled)
    #expect(host.profile(ofSpace: FakeHost.homeID) == FakeHost.defaultProfileID)
    #expect(host.list(FakeHost.homeID).map(\.tabID) == before)
  }

  @Test func theHeadersSetProfileChecksTheSpacesProfile() {
    let (_, _, controller, _, workProfile) = profilesWindow()
    let space = controller.model.shownSpace!
    let items = SpaceHeaderView.profileItems(for: space, in: controller.model.spaces, actions: controller)
    #expect(items.map(\.title) == ["Default", "Work", nil, "New Profile…"])
    guard case .checked = items[0], case .action(_, let choose) = items[1] else {
      Issue.record("Default isn't checked, or Work can't be chosen")
      return
    }
    choose()
    let dialog = controller.dialogs.showing
    #expect(dialog?.page.title == "Switch to your “Work” Profile?")
    _ = workProfile
  }

  @Test func newProfileFromSetProfileGivesItToTheSpace() throws {
    let (host, _, controller, work, _) = profilesWindow()
    controller.newProfile(forSpace: work)
    let dialog = try #require(controller.dialogs.showing)
    try typeName("Client", in: dialog)
    dialog.answer(.accepted)
    #expect(host.profiles.last?.name == "Client")
    #expect(host.profile(ofSpace: work) == host.profiles.last?.profileID)
  }

  @Test func theSpacesMenusChangeProfileActsOnTheWindowsSpace() throws {
    let (host, browser, controller, work, workProfile) = profilesWindow()
    browser.showSpace(work)
    let menu = SpacesMenu(spaces: controller.model.spaces)
    menu.currentController = { controller }
    menu.rebuild()
    let change = try #require(menu.menu.items.first { $0.title == "Change Profile" })
    let items = try #require(change.submenu).items
    #expect(items.map { $0.isSeparatorItem ? "-" : $0.title } == ["Default", "Work", "-", "New Profile…"])
    #expect(items[1].state == .on)
    #expect(items[0].state == .off)
    NSApplication.shared.sendAction(try #require(items[0].action), to: items[0].target, from: items[0])
    // Work shows a new tab page, so it asks first.
    try #require(controller.dialogs.showing).answer(.accepted)
    #expect(host.profile(ofSpace: work) == FakeHost.defaultProfileID)
    _ = workProfile
  }

  /// D12: Manage Spaces asks in place of the list, and stays open.
  @Test func manageSpacesAsksInPlace() throws {
    let (host, _, controller, _, workProfile) = profilesWindow()
    controller.manageSpaces()
    let dialog = try #require(controller.dialogs.showing)
    let state = try #require(controller.openManageSpaces)
    ManageSpacesDialog.setProfile(workProfile, state: state, dialog: dialog)
    #expect(dialog.page.title == "Switch to your “Work” Profile?")
    try #require(dialog.page.buttons.last).action?(dialog)
    #expect(dialog.page.title == "Manage Spaces")
    #expect(controller.dialogs.showing === dialog)
    #expect(host.profile(ofSpace: FakeHost.homeID) == workProfile)
  }
}

/// The New, Rename and Delete profile dialogs (add-profiles D12).
@MainActor
struct ProfileDialogTests {
  static func state(of dialog: ClairDialog) -> ProfileNameState? {
    ProfileDialogs.nameState(of: dialog)
  }

  @Test func createProfileNeedsAName() throws {
    let state = ProfileNameState()
    let page = ProfileDialogs.newProfilePage(state: state)
    #expect(page.title == "Create a new Profile")
    #expect(page.buttons.map(\.title) == ["Cancel", "Create Profile"])
    #expect(page.buttons[1].isEnabled == false)
    #expect(ProfileDialogs.canSave("  ") == false)
    #expect(ProfileDialogs.canSave(" Client ") == true)
  }

  @Test func theNewProfileDialogCreatesOnAccept() throws {
    let host = FakeHost()
    let spaces = SpacesModel(host: host)
    let presenter = ClairDialogPresenter(host: .init(begin: { _ in }, end: { _ in }))
    var created: ProfileID?? = .none
    let dialog = ProfileDialogs.showNewProfile(on: presenter, spaces: spaces) { created = .some($0) }
    try typeName("Client", in: dialog)
    #expect(dialog.page.buttons.last?.isEnabled == true)
    try typeName(" ", in: dialog)
    #expect(dialog.page.buttons.last?.isEnabled == false)
    try typeName("Client", in: dialog)
    dialog.answer(.accepted)
    #expect(created == .some(host.profiles.last?.profileID))
    #expect(host.profiles.map(\.name) == ["Default", "Client"])
  }

  @Test func cancellingCreatesNoProfile() {
    let host = FakeHost()
    let presenter = ClairDialogPresenter(host: .init(begin: { _ in }, end: { _ in }))
    var created: ProfileID?? = .none
    let dialog = ProfileDialogs.showNewProfile(on: presenter, spaces: SpacesModel(host: host)) { created = .some($0) }
    dialog.answer(.cancelled)
    #expect(created == .some(nil))
    #expect(host.profiles.count == 1)
  }

  @Test func renameHoldsTheNameAndNeedsOne() throws {
    let host = FakeHost()
    let spaces = SpacesModel(host: host)
    let presenter = ClairDialogPresenter(host: .init(begin: { _ in }, end: { _ in }))
    let dialog = ProfileDialogs.showRename(of: host.profiles[0], on: presenter, spaces: spaces)
    #expect(dialog.page.title == "Rename your Profile")
    #expect(dialog.page.message == "This won’t affect the names of any of the Spaces associated with this Profile.")
    #expect(dialog.page.buttons.map(\.title) == ["Cancel", "Save"])
    let state = try #require(Self.state(of: dialog))
    #expect(state.text == "Default")
    #expect(dialog.page.buttons[1].isEnabled)
    state.text = ""
    #expect(!dialog.page.buttons[1].isEnabled)
    state.text = "Personal"
    dialog.answer(.accepted)
    #expect(host.profiles[0].name == "Personal")
  }

  @Test func deleteNeedsTheExactName() throws {
    let host = FakeHost()
    let client = host.addProfile("Client")
    let spaces = SpacesModel(host: host)
    let presenter = ClairDialogPresenter(host: .init(begin: { _ in }, end: { _ in }))
    var deleted: Bool?
    let dialog = ProfileDialogs.showDelete(
      of: try #require(spaces.profile(client)), on: presenter, spaces: spaces) { deleted = $0 }
    #expect(dialog.page.title == "Delete this Profile")
    #expect(dialog.page.message?.hasPrefix("Deleting “Client” will permanently remove") == true)
    #expect(dialog.page.buttons.map(\.title) == ["Cancel", "Delete"])
    #expect(dialog.page.buttons[1].isDestructive)
    let state = try #require(Self.state(of: dialog))
    #expect(!dialog.page.buttons[1].isEnabled)
    state.text = "client 2"
    #expect(!dialog.page.buttons[1].isEnabled)
    state.text = "Client"
    #expect(dialog.page.buttons[1].isEnabled)
    dialog.answer(.accepted)
    #expect(deleted == true)
    #expect(host.profiles.map(\.name) == ["Default"])
  }

  @Test func cancellingDeleteKeepsTheProfile() {
    let host = FakeHost()
    let client = host.addProfile("Client")
    let spaces = SpacesModel(host: host)
    let presenter = ClairDialogPresenter(host: .init(begin: { _ in }, end: { _ in }))
    var deleted: Bool?
    let dialog = ProfileDialogs.showDelete(of: spaces.profile(client)!, on: presenter, spaces: spaces) {
      deleted = $0
    }
    dialog.answer(.cancelled)
    #expect(deleted == false)
    #expect(host.profiles.count == 2)
  }
}

/// Settings › Profiles and the Advanced toggles (add-profiles D12; profiles
/// spec, "Profiles page").
@MainActor
struct ProfilesPageTests {
  private let defaults: UserDefaults = {
    let name = "ClairUITests.Profiles.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
  }()

  @Test func theFirstProfileIsSelectedAndANeighbourAfterARemoval() {
    let host = FakeHost()
    let a = host.addProfile("A")
    let b = host.addProfile("B")
    let state = ProfilesPageState(spaces: SpacesModel(host: host), host: host)
    state.reset()
    #expect(state.selection == FakeHost.defaultProfileID)
    state.select(a)
    #expect(state.selection == a)
    host.deleteProfile(a)
    state.removed(a, at: 1)
    #expect(state.selection == FakeHost.defaultProfileID)
    state.select(b)
    host.deleteProfile(b)
    // Removed elsewhere: the first is selected.
    #expect(state.selection == FakeHost.defaultProfileID)
  }

  @Test func removeIsOnlyForAProfileNoSpaceUses() {
    let host = FakeHost()
    let state = ProfilesPageState(spaces: SpacesModel(host: host), host: host)
    #expect(!state.canRemove)
    let client = host.addProfile("Client")
    state.select(client)
    #expect(state.canRemove)
    #expect(!state.linksEnabled)
    _ = host.createSpace(named: "Client", icon: nil, profile: client)
    #expect(!state.canRemove)
    #expect(state.linksEnabled)
  }

  @Test func spaceCountsFollowTheModel() {
    let host = FakeHost()
    let spaces = SpacesModel(host: host)
    let work = host.addProfile("Work")
    #expect(SpacesLogic.spaceCountLabel(spaces.spaceCount(ofProfile: work)) == nil)
    _ = host.createSpace(named: "Work", icon: nil, profile: work)
    #expect(SpacesLogic.spaceCountLabel(spaces.spaceCount(ofProfile: work)) == "1 Space")
    _ = host.createSpace(named: "More", icon: nil, profile: work)
    #expect(SpacesLogic.spaceCountLabel(spaces.spaceCount(ofProfile: work)) == "2 Spaces")
  }

  @Test func thePopupShowsTheFolderOrAskEveryTime() {
    let host = FakeHost()
    let work = host.addProfile("Work")
    let state = ProfilesPageState(spaces: SpacesModel(host: host), host: host)
    state.select(work)
    #expect(state.downloadTitle == "Downloads")
    #expect(state.downloadItems.map { $0?.title } == ["Downloads", "Other…", nil, "Ask every time"])
    #expect(state.downloadItems.map { $0?.isChecked } == [true, false, nil, false])
    state.askEveryTime()
    #expect(state.downloadTitle == "Ask every time")
    #expect(state.downloadItems.map { $0?.isChecked } == [false, false, nil, true])
    #expect(host.commands.last == "asksWhereToSave \(work) true")
    state.useFolder()
    #expect(state.downloadTitle == "Downloads")
    #expect(host.downloadSettings[work]?.asks == false)
    state.useFolder(URL(fileURLWithPath: "/Users/test/Documents", isDirectory: true))
    #expect(state.downloadTitle == "Documents")
    #expect(host.downloadSettings[FakeHost.defaultProfileID] == nil)
  }

  @Test func aLinkOpensInTheSelectedProfile() {
    let host = FakeHost()
    let state = ProfilesPageState(spaces: SpacesModel(host: host), host: host)
    state.reset()
    state.open(.searchEngine)
    #expect(host.openedURLsInProfiles.map(\.url.absoluteString) == ["chrome://settings/search"])
    #expect(host.openedURLsInProfiles.map(\.profileID) == [FakeHost.defaultProfileID])
    #expect(ProfileSettingsLink.allCases.map(\.url.absoluteString) == [
      "chrome://settings/search", "chrome://settings/privacy", "chrome://settings/content/notifications",
      "chrome://settings/clearBrowserData",
    ])
    let client = host.addProfile("Client")
    state.select(client)
    state.open(.privacy)
    #expect(host.openedURLsInProfiles.count == 1)
  }

  @Test func warnBeforeQuittingFollowsTheHost() {
    let host = FakeHost()
    let warn = WarnBeforeQuitting(host: host)
    #expect(warn.isOn)
    warn.set(false)
    #expect(!host.warnsBeforeQuitting)
    #expect(!warn.isOn)
    host.warnsBeforeQuitting = true
    warn.refresh()
    #expect(warn.isOn)
  }

  @Test func restoreWindowsIsOffUntilTurnedOn() {
    #expect(!RestoreWindowsPreference.isEnabled(in: defaults))
    defaults.set(true, forKey: RestoreWindowsPreference.key)
    #expect(RestoreWindowsPreference.isEnabled(in: defaults))
    defaults.set(false, forKey: RestoreWindowsPreference.key)
    #expect(!RestoreWindowsPreference.isEnabled(in: defaults))
    #expect(RestoreWindowsPreference.key == "ClairRestoreWindows")
  }
}

/// D12: the slide across profiles, in a window the group swaps in.
@MainActor
struct SwapTests {
  @Test func aSwappedInWindowSlidesFromTheEarlierSpace() throws {
    let (host, browser, controller, work, _) = profilesWindow(tabs: 2)
    // A second browser stands for the group's member of the Work profile,
    // which last showed Work.
    let member = FakeBrowser(host: host)
    member.showSpace(work)
    let incoming = BrowserWindowController(
      browser: member, spaces: member.spaces,
      preferences: SidebarPreferences(defaults: UserDefaults(suiteName: #function + ".member")!))
    member.clairWindow = incoming
    incoming.window.orderFront(nil)
    defer { incoming.window.orderOut(nil) }
    let homeRows = host.list(FakeHost.homeID).map(\.tabID)
    // The group swapped from the window showing Home to this one.
    incoming.shownSpaceDidChange(work, from: FakeHost.homeID)
    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      let slide = try #require(incoming.model.spaceSlide)
      #expect(slide.fromSpace?.spaceID == FakeHost.homeID)
      #expect(slide.fromTabs.map(\.tabID) == homeRows)
    }
    #expect(incoming.model.shownSpaceID == work)
    _ = (browser, controller)
  }

  @Test func manageSpacesFollowsTheSwap() throws {
    let (host, _, controller, work, _) = profilesWindow()
    controller.manageSpaces()
    let state = try #require(controller.openManageSpaces)
    state.select(work)
    #expect(!controller.window.isVisible)
    let member = FakeBrowser(host: host)
    member.showSpace(work)
    let incoming = BrowserWindowController(
      browser: member, spaces: member.spaces,
      preferences: SidebarPreferences(defaults: UserDefaults(suiteName: #function + ".member")!))
    member.clairWindow = incoming
    incoming.shownSpaceDidChange(work, from: FakeHost.homeID)
    #expect(controller.openManageSpaces == nil)
    #expect(incoming.openManageSpaces === state)
    #expect(incoming.openManageSpaces?.selection == work)
    #expect(incoming.dialogs.showing?.page.title == "Manage Spaces")
  }
}
