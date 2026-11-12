// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import ClairHost
import SwiftUI

/// The New Space form, in place of the Space header and the tab list, as in
/// Arc (spaces spec, "Creating a Space"): "Create a Space" and its line, the
/// name field with the icon button at its leading end, focused, and at the
/// bottom "Create Space", off until a name is typed, and "Cancel". Esc
/// cancels; Return creates.
struct NewSpaceFormView: View {
  @Bindable var model: BrowserWindowModel
  weak var actions: (any SpaceActions)?

  static let fieldHeight: CGFloat = 36
  static let buttonHeight: CGFloat = 36
  static let horizontalInset: CGFloat = 14

  @FocusState private var nameFocused: Bool
  @State private var editsIcon = false

  private var form: NewSpaceFormState { model.newSpaceForm ?? NewSpaceFormState() }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Create a Space")
          .font(.system(size: 17, weight: .semibold))
        Text("Separate your tabs for life, work, projects, and more.")
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.top, 18)
      HStack(spacing: 6) {
        Button {
          editsIcon = true
        } label: {
          Group {
            if editsIcon || form.icon != nil {
              SpaceIconField(
                icon: form.icon, size: 16, isEditing: editsIcon,
                onChange: { model.newSpaceForm?.icon = $0 },
                onEnd: {
                  editsIcon = false
                  nameFocused = true
                })
            } else {
              Image(systemName: "face.smiling").foregroundStyle(.secondary)
            }
          }
          .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .help("Choose an Icon")
        .accessibilityIdentifier("clair.newSpaceIcon")
        TextField("Space name…", text: nameBinding)
          .textFieldStyle(.plain)
          .font(.system(size: 14))
          .focused($nameFocused)
          .onSubmit(create)
          .accessibilityIdentifier("clair.newSpaceName")
      }
      .padding(.horizontal, 8)
      .frame(height: Self.fieldHeight)
      .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
      .padding(.top, 16)
      Spacer(minLength: 16)
      Button(action: create) {
        Text("Create Space")
          .font(.system(size: 14, weight: .semibold))
          .frame(maxWidth: .infinity, minHeight: Self.buttonHeight)
          .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .fill(Color.accentColor.opacity(form.canCreate ? 1 : 0.4)))
          .foregroundStyle(.white)
      }
      .buttonStyle(.plain)
      .disabled(!form.canCreate)
      .accessibilityIdentifier("clair.createSpace")
      Button {
        actions?.cancelNewSpace()
      } label: {
        Text("Cancel")
          .font(.system(size: 14))
          .frame(maxWidth: .infinity, minHeight: Self.buttonHeight)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .padding(.top, 4)
      .padding(.bottom, 8)
      .accessibilityIdentifier("clair.cancelNewSpace")
    }
    .padding(.horizontal, Self.horizontalInset)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .onExitCommand { actions?.cancelNewSpace() }
    .onAppear { nameFocused = true }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("clair.newSpaceForm")
  }

  private var nameBinding: Binding<String> {
    Binding(get: { model.newSpaceForm?.name ?? "" }, set: { model.newSpaceForm?.name = $0 })
  }

  private func create() {
    guard form.canCreate else { return }
    actions?.createSpace(named: SpacesLogic.cleanName(form.name), icon: form.icon)
  }
}
