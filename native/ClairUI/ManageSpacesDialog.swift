// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Observation
import SwiftUI

/// What Manage Spaces holds (add-spaces design D10): the selected Space and
/// the name being typed for it. Each change reaches the host at once, so it
/// shows in every window.
@MainActor
@Observable
final class ManageSpacesState {
  let spaces: SpacesModel
  private(set) var selection: SpaceID?
  /// The selected Space's name as typed.
  var nameDraft = ""
  /// Bumped to put the keyboard in the name field, as after Add.
  private(set) var nameFocusRequests = 0

  /// The name a Space gets from Add.
  static let newSpaceName = "New Space"

  /// Opens with `spaceID` selected, the window's Space.
  init(spaces: SpacesModel, selecting spaceID: SpaceID?) {
    self.spaces = spaces
    select(spaceID ?? spaces.spaces.first?.spaceID)
  }

  var selectedSpace: (any ClairSpace)? {
    selection.flatMap { spaces.space($0) }
  }

  /// Remove is off for the only Space.
  var canRemove: Bool {
    spaces.spaces.count > 1 && selectedSpace != nil
  }

  func select(_ spaceID: SpaceID?) {
    commitName()
    selection = spaceID.flatMap { spaces.space($0) }?.spaceID
    nameDraft = selectedSpace?.name ?? ""
  }

  /// Adds a Space named "New Space" after the last, on the selected Space's
  /// profile, selects it and focuses its name.
  func add() {
    commitName()
    guard let profileID = spaces.defaultProfile(after: selection),
      let spaceID = spaces.createSpace(named: Self.newSpaceName, icon: nil, profile: profileID)
    else { return }
    selection = spaceID
    nameDraft = Self.newSpaceName
    nameFocusRequests += 1
  }

  /// The name as typed, applied at once unless it's empty.
  func nameChanged() {
    guard let selection else { return }
    spaces.renameSpace(selection, to: nameDraft)
  }

  /// The name field lost focus: an emptied name reverts.
  func commitName() {
    guard let space = selectedSpace else { return }
    if SpacesLogic.cleanName(nameDraft).isEmpty {
      nameDraft = space.name
    } else {
      nameChanged()
    }
  }

  func setIcon(_ icon: String?) {
    guard let space = selectedSpace else { return }
    spaces.setIcon(icon, forSpace: space.spaceID)
  }

  /// A Space dragged in the list, to `index`.
  func move(_ spaceID: SpaceID, to index: Int) {
    spaces.moveSpace(spaceID, to: index)
  }

  /// The number of tabs a Space has, in every window.
  func tabCount(of spaceID: SpaceID) -> Int {
    spaces.rowCount(inSpace: spaceID)
  }

  /// After `spaceID` is removed: the Space before it is selected, or the one
  /// after when it was first.
  func removed(_ spaceID: SpaceID, at index: Int) {
    let remaining = spaces.spaces.filter { $0.spaceID != spaceID }
    selection = remaining.isEmpty ? nil : remaining[max(0, min(index - 1, remaining.count - 1))].spaceID
    nameDraft = selectedSpace?.name ?? ""
  }
}

/// Manage Spaces (spaces spec, "Manage Spaces dialog"): a ClairDialog with the
/// Spaces on the left, each with its icon, name and number of tabs, to select,
/// drag, add and remove, and the selected Space's name and icon on the right.
/// Its one button is "Done"; Esc closes it too.
@MainActor
enum ManageSpacesDialog {
  static let listWidth: CGFloat = 176
  static let height: CGFloat = 260

