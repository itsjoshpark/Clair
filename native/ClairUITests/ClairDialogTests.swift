// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import SwiftUI
import Testing

@testable import ClairUI

@MainActor
final class ClairDialogTests {
  private var begun: [ClairDialog] = []
  private var ended: [ClairDialog] = []
  private var answers: [String] = []
  private var presenter: ClairDialogPresenter!

  init() {
    presenter = ClairDialogPresenter(
      host: .init(
        begin: { [unowned self] in begun.append($0) },
        end: { [unowned self] in ended.append($0) }))
  }

  private func dialog(_ title: String, buttons: [ClairDialogButton]? = nil) -> ClairDialog {
    ClairDialog(
      ClairDialogPage(
        title: title,
        buttons: buttons ?? [.init(title: "Cancel", role: .cancel), .init(title: "OK", role: .default)]))
  }

  private func show(_ dialog: ClairDialog) {
    presenter.show(dialog) { [unowned self] answer in answers.append("\(dialog.page.title) \(answer)") }
  }

  // MARK: Buttons

  @Test func rolesMapToEscAndReturn() {
    let cancel = ClairDialogButton(title: "Cancel", role: .cancel)
    let ok = ClairDialogButton(title: "OK", role: .default)
    #expect(cancel.shortcut == .cancelAction)
    #expect(cancel.keyLabel == "ESC")
    #expect(!cancel.isDefault)
    #expect(ok.shortcut == .defaultAction)
    #expect(ok.keyLabel == "↩")
    #expect(ok.isDefault)
    #expect(!ok.isDestructive)
  }

  @Test func destructiveDefaultIsMarkedDestructive() {
    let remove = ClairDialogButton(title: "Remove", role: .destructive)
    #expect(remove.isDestructive)
    #expect(remove.isDefault)
    #expect(remove.shortcut == .defaultAction)
  }

  @Test func disabledDefaultHasNoReturn() {
    let ok = ClairDialogButton(title: "OK", role: .default, isEnabled: false)
    #expect(ok.shortcut == nil)
    let remove = ClairDialogButton(title: "Remove", role: .destructive, isEnabled: false)
    #expect(remove.shortcut == nil)
  }

  @Test func pressingButtonsAnswersWithTheirRole() {
    let first = dialog("A")
    show(first)
    first.press(first.page.buttons[1])
    let second = dialog("B")
    show(second)
    second.press(second.page.buttons[0])
    #expect(answers == ["A accepted", "B cancelled"])
    #expect(ended.map(\.page.title) == ["A", "B"])
  }

  @Test func disabledButtonDoesNothing() {
    let shown = dialog("A", buttons: [.init(title: "OK", role: .default, isEnabled: false)])
    show(shown)
    shown.press(shown.page.buttons[0])
    #expect(answers == [])
    #expect(presenter.showing === shown)
  }

  // MARK: Presenter

  @Test func secondRequestWaitsForTheFirst() {
    let first = dialog("A")
    show(first)
    show(dialog("B"))
    #expect(begun.map(\.page.title) == ["A"])
    first.answer(.accepted)
    #expect(begun.map(\.page.title) == ["A", "B"])
    #expect(presenter.showing === begun[1])
  }

  @Test func answersOnce() {
    let shown = dialog("A")
    show(shown)
    shown.answer(.accepted)
    shown.answer(.cancelled)
    #expect(answers == ["A accepted"])
    #expect(ended.count == 1)
  }

  @Test func dismissedDialogIsNotAnswered() {
    let first = dialog("A")
    let second = dialog("B")
    let third = dialog("C")
    show(first)
    show(second)
    show(third)
    presenter.dismiss(second)
    presenter.dismiss(first)
    #expect(ended.map(\.page.title) == ["A"])
    first.answer(.accepted)
    #expect(answers == [])
    // The next one still waiting takes its place.
    #expect(begun.map(\.page.title) == ["A", "C"])
  }

  @Test func cancelAllCancelsEveryPendingRequest() {
    show(dialog("A"))
    show(dialog("B"))
    presenter.cancelAll()
    #expect(ended.map(\.page.title) == ["A"])
    #expect(answers == ["A cancelled", "B cancelled"])
    #expect(begun.count == 1)
    #expect(presenter.showing == nil)
  }

  @Test func completionCanAskAgain() {
    let first = dialog("A")
    presenter.show(first) { [unowned self] _ in show(dialog("Again")) }
    first.answer(.accepted)
    #expect(begun.map(\.page.title) == ["A", "Again"])
  }

  // MARK: Swapping content

  @Test func swapsContentAndReturns() {
    let shown = dialog("Manage")
    show(shown)
    shown.swap(
      to: ClairDialogPage(
        title: "Delete?",
        buttons: [
          .init(title: "Cancel", role: .cancel, action: { $0.swapBack() }),
          .init(title: "Delete", role: .destructive, action: { $0.swapBack() }),
        ]))
    #expect(shown.page.title == "Delete?")
    shown.press(shown.page.buttons[0])
    #expect(shown.page.title == "Manage")
    #expect(answers == [])
    shown.swapBack()
    #expect(shown.page.title == "Manage")
  }

  @Test func updateChangesTheShownPage() {
    let shown = dialog("Name", buttons: [.init(title: "OK", role: .default, isEnabled: false)])
    shown.update { $0.buttons[0].isEnabled = true }
    #expect(shown.page.buttons[0].shortcut == .defaultAction)
  }

  // MARK: The sheet

  @Test func sheetIsClearAndBorderless() {
    let window = ClairDialogWindow(dialog: dialog("A"))
    #expect(window.styleMask == .borderless)
    #expect(!window.isOpaque)
    #expect(window.backgroundColor == .clear)
    #expect(window.canBecomeKey)
    #expect(window.title == "A")
    #expect(window.frame.width == ClairDialogView.width)
  }

  @Test func escCancelsThroughTheWindow() {
    let shown = dialog("A")
    show(shown)
    ClairDialogWindow(dialog: shown).cancelOperation(nil)
    #expect(answers == ["A cancelled"])
  }

  @Test func firstFieldGetsFocus() {
    var page = ClairDialogPage(title: "Name", buttons: [.init(title: "OK", role: .default)])
    page.content = AnyView(TextField("Name", text: .constant("")))
    let window = ClairDialogWindow(dialog: ClairDialog(page))
    window.contentView?.layoutSubtreeIfNeeded()
    window.focusFirstField()
    let editor = window.firstResponder as? NSTextView
    #expect((editor?.delegate as? NSTextField) != nil)
  }
}
