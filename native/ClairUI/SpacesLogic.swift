// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import ClairHost
import Foundation

/// The Spaces' logic that the sidebar, the menu bar and Manage Spaces share
/// (add-spaces design D10), kept apart from the views so it can be tested.
enum SpacesLogic {
  // MARK: Switching

  /// The Space `step` places after `spaceID` in the order, wrapping around at
  /// the ends, as Next and Previous Space do in Arc. Nil with fewer than two
  /// Spaces or for an unknown one.
  static func neighbour(of spaceID: SpaceID, by step: Int, in spaces: [any ClairSpace]) -> SpaceID? {
    guard spaces.count > 1, let index = spaces.firstIndex(where: { $0.spaceID == spaceID }) else { return nil }
    let count = spaces.count
    return spaces[((index + step) % count + count) % count].spaceID
  }

  /// The Space Ctrl+`number` shows: the first nine, counting from 1.
  static func space(number: Int, in spaces: [any ClairSpace]) -> SpaceID? {
    guard (1...9).contains(number), number <= spaces.count else { return nil }
    return spaces[number - 1].spaceID
  }

  /// Which side the new Space slides in from: the trailing one for a Space
  /// later in the order (spaces spec, "Switching animation").
  static func slidesFromTrailing(to spaceID: SpaceID, from previous: SpaceID, in spaces: [any ClairSpace]) -> Bool {
    guard let to = spaces.firstIndex(where: { $0.spaceID == spaceID }),
      let from = spaces.firstIndex(where: { $0.spaceID == previous })
    else { return true }
    return to > from
  }

  // MARK: The footer's switcher

  struct SwitcherItem: Equatable, Identifiable {
    let spaceID: SpaceID
    let name: String
    /// The Space's emoji, or nil for a dot.
    let icon: String?
    let isCurrent: Bool
    /// For the runtime suite: "clair.space.1" for the first Space.
    let identifier: String

    var id: SpaceID { spaceID }

    /// The same item, not marked current, as while the New Space form shows.
    var notCurrent: SwitcherItem {
      SwitcherItem(spaceID: spaceID, name: name, icon: icon, isCurrent: false, identifier: identifier)
    }
  }

  /// One item per Space, in order, or none with one Space unless
  /// `includingOne`, as while the New Space form shows.
  static func switcherItems(_ spaces: [any ClairSpace], shown: SpaceID, includingOne: Bool = false)
    -> [SwitcherItem]
  {
    guard spaces.count > 1 || (includingOne && !spaces.isEmpty) else { return [] }
    return spaces.enumerated().map { index, space in
      SwitcherItem(
        spaceID: space.spaceID, name: space.name, icon: space.icon, isCurrent: space.spaceID == shown,
        identifier: "clair.space.\(index + 1)")
    }
  }

  /// Where an item at `index` of `count`, dragged `translation` points along
  /// a strip of items `pitch` apart, lands: the nearest slot, clamped to the
  /// strip.
  static func dragTarget(from index: Int, translation: CGFloat, pitch: CGFloat, count: Int) -> Int {
    guard count > 0, pitch > 0 else { return index }
    let target = index + Int((translation / pitch).rounded())
    return min(max(target, 0), count - 1)
  }

  // MARK: Menus

  /// An item of the Space header's menu (spaces spec, "Space header").
  struct MenuItem: Equatable {
    enum Command: Equatable {
      case changeIcon, rename, manage, delete
    }

    let title: String
    let command: Command
    let isEnabled: Bool
  }

  /// The header's menu, a nil for each separator: Delete Space is off for the
  /// only Space.
  static func headerMenu(spaceCount: Int) -> [MenuItem?] {
    [
      MenuItem(title: "Change Space Icon…", command: .changeIcon, isEnabled: true),
      MenuItem(title: "Rename Space…", command: .rename, isEnabled: true),
      nil,
      MenuItem(title: "Manage Spaces…", command: .manage, isEnabled: true),
      nil,
      MenuItem(title: "Delete Space", command: .delete, isEnabled: spaceCount > 1),
    ]
  }

  /// The Spaces a tab of `spaceID` can move to, in order: every other one.
  /// Empty with one Space, so the tab's menu has no "Move to Space".
  static func moveTargets(from spaceID: SpaceID, in spaces: [any ClairSpace]) -> [any ClairSpace] {
    spaces.count > 1 ? spaces.filter { $0.spaceID != spaceID } : []
  }

  /// A Space's name with its icon before it, as menus show it.
  static func label(of space: any ClairSpace) -> String {
    guard let icon = space.icon, !icon.isEmpty else { return space.name }
    return "\(icon) \(space.name)"
  }

  // MARK: Deleting

  /// Whether deleting a Space asks first: only when it has tabs, in any
  /// window (spaces spec, "Deleting a Space").
  static func deletionNeedsConfirmation(tabCount: Int) -> Bool {
    tabCount > 0
  }

  /// Text for the confirmation, worded for Clair: its tabs close.
  static func deletionTitle(_ name: String) -> String {
    "Delete the “\(name)” Space?"
  }

  static func deletionMessage(tabCount: Int) -> String {
    tabCount == 1 ? "Its tab will close." : "Its \(tabCount) tabs will close."
  }

  // MARK: Names

  /// A name as typed, without the spaces around it; empty when it has none.
  static func cleanName(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

/// A Space's icon is one emoji (add-spaces design D10).
enum SpaceIcon {
  /// What typing or picking `text` into the icon field does.
  enum Edit: Equatable {
    /// The icon becomes this emoji.
    case set(String)
    /// The icon goes.
    case clear
    /// The icon stays as it was: `text` has no emoji.
    case unchanged
  }

  /// Keeps the first emoji of `text`, with its skin tone or joined parts; an
  /// empty `text` clears the icon, and text with no emoji changes nothing.
  static func edit(for text: String) -> Edit {
    if text.isEmpty { return .clear }
    guard let emoji = text.first(where: isEmoji) else { return .unchanged }
    return .set(String(emoji))
  }

  /// Whether a character is an emoji that shows as one: a digit or "#" can
  /// start an emoji sequence but isn't one alone.
  static func isEmoji(_ character: Character) -> Bool {
    let scalars = character.unicodeScalars
    guard let first = scalars.first else { return false }
    if scalars.contains(where: { $0.properties.isEmojiPresentation }) {
      return true
    }
    // A text-default symbol such as ✈ made an emoji by its selector, or a
    // keycap sequence.
    return first.properties.isEmoji && scalars.count > 1
  }
}

/// What the New Space form holds (spaces spec, "Creating a Space").
struct NewSpaceFormState: Equatable {
  var name = ""
  var icon: String?

  /// "Create Space" is off until a name is typed.
  var canCreate: Bool { !SpacesLogic.cleanName(name).isEmpty }
}
