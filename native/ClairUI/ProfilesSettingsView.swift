// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Observation
import SwiftUI

/// The Download location popup's rules (profiles spec, "Download location").
enum DownloadLocationLogic {
  struct Item: Equatable {
    enum Kind: Equatable {
      /// The folder the profile saves to: choosing it stops asking.
      case folder
      /// macOS's folder picker.
      case other
      case askEveryTime
    }

    let title: String
    let kind: Kind
    let isChecked: Bool
  }

  static let otherTitle = "Other…"
  static let askTitle = "Ask every time"

  /// A folder's name, as Finder shows it.
  static func folderName(_ directory: URL?) -> String {
    guard let directory else { return "" }
    return FileManager.default.displayName(atPath: directory.path)
  }

  /// What the popup shows closed: the folder, or "Ask every time".
  static func title(directory: URL?, asks: Bool) -> String {
    asks ? askTitle : folderName(directory)
  }

  /// The folder, "Other…", a nil for the divider, and "Ask every time", with
  /// a checkmark on the one in use.
  static func items(directory: URL?, asks: Bool) -> [Item?] {
    [
      Item(title: folderName(directory), kind: .folder, isChecked: !asks),
      Item(title: otherTitle, kind: .other, isChecked: false),
      nil,
      Item(title: askTitle, kind: .askEveryTime, isChecked: asks),
    ]
  }
}

/// The rows that open Chromium's settings for the selected profile (profiles
/// spec, "Links to a profile's Chromium settings").
enum ProfileSettingsLink: CaseIterable {
  case searchEngine, privacy, notifications, clearBrowsingData

  var title: String {
    switch self {
    case .searchEngine: "Search Engine"
    case .privacy: "Privacy and Security"
    case .notifications: "Notifications"
    case .clearBrowsingData: "Clear Browsing Data"
    }
  }

  var url: URL {
    switch self {
    case .searchEngine: URL(string: "chrome://settings/search")!
    case .privacy: URL(string: "chrome://settings/privacy")!
    case .notifications: URL(string: "chrome://settings/content/notifications")!
    case .clearBrowsingData: URL(string: "chrome://settings/clearBrowserData")!
    }
  }

  var symbol: String {
    switch self {
    case .searchEngine: "magnifyingglass"
    case .privacy: "hand.raised.fill"
    case .notifications: "bell.fill"
    case .clearBrowsingData: "trash.fill"
    }
  }

  var color: Color {
    switch self {
    case .searchEngine: .blue
    case .privacy: .indigo
    case .notifications: .red
    case .clearBrowsingData: .gray
    }
  }

  static let disabledNote = "Use this Profile in a Space to change these settings."
}

/// What the Profiles page holds: the selected profile and its download
/// settings (add-profiles design D12). The list itself follows `SpacesModel`.
@MainActor
@Observable
final class ProfilesPageState {
  let spaces: SpacesModel
  @ObservationIgnored let host: (any ClairHost)?
  private var chosen: ProfileID?
  /// The selected profile's download folder and whether it asks, once read.
  private(set) var downloadDirectory: URL?
  private(set) var asksWhereToSave = false
  /// Which profile the download settings were read for.
  private var downloadsRead: ProfileID?

  init(spaces: SpacesModel, host: (any ClairHost)?) {
    self.spaces = spaces
    self.host = host
  }

  /// One profile is always selected: the one chosen, while it exists, or
  /// else the first.
  var selection: ProfileID? {
    if let chosen, spaces.profile(chosen) != nil {
      return chosen
    }
    return spaces.profiles.first?.profileID
  }

  var selectedProfile: (any ClairProfile)? {
    selection.flatMap { spaces.profile($0) }
  }

  func select(_ profileID: ProfileID) {
    guard spaces.profile(profileID) != nil else { return }
    chosen = profileID
    readDownloadSettings()
  }

  /// The page opened: the first profile is selected.
  func reset() {
    chosen = nil
    readDownloadSettings()
  }

  /// Remove is on only for a profile no Space uses (D7).
  var canRemove: Bool {
    selection.map(spaces.canDeleteProfile) ?? false
  }

  /// The link rows need a Space using the profile.
  var linksEnabled: Bool {
    selection.map { spaces.spaceCount(ofProfile: $0) > 0 } ?? false
  }

  /// After `profileID`, at `index` in the list, is removed: its neighbour is
  /// selected, the one before it or else the one after.
  func removed(_ profileID: ProfileID, at index: Int) {
    let remaining = spaces.profiles.filter { $0.profileID != profileID }
    chosen = remaining.isEmpty ? nil : remaining[max(0, min(index - 1, remaining.count - 1))].profileID
    readDownloadSettings()
  }

  /// Reads the selected profile's download settings from the host.
  func readDownloadSettings() {
    guard let profileID = selection, let host else { return }
    downloadsRead = profileID
    host.downloadSettings(forProfile: profileID) { [weak self] directory, asks in
      MainActor.assumeIsolated {
        guard let self, self.downloadsRead == profileID else { return }
        self.downloadDirectory = directory
        self.asksWhereToSave = asks
      }
    }
  }

  /// The popup's items for the selected profile.
  var downloadItems: [DownloadLocationLogic.Item?] {
    DownloadLocationLogic.items(directory: downloadDirectory, asks: asksWhereToSave)
  }

  var downloadTitle: String {
    DownloadLocationLogic.title(directory: downloadDirectory, asks: asksWhereToSave)
  }

  /// The folder in the menu, or a folder from "Other…": downloads go there
  /// without asking.
  func useFolder(_ directory: URL? = nil) {
    guard let profileID = selection, let directory = directory ?? downloadDirectory else { return }
    host?.setDownloadDirectory(directory, forProfile: profileID)
    downloadDirectory = directory
    asksWhereToSave = false
  }

