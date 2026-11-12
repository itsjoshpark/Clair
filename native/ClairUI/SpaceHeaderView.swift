// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import SwiftUI

/// What the Space views ask the window to do (add-spaces design D10).
@MainActor
protocol SpaceActions: AnyObject {
  func showSpace(_ spaceID: SpaceID)
  /// The New Space form, in place of the header and the list.
  func beginNewSpace()
  func cancelNewSpace()
  func createSpace(named name: String, icon: String?)
  /// Inline renaming and the icon field in the header.
  func beginRenamingSpace()
  func beginChangingSpaceIcon()
  func endEditingSpaceHeader()
  func renameSpace(_ spaceID: SpaceID, to name: String)
  func setIcon(_ icon: String?, forSpace spaceID: SpaceID)
  /// Asks first when the Space has tabs.
  func deleteSpace(_ spaceID: SpaceID)
  func moveSpace(_ spaceID: SpaceID, to index: Int)
  func moveTab(_ tab: TabID, toSpace spaceID: SpaceID)
  func manageSpaces()
}

/// What the Space header is editing, if anything.
enum SpaceHeaderEdit: Equatable {
  case renaming
  case icon
}

/// The current Space's icon and name above the tab list, as in Arc: the icon
/// 26 pt across from 13 pt in, the name 18 pt high after it, or from 13 pt in
/// without an icon. Right-clicking it opens its menu; Rename Space… turns the
/// name into a field, with "Done" where Arc's More button is.
struct SpaceHeaderView: View {
  let model: BrowserWindowModel
  /// The Space it shows: the window's, or the one sliding out.
  let space: (any ClairSpace)?
  weak var actions: (any SpaceActions)?

  static let height: CGFloat = 32
  /// Room under the header, so the name's centre sits 41 pt above the "New
  /// Tab" row's, as in Arc.
  static let bottomGap: CGFloat = 4.5
  static let leading: CGFloat = 13
  static let iconSize: CGFloat = 26
  static let nameGap: CGFloat = 2
  /// Arc's name: 13 pt semibold, in the sidebar's secondary grey.
  static let nameFont = Font.system(size: 13, weight: .semibold)

  @State private var draft = ""
  @FocusState private var nameFocused: Bool

  private var isCurrent: Bool { space?.spaceID == model.shownSpaceID }
  private var edit: SpaceHeaderEdit? { isCurrent ? model.spaceHeaderEdit : nil }

  var body: some View {
    HStack(spacing: Self.nameGap) {
      if edit == .icon || space?.icon != nil {
        icon
      }
      if edit == .renaming {
        TextField("Space name", text: $draft)
          .textFieldStyle(.plain)
          .font(Self.nameFont)
          .focused($nameFocused)
          .onSubmit { commitName() }
          .onExitCommand { actions?.endEditingSpaceHeader() }
          .onAppear {
            draft = space?.name ?? ""
            nameFocused = true
          }
          .accessibilityIdentifier("clair.spaceNameField")
        Button("Done") { commitName() }
          .buttonStyle(.borderless)
          .font(.system(size: 12, weight: .medium))
          .accessibilityIdentifier("clair.spaceRenameDone")
      } else {
        Text(space?.name ?? "")
          .font(Self.nameFont)
          .lineLimit(1)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("clair.spaceName")
        Spacer(minLength: 0)
      }
    }
    .padding(.leading, Self.leading)
    .padding(.trailing, 13)
    .frame(height: Self.height)
    .contentShape(Rectangle())
    .padding(.bottom, Self.bottomGap)
    .overlay {
      if edit == nil {
        RowClickCatcher(onMiddleClick: {}, menuItems: menuItems)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("clair.spaceHeader")
  }

  @ViewBuilder private var icon: some View {
    SpaceIconField(
      icon: space?.icon, size: 18, isEditing: edit == .icon,
      onChange: { icon in
        if let space { actions?.setIcon(icon, forSpace: space.spaceID) }
      },
      onEnd: { actions?.endEditingSpaceHeader() }
    )
    .frame(width: Self.iconSize, height: Self.iconSize)
    .overlay {
      // Arc shows a dashed square where the icon goes while the picker is
      // open.
      if edit == .icon {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
          .foregroundStyle(.secondary)
          .allowsHitTesting(false)
      }
    }
  }

  private func commitName() {
    if let space {
      let name = SpacesLogic.cleanName(draft)
      // An empty name keeps the earlier one.
      if !name.isEmpty, name != space.name {
        actions?.renameSpace(space.spaceID, to: name)
      }
    }
    actions?.endEditingSpaceHeader()
  }

  /// The header's menu (spaces spec, "Space header").
  private var menuItems: [RowClickCatcher.Item] {
    guard let space else { return [] }
    return SpacesLogic.headerMenu(spaceCount: model.spaces.spaces.count).map { item in
      guard let item else { return .separator }
      guard item.isEnabled else { return .disabled(item.title) }
      return .action(item.title) { [weak actions] in
        switch item.command {
        case .changeIcon: actions?.beginChangingSpaceIcon()
        case .rename: actions?.beginRenamingSpace()
        case .manage: actions?.manageSpaces()
        case .delete: actions?.deleteSpace(space.spaceID)
        }
      }
    }
  }
}
