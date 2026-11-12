// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import SwiftUI

/// The dialog for an extension confirmation (arc-extension-experience D4,
/// add-clair-dialogs D3). Install and remove use Clair's wording; other
/// prompts use Chromium's.
@MainActor
enum ExtensionPromptDialog {
  /// The tallest the permission list gets before it scrolls, so a long list
  /// can't push the dialog's buttons off the screen.
  static let maxListHeight: CGFloat = 200

  static func make(for prompt: any ClairExtensionPrompt) -> ClairDialogPage {
    switch prompt.kind {
    case .install:
      page(
        prompt, title: "Add \"\(prompt.extensionName)\" to Clair?", heading: "It can:",
        buttons: buttons(accept: "Add Extension", role: .default, cancel: "Cancel"))
    case .remove:
      page(
        prompt, title: "Remove \"\(prompt.extensionName)\" from Clair?", heading: nil,
        buttons: buttons(accept: "Remove Extension", role: .destructive, cancel: "Cancel"))
    default:
      page(
        prompt, title: prompt.title, heading: prompt.permissionsHeading,
        buttons: buttons(accept: prompt.acceptLabel, role: .default, cancel: prompt.cancelLabel))
    }
  }

  private static func page(
    _ prompt: any ClairExtensionPrompt, title: String, heading: String?, buttons: [ClairDialogButton]
  ) -> ClairDialogPage {
    let permissions = heading == nil ? [] : prompt.permissions
    return ClairDialogPage(
      icon: prompt.icon, title: title, message: permissions.isEmpty || heading?.isEmpty != false ? nil : heading,
      content: permissions.isEmpty ? nil : AnyView(PermissionListView(permissions: permissions)),
      buttons: buttons)
  }

  private static func buttons(accept: String, role: ClairDialogButton.Role, cancel: String) -> [ClairDialogButton] {
    // Esc whatever the label says.
    let cancelButton = cancel.isEmpty ? [] : [ClairDialogButton(title: cancel, role: .cancel)]
    return cancelButton + [ClairDialogButton(title: accept, role: role)]
  }

  /// The card's slate grey, following the appearance as the text is drawn.
  static let listColor = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      ? NSColor(white: 1, alpha: 0.75) : NSColor(white: 0, alpha: 0.75)
  }

  /// The permissions as a bulleted list, scrolling once it's taller than
  /// `maxListHeight`.
  static func permissionList(_ permissions: [String], width: CGFloat = ClairDialogView.contentWidth) -> NSScrollView {
    let text = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 0))
    // Arc's list: 14 pt, the bullet 3 pt in and the text hanging at 20 pt.
    let paragraph = NSMutableParagraphStyle()
    paragraph.firstLineHeadIndent = 3
    paragraph.headIndent = 20
    paragraph.tabStops = [NSTextTab(textAlignment: .left, location: 20)]
    paragraph.paragraphSpacing = 6
    text.textStorage?.setAttributedString(
      NSAttributedString(
        string: permissions.map { "•\t\($0)" }.joined(separator: "\n"),
        attributes: [
          .font: NSFont.systemFont(ofSize: 14),
          .foregroundColor: listColor,
          .paragraphStyle: paragraph,
        ]))
    text.isEditable = false
    text.isSelectable = false
    text.drawsBackground = false
    text.textContainerInset = .zero
    text.textContainer?.lineFragmentPadding = 0
    var height: CGFloat = 0
    if let layout = text.layoutManager, let container = text.textContainer {
      layout.ensureLayout(for: container)
      height = ceil(layout.usedRect(for: container).height)
    }
    text.frame.size.height = height
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: min(height, maxListHeight)))
    scroll.drawsBackground = false
    scroll.borderType = .noBorder
    scroll.hasVerticalScroller = height > maxListHeight
    scroll.autohidesScrollers = true
    scroll.documentView = text
    return scroll
  }
}

/// The permission list in the dialog's content slot, as tall as its list up
/// to `maxListHeight`.
private struct PermissionListView: NSViewRepresentable {
  let permissions: [String]
  let size: CGSize

  init(permissions: [String]) {
    self.permissions = permissions
    size = ExtensionPromptDialog.permissionList(permissions).frame.size
  }

  func makeNSView(context: Context) -> NSScrollView {
    ExtensionPromptDialog.permissionList(permissions)
  }

  func updateNSView(_ view: NSScrollView, context: Context) {}

  func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
    size
  }
}

/// A window's extension confirmations, as dialogs on the window's presenter,
/// which shows one at a time. Each prompt is answered at most once; the
/// presenter's `cancelAll()` answers what's left when the window closes.
@MainActor
final class ExtensionPromptSheets {
  private let dialogs: ClairDialogPresenter
  private let answer: (_ promptID: Int, _ accepted: Bool) -> Void
  private var asked: [Int: ClairDialog] = [:]

  init(dialogs: ClairDialogPresenter, answer: @escaping (_ promptID: Int, _ accepted: Bool) -> Void) {
    self.dialogs = dialogs
    self.answer = answer
  }

  func show(_ prompt: any ClairExtensionPrompt) {
    let promptID = prompt.promptID
    let dialog = ClairDialog(ExtensionPromptDialog.make(for: prompt))
    asked[promptID] = dialog
    dialogs.show(dialog) { [weak self] answer in
      guard let self, self.asked.removeValue(forKey: promptID) != nil else { return }
      self.answer(promptID, answer == .accepted)
    }
  }

  /// Chromium no longer needs the answer.
  func dismiss(_ promptID: Int) {
    guard let dialog = asked.removeValue(forKey: promptID) else { return }
    dialogs.dismiss(dialog)
  }
}
