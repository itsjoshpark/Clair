// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost

/// The alert for an extension confirmation (arc-extension-experience D4).
/// Install and remove use Clair's wording; other prompts use Chromium's.
@MainActor
enum ExtensionPromptAlert {
  static func make(for prompt: any ClairExtensionPrompt) -> NSAlert {
    let alert = NSAlert()
    if let icon = prompt.icon {
      alert.icon = icon
    }
    switch prompt.kind {
    case .install:
      alert.messageText = "Add \"\(prompt.extensionName)\" to Clair?"
      alert.informativeText = permissionText(heading: "It can:", permissions: prompt.permissions)
      addButtons(to: alert, accept: "Add Extension", cancel: "Cancel")
    case .remove:
      alert.messageText = "Remove \"\(prompt.extensionName)\" from Clair?"
      addButtons(to: alert, accept: "Remove Extension", cancel: "Cancel")
      alert.buttons.first?.hasDestructiveAction = true
    default:
      alert.messageText = prompt.title
      alert.informativeText = permissionText(heading: prompt.permissionsHeading, permissions: prompt.permissions)
      addButtons(to: alert, accept: prompt.acceptLabel, cancel: prompt.cancelLabel)
    }
    return alert
  }

  private static func permissionText(heading: String, permissions: [String]) -> String {
    guard !permissions.isEmpty else { return "" }
    let list = permissions.map { "• \($0)" }.joined(separator: "\n")
    return heading.isEmpty ? list : "\(heading)\n\(list)"
  }

  private static func addButtons(to alert: NSAlert, accept: String, cancel: String) {
    alert.addButton(withTitle: accept)
    if !cancel.isEmpty {
      // Esc whatever the label says; only a button titled "Cancel" gets it
      // from NSAlert.
      alert.addButton(withTitle: cancel).keyEquivalent = "\u{1b}"
    }
  }
}

/// A window's extension confirmations: one sheet at a time, the rest waiting
/// behind it. Each prompt is answered at most once.
@MainActor
final class ExtensionPromptSheets {
  typealias Present = (NSAlert, @escaping @MainActor (NSApplication.ModalResponse) -> Void) -> Void

  private let present: Present
  private let close: (NSAlert) -> Void
  private let answer: (_ promptID: Int, _ accepted: Bool) -> Void
  private var waiting: [any ClairExtensionPrompt] = []
  private var current: (promptID: Int, alert: NSAlert)?

  init(
    present: @escaping Present, close: @escaping (NSAlert) -> Void,
    answer: @escaping (_ promptID: Int, _ accepted: Bool) -> Void
  ) {
    self.present = present
    self.close = close
    self.answer = answer
  }

  func show(_ prompt: any ClairExtensionPrompt) {
    waiting.append(prompt)
    showNext()
  }

  /// Chromium no longer needs the answer.
  func dismiss(_ promptID: Int) {
    waiting.removeAll { $0.promptID == promptID }
    guard let current, current.promptID == promptID else { return }
    self.current = nil
    close(current.alert)
    showNext()
  }

  /// The window is closing: everything still asked counts as a cancel.
  func cancelAll() {
    let pending = (current.map { [$0.promptID] } ?? []) + waiting.map(\.promptID)
    let alert = current?.alert
    current = nil
    waiting = []
    if let alert {
      close(alert)
    }
    pending.forEach { answer($0, false) }
  }

  private func showNext() {
    guard current == nil, !waiting.isEmpty else { return }
    let prompt = waiting.removeFirst()
    let alert = ExtensionPromptAlert.make(for: prompt)
    let promptID = prompt.promptID
    current = (promptID, alert)
    present(alert) { [weak self] response in
      self?.finish(promptID, accepted: response == .alertFirstButtonReturn)
    }
  }

  private func finish(_ promptID: Int, accepted: Bool) {
    // A sheet closed by dismiss or cancelAll has already been dealt with.
    guard current?.promptID == promptID else { return }
    current = nil
    answer(promptID, accepted)
    showNext()
  }
}
