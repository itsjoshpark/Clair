// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Observation
import SwiftUI

/// The text typed into a profile dialog's field.
@MainActor
@Observable
final class ProfileNameState {
  var text: String {
    didSet { onChange?() }
  }
  /// Runs on each change, to enable the dialog's button.
  @ObservationIgnored var onChange: (() -> Void)?
  /// Runs on Return in the field.
  @ObservationIgnored var onSubmit: (() -> Void)?

  init(text: String = "") {
    self.text = text
  }
}

/// The New, Rename and Delete profile dialogs (add-profiles design D12), as
/// `ClairDialog`s worded after Arc's sheets (add-spaces' arc-reference.md,
/// "Profile sheets"). Each can show on its own or swap into a dialog already
/// on the window, as in Manage Spaces.
@MainActor
enum ProfileDialogs {
  // MARK: Wording

  static let newTitle = "Create a new Profile"
  static let newMessage =
    "Profiles make your Spaces truly separate — with their own history, logins, extensions, and other browsing "
    + "data. No more flipping between work and personal accounts!"
  static let newQuestion = "What do you want to call this Profile?"
  static let newPlaceholder = "Personal"
  static let newFootnote = "Profiles are not synced between computers."
  static let newButton = "Create Profile"

  static let renameTitle = "Rename your Profile"
  static let renameMessage = "This won’t affect the names of any of the Spaces associated with this Profile."
  static let renameButton = "Save"

  static let deleteTitle = "Delete this Profile"
  static func deleteMessage(_ name: String) -> String {
    "Deleting “\(name)” will permanently remove any cookies, history, preferences, and logins that belong to "
      + "this Profile. To continue, please type the name of this Profile:"
  }
  static let deleteButton = "Delete"

  // MARK: Rules

  /// "Create Profile" and "Save" need a name.
  static func canSave(_ text: String) -> Bool {
    !SpacesLogic.cleanName(text).isEmpty
  }

  /// "Delete" needs the profile's name, exactly.
  static func canDelete(typed text: String, name: String) -> Bool {
    SpacesLogic.cleanName(text) == name
  }

  // MARK: Pages

  /// A button's action, or nil to answer with its role.
  typealias Action = @MainActor (ClairDialog) -> Void

  static func newProfilePage(state: ProfileNameState, create: Action? = nil, cancel: Action? = nil)
    -> ClairDialogPage
  {
    ClairDialogPage(
      title: newTitle, message: newMessage,
      content: AnyView(
        ProfileNameField(
          state: state, question: newQuestion, placeholder: newPlaceholder, footnote: newFootnote,
          identifier: "clair.newProfileName")),
      buttons: [
        ClairDialogButton(title: "Cancel", role: .cancel, action: cancel),
        ClairDialogButton(title: newButton, role: .default, isEnabled: canSave(state.text), action: create),
      ])
  }

  static func renamePage(state: ProfileNameState) -> ClairDialogPage {
    ClairDialogPage(
      title: renameTitle, message: renameMessage,
      content: AnyView(
        ProfileNameField(state: state, placeholder: state.text, identifier: "clair.renameProfileName")),
      buttons: [
        ClairDialogButton(title: "Cancel", role: .cancel),
        ClairDialogButton(title: renameButton, role: .default, isEnabled: canSave(state.text)),
      ])
  }

  static func deletePage(name: String, state: ProfileNameState) -> ClairDialogPage {
    ClairDialogPage(
      title: deleteTitle, message: deleteMessage(name),
      content: AnyView(ProfileNameField(state: state, placeholder: name, identifier: "clair.deleteProfileName")),
      buttons: [
        ClairDialogButton(title: "Cancel", role: .cancel),
        ClairDialogButton(
          title: deleteButton, role: .destructive, isEnabled: canDelete(typed: state.text, name: name)),
      ])
  }

  /// The field's state of the profile page on top of each dialog, kept for
  /// as long as the dialog lives.
  private static let states = NSMapTable<ClairDialog, ProfileNameState>.weakToStrongObjects()

  /// What's typed in `dialog`'s profile field, if it shows a profile page.
  static func nameState(of dialog: ClairDialog) -> ProfileNameState? {
    states.object(forKey: dialog)
  }

