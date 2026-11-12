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
  @Environment(\.colorScheme) private var colorScheme

  private var form: NewSpaceFormState { model.newSpaceForm ?? NewSpaceFormState() }

  var body: some View {
    VStack(alignment: .center, spacing: 0) {
      NewSpaceIllustration()
        .padding(.top, 40)
      VStack(alignment: .center, spacing: 6) {
        Text("Create a Space")
          .font(.system(size: 17, weight: .semibold))
        Text("Separate your tabs for life, work, projects, and more.")
          .font(.system(size: 13))
          .foregroundStyle(.primary.opacity(0.75))
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.top, 14)
      HStack(spacing: 6) {
        Button {
          editsIcon = true
        } label: {
          Group {
            if editsIcon || form.icon != nil {
              SpaceIconField(
                icon: form.icon, size: 15, isEditing: editsIcon,
                onChange: { model.newSpaceForm?.icon = $0 },
                onEnd: {
                  editsIcon = false
                  nameFocused = true
                })
            } else {
              // Arc's icon button: a "+" in a dashed square.
              Image(systemName: "plus")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .overlay {
                  RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .foregroundStyle(.secondary)
                }
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
      // Arc's field is nearly white in Light Mode.
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.75))
          .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.05), radius: 0.5, y: 0.5))
      .padding(.top, 22)
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

/// Arc's picture above the form: three cards fanned out, with an emoji each.
struct NewSpaceIllustration: View {
  static let cards: [(emoji: String, angle: Double, x: CGFloat)] = [("🌴", -14, -18), ("📚", 14, 18), ("💻", 0, 0)]

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    ZStack {
      ForEach(Self.cards, id: \.emoji) { card in
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .fill(colorScheme == .dark ? Color(white: 0.3) : .white)
          .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
          .overlay(Text(card.emoji).font(.system(size: 16)))
          .frame(width: 28, height: 34)
          .rotationEffect(.degrees(card.angle))
          .offset(x: card.x)
      }
    }
    .frame(height: 40)
    .accessibilityHidden(true)
  }
}