  /// Opens the dialog on the window, with `state`'s selection when it comes
  /// from another window of the group (add-profiles D12), or the window's
  /// Space.
  static func show(for controller: BrowserWindowController, state: ManageSpacesState? = nil) {
    let state = state ?? ManageSpacesState(spaces: controller.model.spaces, selecting: controller.model.shownSpaceID)
    let dialog = ClairDialog(page(state: state, remove: { _ in }, profile: { _ in }, newProfile: {}))
    // The page's Remove, profile popup and New Profile need the dialog, to
    // ask in place of the list.
    dialog.update {
      $0 = page(
        state: state,
        remove: { [weak dialog, weak controller] spaceID in
          guard let dialog, let controller else { return }
          remove(spaceID, state: state, dialog: dialog, controller: controller)
        },
        profile: { [weak dialog] profileID in
          guard let dialog else { return }
          setProfile(profileID, state: state, dialog: dialog)
        },
        newProfile: { [weak dialog] in
          guard let dialog else { return }
          ProfileDialogs.swapToNewProfile(in: dialog, spaces: state.spaces) { profileID in
            if let profileID {
              setProfile(profileID, state: state, dialog: dialog)
            }
          }
        })
    }
    controller.manageSpacesDidOpen(state, dialog: dialog)
    controller.dialogs.show(dialog) { [weak controller] answer in
      state.commitName()
      controller?.manageSpacesDidClose(state)
    }
  }

  static func page(
    state: ManageSpacesState, remove: @escaping @MainActor (SpaceID) -> Void,
    profile: @escaping @MainActor (ProfileID) -> Void, newProfile: @escaping @MainActor () -> Void
  ) -> ClairDialogPage {
    ClairDialogPage(
      title: "Manage Spaces",
      content: AnyView(
        ManageSpacesView(state: state, onRemove: remove, onProfile: profile, onNewProfile: newProfile)),
      buttons: [ClairDialogButton(title: "Done", role: .default)],
      escapePressesDefault: true)
  }

  /// Gives the selected Space another profile: at once without tabs, or
  /// after asking in place of the list (profiles spec, "Changing a Space's
  /// profile").
  static func setProfile(_ profileID: ProfileID, state: ManageSpacesState, dialog: ClairDialog) {
    guard let spaceID = state.selection, let change = state.spaces.profileChange(of: spaceID, to: profileID) else {
      return
    }
    guard change.needsConfirmation else {
      state.spaces.setProfile(profileID, forSpace: spaceID)
      return
    }
    dialog.swap(
      to: BrowserWindowController.profileChangePage(
        for: change,
        confirm: { dialog in
          dialog.swapBack()
          state.spaces.setProfile(profileID, forSpace: spaceID)
        },
        cancel: { dialog in dialog.swapBack() }))
  }

  /// Removes a Space: at once without tabs, or after asking in place of the
  /// list, with Delete Space's rules (spaces spec, "Editing Spaces in the
  /// dialog").
  static func remove(
    _ spaceID: SpaceID, state: ManageSpacesState, dialog: ClairDialog, controller: BrowserWindowController
  ) {
    let spaces = state.spaces
    guard let deletion = spaces.deletion(of: spaceID), let index = spaces.index(of: spaceID) else { return }
    let delete = {
      spaces.deleteSpace(spaceID)
      state.removed(spaceID, at: index)
    }
    guard deletion.needsConfirmation else {
      delete()
      return
    }
    dialog.swap(
      to: BrowserWindowController.deletionPage(
        for: deletion.space, tabCount: deletion.tabCount,
        confirm: { dialog in
          delete()
          dialog.swapBack()
        },
        cancel: { dialog in dialog.swapBack() }))
  }
}

/// The dialog's two columns.
struct ManageSpacesView: View {
  @Bindable var state: ManageSpacesState
  let onRemove: @MainActor (SpaceID) -> Void
  let onProfile: @MainActor (ProfileID) -> Void
  let onNewProfile: @MainActor () -> Void

