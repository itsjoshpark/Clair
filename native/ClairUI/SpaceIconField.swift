// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import SwiftUI

/// A Space's icon as a one-emoji field (add-spaces design D10). While it has
/// focus, macOS's emoji picker is open; it keeps the first emoji of whatever
/// is entered (`SpaceIcon.edit(for:)`), ignores text that isn't an emoji and
/// clears on Delete. Return, Esc or losing focus ends the edit.
struct SpaceIconField: NSViewRepresentable {
  /// The icon it shows, or nil for none.
  let icon: String?
  /// The point size of the emoji.
  var size: CGFloat = 18
  /// Whether it takes focus, and opens the emoji picker, as it appears or
  /// when this becomes true.
  var isEditing: Bool
  /// What to show where there's no icon while it isn't being edited.
  var placeholder: String = ""
  /// The icon changed: a new emoji, or nil once deleted.
  let onChange: (String?) -> Void
  /// The edit ended, by Return, Esc or focus leaving the field.
  var onEnd: () -> Void = {}

  func makeNSView(context: Context) -> IconTextField {
    let field = IconTextField()
    field.delegate = context.coordinator
    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.alignment = .center
    field.cell?.usesSingleLineMode = true
    field.cell?.lineBreakMode = .byClipping
    field.setAccessibilityIdentifier("clair.spaceIconField")
    return field
  }

  func updateNSView(_ field: IconTextField, context: Context) {
    context.coordinator.parent = self
    field.font = .systemFont(ofSize: size)
    field.placeholderString = placeholder
    if field.currentEditor() == nil, field.stringValue != (icon ?? "") {
      field.stringValue = icon ?? ""
    }
    field.isEditable = isEditing
    field.isSelectable = isEditing
    if isEditing, !context.coordinator.wasEditing {
      context.coordinator.begin()
      // Now if the field is in a window, or else once SwiftUI puts it in
      // one, as when editing makes the field appear.
      field.wantsPicking = true
      DispatchQueue.main.async { [weak field] in field?.beginPickingIfWanted() }
    } else if !isEditing {
      field.wantsPicking = false
    }
    context.coordinator.wasEditing = isEditing
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  final class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: SpaceIconField
    var wasEditing = false
    private var ended = false

    init(parent: SpaceIconField) {
      self.parent = parent
    }

    /// An edit starts. Not `controlTextDidBeginEditing`, which waits for the
    /// first change: an edit that changes nothing has to end too.
    func begin() {
      ended = false
    }

    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSTextField else { return }
      switch SpaceIcon.edit(for: field.stringValue) {
      case .set(let emoji):
        field.stringValue = emoji
        if emoji != parent.icon {
          parent.onChange(emoji)
        }
      case .clear:
        if parent.icon != nil {
          parent.onChange(nil)
        }
      case .unchanged:
        field.stringValue = parent.icon ?? ""
      }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
      if selector == #selector(NSResponder.insertNewline(_:)) || selector == #selector(NSResponder.cancelOperation(_:)) {
        end(control)
        return true
      }
      return false
    }

    func controlTextDidEndEditing(_ notification: Notification) {
      guard !ended else { return }
      ended = true
      parent.onEnd()
    }

    private func end(_ control: NSControl) {
      guard !ended else { return }
      ended = true
      control.window?.makeFirstResponder(nil)
      parent.onEnd()
    }
  }
}

/// The field behind `SpaceIconField`: it selects its emoji on focus, so the
/// next one picked replaces it, and opens the emoji picker.
final class IconTextField: NSTextField {
  /// An edit started, and the field takes focus once it's in a window.
  var wantsPicking = false

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    DispatchQueue.main.async { [weak self] in self?.beginPickingIfWanted() }
  }

  func beginPickingIfWanted() {
    guard wantsPicking, let window, window.makeFirstResponder(self) else { return }
    wantsPicking = false
    currentEditor()?.selectAll(nil)
    NSApp.orderFrontCharacterPalette(self)
  }
}
