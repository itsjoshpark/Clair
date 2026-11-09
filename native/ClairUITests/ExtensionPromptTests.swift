// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Testing

@testable import ClairUI

@MainActor
final class ExtensionPromptTests {
  private var presented: [(alert: NSAlert, respond: (NSApplication.ModalResponse) -> Void)] = []
  private var closed: [NSAlert] = []
  private var answers: [String] = []
  private var sheets: ExtensionPromptSheets!

  init() {
    sheets = ExtensionPromptSheets(
      present: { [unowned self] alert, respond in presented.append((alert, respond)) },
      close: { [unowned self] alert in closed.append(alert) },
      answer: { [unowned self] id, accepted in answers.append("\(id) \(accepted)") })
  }

  private func buttons(_ alert: NSAlert) -> [String] { alert.buttons.map(\.title) }

  @Test func installAlert() {
    let alert = ExtensionPromptAlert.make(
      for: FakeExtensionPrompt(id: 1, kind: .install, name: "Reader", permissions: ["Read your history", "Read data"]))
    #expect(alert.messageText == "Add \"Reader\" to Clair?")
    #expect(alert.informativeText == "It can:\n• Read your history\n• Read data")
    #expect(buttons(alert) == ["Add Extension", "Cancel"])
    #expect(alert.buttons[0].keyEquivalent == "\r")
    #expect(alert.buttons[1].keyEquivalent == "\u{1b}")
  }

  @Test func installWithoutPermissionsHasNoList() {
    let alert = ExtensionPromptAlert.make(for: FakeExtensionPrompt(id: 1, kind: .install, name: "Reader"))
    #expect(alert.informativeText == "")
    #expect(buttons(alert) == ["Add Extension", "Cancel"])
  }

  @Test func removeAlertIsDestructive() {
    let alert = ExtensionPromptAlert.make(for: FakeExtensionPrompt(id: 2, kind: .remove, name: "Reader"))
    #expect(alert.messageText == "Remove \"Reader\" from Clair?")
    #expect(alert.informativeText == "")
    #expect(buttons(alert) == ["Remove Extension", "Cancel"])
    #expect(alert.buttons[0].hasDestructiveAction)
    #expect(alert.buttons[0].keyEquivalent == "\r")
  }

  @Test func otherAlertUsesChromiumsText() {
    let alert = ExtensionPromptAlert.make(
      for: FakeExtensionPrompt(
        id: 3, kind: .other, name: "Reader", permissions: ["Read data"], title: "Reader wants more",
        heading: "It could:", accept: "Allow", cancel: "Deny"))
    #expect(alert.messageText == "Reader wants more")
    #expect(alert.informativeText == "It could:\n• Read data")
    #expect(buttons(alert) == ["Allow", "Deny"])
    #expect(alert.buttons[1].keyEquivalent == "\u{1b}")
  }

  @Test func answersOnceWithThePromptsID() {
    sheets.show(FakeExtensionPrompt(id: 7, kind: .install, name: "A"))
    presented[0].respond(.alertFirstButtonReturn)
    presented[0].respond(.alertFirstButtonReturn)
    #expect(answers == ["7 true"])

    sheets.show(FakeExtensionPrompt(id: 8, kind: .remove, name: "B"))
    presented[1].respond(.alertSecondButtonReturn)
    #expect(answers == ["7 true", "8 false"])
  }

  @Test func oneSheetAtATime() {
    sheets.show(FakeExtensionPrompt(id: 1, kind: .install, name: "A"))
    sheets.show(FakeExtensionPrompt(id: 2, kind: .install, name: "B"))
    #expect(presented.count == 1)
    presented[0].respond(.alertFirstButtonReturn)
    #expect(presented.count == 2)
    #expect(presented[1].alert.messageText == "Add \"B\" to Clair?")
  }

  @Test func dismissedPromptAnswersNothing() {
    sheets.show(FakeExtensionPrompt(id: 1, kind: .remove, name: "A"))
    sheets.show(FakeExtensionPrompt(id: 2, kind: .install, name: "B"))
    sheets.dismiss(1)
    #expect(closed.count == 1)
    presented[0].respond(.abort)  // endSheet's completion
    #expect(answers == [])
    // The next one takes its place.
    #expect(presented.count == 2)
  }

  @Test func windowClosingCancelsEverything() {
    sheets.show(FakeExtensionPrompt(id: 1, kind: .install, name: "A"))
    sheets.show(FakeExtensionPrompt(id: 2, kind: .install, name: "B"))
    sheets.cancelAll()
    #expect(closed.count == 1)
    #expect(answers == ["1 false", "2 false"])
    presented[0].respond(.abort)
    #expect(answers.count == 2)
    #expect(presented.count == 1)
  }
}
