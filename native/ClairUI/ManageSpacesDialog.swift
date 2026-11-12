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

  /// Adds a Space named "New Space" after the last, selects it and focuses
  /// its name.
  func add() {
    commitName()
    guard let spaceID = spaces.host?.createSpace(named: Self.newSpaceName, icon: nil) else { return }
    selection = spaceID
    nameDraft = Self.newSpaceName
    nameFocusRequests += 1
  }

  /// The name as typed, applied at once unless it's empty.
  func nameChanged() {
    guard let space = selectedSpace else { return }
    let name = SpacesLogic.cleanName(nameDraft)
    if !name.isEmpty, name != space.name {
      spaces.host?.renameSpace(space.spaceID, to: name)
    }
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
    spaces.host?.setIcon(icon, forSpace: space.spaceID)
  }

  /// A drag in the list, with SwiftUI's offsets.
  func move(from source: IndexSet, to destination: Int) {
    guard let from = source.first,
      let target = TabListLogic.moveTarget(from: from, to: destination, count: spaces.spaces.count)
    else { return }
    spaces.host?.moveSpace(spaces.spaces[from].spaceID, to: target)
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

  static func show(for controller: BrowserWindowController) {
    let state = ManageSpacesState(spaces: controller.model.spaces, selecting: controller.model.shownSpaceID)
    let dialog = ClairDialog(page(state: state, remove: { _ in }))
    // The page's Remove needs the dialog, to ask in place of the list.
    dialog.update { $0 = page(state: state, remove: { [weak dialog, weak controller] spaceID in
      guard let dialog, let controller else { return }
      remove(spaceID, state: state, dialog: dialog, controller: controller)
    }) }
    controller.dialogs.show(dialog) { _ in state.commitName() }
  }

  static func page(state: ManageSpacesState, remove: @escaping @MainActor (SpaceID) -> Void) -> ClairDialogPage {
    ClairDialogPage(
      title: "Manage Spaces",
      content: AnyView(ManageSpacesView(state: state, onRemove: remove)),
      buttons: [ClairDialogButton(title: "Done", role: .default)],
      escapePressesDefault: true)
  }

  /// Removes a Space: at once without tabs, or after asking in place of the
  /// list, with Delete Space's rules (spaces spec, "Editing Spaces in the
  /// dialog").
  static func remove(
    _ spaceID: SpaceID, state: ManageSpacesState, dialog: ClairDialog, controller: BrowserWindowController
  ) {
    guard state.canRemove, let space = state.spaces.space(spaceID),
      let index = state.spaces.index(of: spaceID)
    else { return }
    let tabCount = state.tabCount(of: spaceID)
    let host = state.spaces.host
    guard SpacesLogic.deletionNeedsConfirmation(tabCount: tabCount) else {
      host?.deleteSpace(spaceID)
      state.removed(spaceID, at: index)
      return
    }
    dialog.swap(
      to: BrowserWindowController.deletionPage(
        for: space, tabCount: tabCount,
        confirm: { dialog in
          host?.deleteSpace(spaceID)
          state.removed(spaceID, at: index)
          dialog.swapBack()
        },
        cancel: { dialog in dialog.swapBack() }))
  }
}

/// The dialog's two columns.
struct ManageSpacesView: View {
  @Bindable var state: ManageSpacesState
  let onRemove: @MainActor (SpaceID) -> Void

  @FocusState private var nameFocused: Bool
  @State private var editsIcon = false

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      VStack(spacing: 0) {
        List(selection: selectionBinding) {
          ForEach(state.spaces.spaces, id: \.spaceID) { space in
            ManageSpacesRow(space: space, tabCount: state.tabCount(of: space.spaceID))
              .tag(space.spaceID)
          }
          .onMove { state.move(from: $0, to: $1) }
        }
        .listStyle(.bordered)
        .accessibilityIdentifier("clair.manageSpacesList")
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
        Spacer(minLength: 0)
      }
      .disabled(state.selectedSpace == nil)
    }
    .frame(height: ManageSpacesDialog.height)
    .onChange(of: state.nameFocusRequests) { nameFocused = true }
  }

  private var selectionBinding: Binding<SpaceID?> {
    Binding(get: { state.selection }, set: { state.select($0) })
  }
}

/// A Space in the dialog's list: its icon or a dot, its name and its number
/// of tabs.
struct ManageSpacesRow: View {
  let space: any ClairSpace
  let tabCount: Int

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
        Text("\(tabCount)").font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(space.name), \(tabCount == 1 ? "1 tab" : "\(tabCount) tabs")")
  }
}