  func askEveryTime() {
    guard let profileID = selection else { return }
    host?.setAsksWhereToSave(true, forProfile: profileID)
    asksWhereToSave = true
  }

  /// Opens a link row's page in a Space of the selected profile.
  func open(_ link: ProfileSettingsLink) {
    guard linksEnabled, let profileID = selection else { return }
    host?.open(link.url, inProfile: profileID)
  }
}

/// What the Profiles page asks its window to do.
@MainActor
protocol ProfilesPageActions: AnyObject {
  func addProfile()
  func removeProfile(_ profile: any ClairProfile)
  func renameProfile(_ profile: any ClairProfile)
  func chooseDownloadFolder()
  /// A link row opened its page: the Settings window closes.
  func didOpenLink()
}

/// Settings › Profiles (profiles spec, "Profiles page"), laid out as Arc's:
/// the help text, then "Your Profiles" on the left with Add, Remove and Rename
/// at its bottom edge, and the selected profile's settings on the right.
struct ProfilesSettingsView: View {
  let state: ProfilesPageState
  weak var actions: (any ProfilesPageActions)?

  static let width: CGFloat = 684
  static let listWidth: CGFloat = 205
  static let rowHeight: CGFloat = 40
  static let helpText =
    "Profiles help keep your data separate across Spaces — like history, logins, cookies, and extensions. You can "
    + "use any Profile across one or more Spaces."

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(Self.helpText)
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      HStack(alignment: .top, spacing: 16) {
        profileList
          .frame(width: Self.listWidth)
        details
      }
    }
    .padding(20)
    .frame(width: Self.width, alignment: .topLeading)
    .fixedSize(horizontal: false, vertical: true)
    .onAppear { state.reset() }
  }

  private var profileList: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Your Profiles")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
      Divider()
      ScrollView {
        VStack(spacing: 0) {
          ForEach(state.spaces.profiles, id: \.profileID) { profile in
            let selected = profile.profileID == state.selection
            HStack {
              Text(profile.name).lineLimit(1)
              Spacer(minLength: 4)
              if let count = SpacesLogic.spaceCountLabel(state.spaces.spaceCount(ofProfile: profile.profileID)) {
                Text(count)
                  .font(.system(size: 12))
                  .foregroundStyle(selected ? AnyShapeStyle(Color.white.opacity(0.8)) : AnyShapeStyle(.secondary))
              }
            }
            .foregroundStyle(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 12)
            .frame(height: Self.rowHeight)
            .background {
              if selected {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.accentColor).padding(.horizontal, 4)
              }
            }
            .contentShape(Rectangle())
            .onTapGesture { state.select(profile.profileID) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            .accessibilityIdentifier("clair.profileRow")
          }
        }
        .padding(.vertical, 4)
      }
      .frame(height: 220)
      Divider()
      HStack(spacing: 0) {
        Button {
          actions?.addProfile()
        } label: {
          Image(systemName: "plus").frame(width: 26, height: 22)
        }
        .help("Add Profile")
        .accessibilityIdentifier("clair.profilesAdd")
        Button {
          if let profile = state.selectedProfile { actions?.removeProfile(profile) }
        } label: {
          Image(systemName: "minus").frame(width: 26, height: 22)
        }
        .disabled(!state.canRemove)
        .help("Remove Profile")
        .accessibilityIdentifier("clair.profilesRemove")
        Spacer(minLength: 0)
        Button("Rename") {
          if let profile = state.selectedProfile { actions?.renameProfile(profile) }
        }
        .disabled(state.selectedProfile == nil)
        .accessibilityIdentifier("clair.profilesRename")
      }
      .buttonStyle(.borderless)
      .padding(.horizontal, 6)
      .padding(.vertical, 4)
    }
    .background(SettingsCard.background)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("clair.profilesList")
  }

  private var details: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Download location")
        Spacer(minLength: 8)
        Menu {
          ForEach(Array(state.downloadItems.enumerated()), id: \.offset) { _, item in
            if let item {
              Toggle(item.title, isOn: Binding(get: { item.isChecked }, set: { _ in choose(item) }))
            } else {
              Divider()
            }
          }
        } label: {
          Text(state.downloadTitle).lineLimit(1)
        }
        .fixedSize()
        .accessibilityIdentifier("clair.downloadLocation")
      }
      .padding(12)
      .background(SettingsCard.background)
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(ProfileSettingsLink.allCases.enumerated()), id: \.offset) { index, link in
          if index > 0 {
            Divider().padding(.leading, 44)
          }
          Button {
            state.open(link)
            actions?.didOpenLink()
          } label: {
            HStack(spacing: 10) {
              Image(systemName: link.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(link.color))
              Text(link.title)
              Spacer(minLength: 4)
              Image(systemName: "arrow.up.forward").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .disabled(!state.linksEnabled)
          .accessibilityIdentifier("clair.profileLink")
        }
      }
      .background(SettingsCard.background)
      .opacity(state.linksEnabled ? 1 : 0.5)
      if !state.linksEnabled {
        Text(ProfileSettingsLink.disabledNote)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("clair.profileLinksNote")
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  private func choose(_ item: DownloadLocationLogic.Item) {
    switch item.kind {
    case .folder: state.useFolder()
    case .other: actions?.chooseDownloadFolder()
    case .askEveryTime: state.askEveryTime()
    }
  }
}

/// The rounded card the Settings pages group their rows in, as a grouped
/// Form draws it.
enum SettingsCard {
  static var background: some View {
    RoundedRectangle(cornerRadius: 8, style: .continuous)
      .fill(Color(nsColor: .quaternarySystemFill))
      .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
  }
}