  @FocusState private var nameFocused: Bool
  @State private var editsIcon = false

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      VStack(spacing: 0) {
        ManageSpacesList(state: state)
        HStack(spacing: 0) {
          Button {
            state.add()
          } label: {
            Image(systemName: "plus").frame(width: 24, height: 22)
          }
          .help("Add Space")
          .accessibilityIdentifier("clair.manageSpacesAdd")
          Button {
            if let selection = state.selection { onRemove(selection) }
          } label: {
            Image(systemName: "minus").frame(width: 24, height: 22)
          }
          .disabled(!state.canRemove)
          .help("Remove Space")
          .accessibilityIdentifier("clair.manageSpacesRemove")
          Spacer(minLength: 0)
        }
        .buttonStyle(.borderless)
        .padding(.top, 4)
      }
      .frame(width: ManageSpacesDialog.listWidth)
      VStack(alignment: .leading, spacing: 8) {
        Text("Name").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
        TextField("Space name", text: $state.nameDraft)
          .textFieldStyle(.roundedBorder)
          .focused($nameFocused)
          .onChange(of: state.nameDraft) { state.nameChanged() }
          .onSubmit { state.commitName() }
          .onChange(of: nameFocused) { _, focused in
            if !focused { state.commitName() }
          }
          .accessibilityIdentifier("clair.manageSpacesName")
        Text("Icon").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).padding(.top, 6)
        Button {
          editsIcon = true
        } label: {
          Group {
            if editsIcon || state.selectedSpace?.icon != nil {
              SpaceIconField(
                icon: state.selectedSpace?.icon, size: 20, isEditing: editsIcon,
                onChange: { state.setIcon($0) }, onEnd: { editsIcon = false })
            } else {
              Image(systemName: "face.smiling").foregroundStyle(.secondary)
            }
          }
          .frame(width: 36, height: 36)
          .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .help("Choose an Icon")
        .accessibilityIdentifier("clair.manageSpacesIcon")
        Text("Profile").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).padding(.top, 6)
        ProfilePopup(
          profiles: state.spaces.profiles, selection: state.selectedSpace?.profileID,
          onSelect: { onProfile($0) }, onNewProfile: { onNewProfile() })
        Spacer(minLength: 0)
      }
      .disabled(state.selectedSpace == nil)
    }
    .frame(height: ManageSpacesDialog.height)
    .onChange(of: state.nameFocusRequests) { nameFocused = true }
  }

}

/// The dialog's list of Spaces: a click selects a row, and dragging one moves
/// its Space to the row it's dropped on. Rows rather than a List, whose own
/// drag and drop didn't start in the dialog.
struct ManageSpacesList: View {
  @Bindable var state: ManageSpacesState

  static let rowHeight: CGFloat = 26

  @State private var dragged: SpaceID?
  @State private var dragOffset: CGFloat = 0
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let spaces = state.spaces.spaces
    ScrollView {
      VStack(spacing: 0) {
        ForEach(spaces, id: \.spaceID) { space in
          let selected = space.spaceID == state.selection
          ManageSpacesRow(space: space, tabCount: state.tabCount(of: space.spaceID), isSelected: selected)
            .padding(.horizontal, 8)
            .frame(height: Self.rowHeight)
            .background {
              if selected {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.accentColor)
              }
            }
            .contentShape(Rectangle())
            .offset(y: dragged == space.spaceID ? dragOffset : 0)
            .zIndex(dragged == space.spaceID ? 1 : 0)
            .onTapGesture { state.select(space.spaceID) }
            .gesture(
              SpaceReorderDrag.gesture(
                for: space.spaceID, in: spaces.map(\.spaceID), along: .vertical, pitch: Self.rowHeight,
                dragged: $dragged, offset: $dragOffset
              ) { spaceID, index in
                state.move(spaceID, to: index)
              })
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("clair.manageSpacesRow")
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
      }
      .padding(4)
    }
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.8)))
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("clair.manageSpacesList")
  }
}

/// A Space in the dialog's list: its icon or a dot, its name and its number
/// of tabs.
struct ManageSpacesRow: View {
  let space: any ClairSpace
  let tabCount: Int
  var isSelected = false

  var body: some View {
    HStack(spacing: 8) {
      Group {
        if let icon = space.icon {
          Text(icon).font(.system(size: 14))
        } else {
          Circle().fill(Color.primary.opacity(0.35)).frame(width: 6, height: 6)
        }
      }
      .frame(width: 18)
      Text(space.name).lineLimit(1)
      Spacer(minLength: 4)
      if tabCount > 0 {
        Text("\(tabCount)").font(.system(size: 11)).monospacedDigit()
          .foregroundStyle(isSelected ? AnyShapeStyle(Color.white.opacity(0.8)) : AnyShapeStyle(.secondary))
      }
    }
    .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(space.name), \(tabCount == 1 ? "1 tab" : "\(tabCount) tabs")")
  }
}