  /// Keeps the default button of the page on top of `dialog` enabled by
  /// `enabled`, and makes Return in the field press it.
  private static func bind(_ state: ProfileNameState, to dialog: ClairDialog, enabled: @escaping (String) -> Bool) {
    states.setObject(state, forKey: dialog)
    state.onChange = { [weak dialog, weak state] in
      guard let dialog, let state else { return }
      dialog.update { page in
        for index in page.buttons.indices where page.buttons[index].isDefault {
          page.buttons[index].isEnabled = enabled(state.text)
        }
      }
    }
    state.onSubmit = { [weak dialog] in
      guard let dialog, let button = dialog.page.buttons.first(where: \.isDefault) else { return }
      dialog.press(button)
    }
  }

  // MARK: Showing

  /// Asks for a new profile's name on `presenter`'s window and creates it.
  /// `completion` gets the new profile's ID once it exists, or nil when the
  /// user cancels or it can't be created.
  @discardableResult
  static func showNewProfile(
    on presenter: ClairDialogPresenter, spaces: SpacesModel,
    completion: @escaping @MainActor (ProfileID?) -> Void = { _ in }
  ) -> ClairDialog {
    let state = ProfileNameState()
    let dialog = ClairDialog(newProfilePage(state: state))
    bind(state, to: dialog, enabled: canSave)
    presenter.show(dialog) { answer in
      guard answer == .accepted else {
        completion(nil)
        return
      }
      spaces.createProfile(named: state.text, completion: completion)
    }
    return dialog
  }

  /// Swaps the New Profile page into `dialog`, as in Manage Spaces, and swaps
  /// back once it's answered.
  static func swapToNewProfile(
    in dialog: ClairDialog, spaces: SpacesModel, completion: @escaping @MainActor (ProfileID?) -> Void
  ) {
    let state = ProfileNameState()
    let page = newProfilePage(
      state: state,
      create: { dialog in
        guard canSave(state.text) else { return }
        dialog.swapBack()
        spaces.createProfile(named: state.text, completion: completion)
      },
      cancel: { dialog in
        dialog.swapBack()
        completion(nil)
      })
    dialog.swap(to: page)
    bind(state, to: dialog, enabled: canSave)
  }

  /// Asks for a profile's new name and renames it.
  @discardableResult
  static func showRename(of profile: any ClairProfile, on presenter: ClairDialogPresenter, spaces: SpacesModel)
    -> ClairDialog
  {
    let state = ProfileNameState(text: profile.name)
    let dialog = ClairDialog(renamePage(state: state))
    bind(state, to: dialog, enabled: canSave)
    let profileID = profile.profileID
    presenter.show(dialog) { answer in
      if answer == .accepted {
        spaces.renameProfile(profileID, to: state.text)
      }
    }
    return dialog
  }

  /// Asks the user to type a profile's name, then deletes it. `completion`
  /// says whether it did.
  @discardableResult
  static func showDelete(
    of profile: any ClairProfile, on presenter: ClairDialogPresenter, spaces: SpacesModel,
    completion: @escaping @MainActor (Bool) -> Void = { _ in }
  ) -> ClairDialog {
    let state = ProfileNameState()
    let name = profile.name
    let dialog = ClairDialog(deletePage(name: name, state: state))
    bind(state, to: dialog) { canDelete(typed: $0, name: name) }
    let profileID = profile.profileID
    presenter.show(dialog) { answer in
      let delete = answer == .accepted && canDelete(typed: state.text, name: name) && spaces.canDeleteProfile(profileID)
      if delete {
        spaces.deleteProfile(profileID)
      }
      completion(delete)
    }
    return dialog
  }
}

/// A profile dialog's field, with an optional question above it and a note
/// below.
struct ProfileNameField: View {
  @Bindable var state: ProfileNameState
  var question: String?
  let placeholder: String
  var footnote: String?
  let identifier: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let question {
        Text(question).font(.system(size: 13, weight: .medium))
      }
      TextField(placeholder, text: $state.text)
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 14))
        .onSubmit { state.onSubmit?() }
        .accessibilityIdentifier(identifier)
      if let footnote {
        Text(footnote)
          .font(.system(size: 12))
          .foregroundStyle(Color(nsColor: ClairDialogView.secondaryTextColor))
      }
    }
  }
}
