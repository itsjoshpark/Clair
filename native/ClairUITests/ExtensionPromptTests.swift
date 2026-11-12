// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Testing

@testable import ClairUI

@MainActor
final class ExtensionPromptTests {
  private var begun: [ClairDialog] = []
  private var ended: [ClairDialog] = []
  private var answers: [String] = []
  private var presenter: ClairDialogPresenter!
  private var sheets: ExtensionPromptSheets!

  init() {
    presenter = ClairDialogPresenter(
      host: .init(
        begin: { [unowned self] in begun.append($0) },
        end: { [unowned self] in ended.append($0) }))
    sheets = ExtensionPromptSheets(dialogs: presenter) { [unowned self] id, accepted in
      answers.append("\(id) \(accepted)")
    }
  }

  private func buttons(_ page: ClairDialogPage) -> [String] { page.buttons.map(\.title) }
  private func list(_ permissions: [String]) -> String? {
    (ExtensionPromptDialog.permissionList(permissions).documentView as? NSTextView)?.string
  }
  private func accept(_ dialog: ClairDialog) { dialog.press(dialog.page.buttons.last!) }
  private func cancel(_ dialog: ClairDialog) { dialog.press(dialog.page.buttons.first!) }

  @Test func installDialog() {
    let page = ExtensionPromptDialog.make(
      for: FakeExtensionPrompt(id: 1, kind: .install, name: "Reader", permissions: ["Read your history", "Read data"]))
    #expect(page.title == "Add “Reader” to Clair?")
    #expect(page.message == "It can:")
    #expect(page.content != nil)
    #expect(list(["Read your history", "Read data"]) == "•\tRead your history\n•\tRead data")
    #expect(buttons(page) == ["Cancel", "Add Extension"])
    #expect(page.buttons[1].shortcut == .defaultAction)
    #expect(!page.buttons[1].isDestructive)
    #expect(page.buttons[0].shortcut == .cancelAction)
  }

  @Test func installWithoutPermissionsHasNoList() {
    let page = ExtensionPromptDialog.make(for: FakeExtensionPrompt(id: 1, kind: .install, name: "Reader"))
    #expect(page.message == nil)
    #expect(page.content == nil)
    #expect(buttons(page) == ["Cancel", "Add Extension"])
  }

  /// Arc fills Remove Extension with the Space's colour, not red.
  @Test func removeDialogFollowsArc() {
    let page = ExtensionPromptDialog.make(
      for: FakeExtensionPrompt(id: 2, kind: .remove, name: "Reader", permissions: ["Read data"]))
    #expect(page.title == "Remove “Reader” from Clair?")
    #expect(page.message == nil)
    #expect(page.content == nil)
    #expect(buttons(page) == ["Cancel", "Remove Extension"])
    #expect(page.buttons[1].role == .default)
    #expect(page.buttons[1].shortcut == .defaultAction)
  }

  @Test func otherDialogUsesChromiumsText() {
    let page = ExtensionPromptDialog.make(
      for: FakeExtensionPrompt(
        id: 3, kind: .other, name: "Reader", permissions: ["Read data"], title: "Reader wants more",
        heading: "It could:", accept: "Allow", cancel: "Deny"))
    #expect(page.title == "Reader wants more")
    #expect(page.message == "It could:")
    #expect(page.content != nil)
    #expect(buttons(page) == ["Deny", "Allow"])
    #expect(page.buttons[0].shortcut == .cancelAction)
  }

  @Test func otherDialogWithoutCancelHasOneButton() {
    let page = ExtensionPromptDialog.make(
      for: FakeExtensionPrompt(id: 3, kind: .other, name: "Reader", title: "Reader", accept: "OK"))
    #expect(buttons(page) == ["OK"])
  }

  @Test func showsTheExtensionsIcon() {
    let icon = NSImage(size: NSSize(width: 16, height: 16))
    let prompt = FakeExtensionPrompt(id: 1, kind: .install, name: "Reader")
    prompt.icon = icon
    #expect(ExtensionPromptDialog.make(for: prompt).icon === icon)
  }

  @Test func longListStaysCapped() {
    let permissions = (1...100).map { "Read and change your data on site\($0).example" }
    let scroll = ExtensionPromptDialog.permissionList(permissions)
    #expect(scroll.frame.height == ExtensionPromptDialog.maxListHeight)
    #expect(scroll.hasVerticalScroller)
    #expect(ExtensionPromptDialog.permissionList(["Read data"]).frame.height < ExtensionPromptDialog.maxListHeight)
  }

  @Test func permissionListFollowsTheAppearance() {
    let text = ExtensionPromptDialog.permissionList(["Read data"]).documentView as? NSTextView
    let color = text?.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
    func whiteness(_ name: NSAppearance.Name) -> CGFloat {
      var white: CGFloat = -1
      NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
        color?.usingColorSpace(.genericGray)?.getWhite(&white, alpha: nil)
      }
      return white
    }
    #expect(whiteness(.darkAqua) > 0.9)
    #expect(whiteness(.aqua) < 0.3)
  }

  @Test func permissionListTakesRoomInTheCard() {
    func height(_ permissions: [String]) -> CGFloat {
      let page = ExtensionPromptDialog.make(
        for: FakeExtensionPrompt(id: 1, kind: .other, name: "R", permissions: permissions, title: "R", accept: "OK"))
      return ClairDialogWindow(dialog: ClairDialog(page)).frame.height
    }
    let lines = ["Read your history", "Read data", "Change data"]
    let list = ExtensionPromptDialog.permissionList(lines).frame.height
    #expect(list > 0)
    // The card grows by the list and the heading, not just the heading.
    #expect(height(lines) - height(["Read data"]) >= list / 2)
  }

  @Test func answersOnceWithThePromptsID() {
    sheets.show(FakeExtensionPrompt(id: 7, kind: .install, name: "A"))
    accept(begun[0])
    accept(begun[0])
    #expect(answers == ["7 true"])

    sheets.show(FakeExtensionPrompt(id: 8, kind: .remove, name: "B"))
    cancel(begun[1])
    #expect(answers == ["7 true", "8 false"])
  }

  @Test func oneSheetAtATime() {
    sheets.show(FakeExtensionPrompt(id: 1, kind: .install, name: "A"))
    sheets.show(FakeExtensionPrompt(id: 2, kind: .install, name: "B"))
    #expect(begun.count == 1)
    accept(begun[0])
    #expect(begun.count == 2)
    #expect(begun[1].page.title == "Add “B” to Clair?")
  }

  @Test func dismissedPromptAnswersNothing() {
    sheets.show(FakeExtensionPrompt(id: 1, kind: .remove, name: "A"))
    sheets.show(FakeExtensionPrompt(id: 2, kind: .install, name: "B"))
    sheets.dismiss(1)
    #expect(ended.count == 1)
    accept(begun[0])
    #expect(answers == [])
    // The next one takes its place.
    #expect(begun.count == 2)
  }

  @Test func windowClosingCancelsEverything() {
    sheets.show(FakeExtensionPrompt(id: 1, kind: .install, name: "A"))
    sheets.show(FakeExtensionPrompt(id: 2, kind: .install, name: "B"))
    presenter.cancelAll()
    #expect(ended.count == 1)
    #expect(answers == ["1 false", "2 false"])
    accept(begun[0])
    #expect(answers.count == 2)
    #expect(begun.count == 1)
  }
}
