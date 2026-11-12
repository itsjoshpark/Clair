// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import Observation
import SwiftUI

/// A button in a dialog's row (add-clair-dialogs D1). Its role decides its
/// look, its key and how it answers.
struct ClairDialogButton {
  enum Role {
    /// Esc; answers `.cancelled`.
    case cancel
    /// Return, filled with the accent colour; answers `.accepted`.
    case `default`
    /// Return, filled with red, for one that destroys something; answers
    /// `.accepted`.
    case destructive
  }

  var title: String
  var role: Role
  var isEnabled = true
  /// Runs instead of answering and closing, as a swapped card's buttons do
  /// to go back. Nil answers with the role.
  var action: (@MainActor (ClairDialog) -> Void)?

  var isDefault: Bool { role != .cancel }
  var isDestructive: Bool { role == .destructive }

  /// Esc for the cancelling button and Return for the default one, unless
  /// it's disabled (D2).
  var shortcut: KeyboardShortcut? {
    switch role {
    case .cancel: .cancelAction
    case .default, .destructive: isEnabled ? .defaultAction : nil
    }
  }

  /// The key shown in the button's capsule, as Arc's buttons do.
  var keyLabel: String { role == .cancel ? "ESC" : "↩" }

  /// For the runtime suite.
  var identifier: String { role == .cancel ? "clair.dialogCancel" : "clair.dialogDefault" }
}

/// What a dialog's card shows. A dialog can swap it for another and come
/// back (D1).
struct ClairDialogPage {
  var icon: NSImage?
  var title: String
  var message: String?
  /// A field, a list or a later change's larger content, between the
  /// message and the buttons.
  var content: AnyView?
  var buttons: [ClairDialogButton]
}

/// How a dialog was answered.
enum ClairDialogAnswer: Equatable {
  /// The cancelling button, Esc, or the window closing.
  case cancelled
  /// The default button, or Return.
  case accepted
}

/// One dialog: its card, with the pages swapped in on top of it.
@MainActor
@Observable
final class ClairDialog {
  private(set) var pages: [ClairDialogPage]
  /// The presenter showing it or holding it in its queue.
  @ObservationIgnored weak var presenter: ClairDialogPresenter?
  /// Bumped to move keyboard focus to the default button, once the sheet is
  /// key and AppKit has picked its own first key view (D2).
  private(set) var defaultFocusRequests = 0

  init(_ page: ClairDialogPage) {
    pages = [page]
  }

  /// The page on the card.
  var page: ClairDialogPage { pages[pages.count - 1] }

  /// Shows `page` in place of the card's content, for a question asked from
  /// inside the dialog, until `swapBack()`.
  func swap(to page: ClairDialogPage) {
    pages.append(page)
  }

  /// Returns to the page shown before the last `swap(to:)`.
  func swapBack() {
    if pages.count > 1 {
      pages.removeLast()
    }
  }

  /// Changes the page on the card, such as a button's `isEnabled`.
  func update(_ change: (inout ClairDialogPage) -> Void) {
    change(&pages[pages.count - 1])
  }

  /// Closes the dialog with `answer`. Does nothing once it has closed.
  func answer(_ answer: ClairDialogAnswer) {
    presenter?.finish(self, answer: answer)
  }

  func focusDefaultButton() {
    defaultFocusRequests += 1
  }

  func press(_ button: ClairDialogButton) {
    guard button.isEnabled else { return }
    if let action = button.action {
      action(self)
    } else {
      answer(button.isDefault ? .accepted : .cancelled)
    }
  }
}

/// A window's dialogs (D1): shows one at a time as a sheet, the rest waiting
/// behind it. Each dialog is answered at most once.
@MainActor
final class ClairDialogPresenter {
  /// Shows and hides a dialog; the window's sheets, or a fake in tests.
  struct Host {
    var begin: @MainActor (ClairDialog) -> Void
    var end: @MainActor (ClairDialog) -> Void
  }

  typealias Completion = @MainActor (ClairDialogAnswer) -> Void

  private struct Request {
    let dialog: ClairDialog
    let completion: Completion
  }

  private let host: Host
  private var waiting: [Request] = []
  private var current: Request?

  init(host: Host) {
    self.host = host
  }

  /// Shows dialogs as sheets on `window`.
  convenience init(window: NSWindow) {
    let sheets = ClairDialogSheets(parent: window)
    self.init(host: Host(begin: { sheets.begin($0) }, end: { sheets.end($0) }))
  }

  /// The dialog on the window, if any.
  var showing: ClairDialog? { current?.dialog }

  /// Shows `dialog` once the window's other dialogs are answered.
  func show(_ dialog: ClairDialog, completion: @escaping Completion) {
    dialog.presenter = self
    waiting.append(Request(dialog: dialog, completion: completion))
    showNext()
  }

  /// Closes `dialog`, or takes it out of the queue, without answering it.
  func dismiss(_ dialog: ClairDialog) {
    waiting.removeAll { $0.dialog === dialog }
    dialog.presenter = nil
    guard current?.dialog === dialog else { return }
    current = nil
    host.end(dialog)
    showNext()
  }

  /// The window is closing: every dialog shown or waiting is cancelled.
  func cancelAll() {
    let pending = (current.map { [$0] } ?? []) + waiting
    if let current {
      host.end(current.dialog)
    }
    current = nil
    waiting = []
    for request in pending {
      request.dialog.presenter = nil
      request.completion(.cancelled)
    }
  }

  fileprivate func finish(_ dialog: ClairDialog, answer: ClairDialogAnswer) {
    guard let request = current, request.dialog === dialog else { return }
    current = nil
    dialog.presenter = nil
    host.end(dialog)
    request.completion(answer)
    showNext()
  }

  private func showNext() {
    guard current == nil, !waiting.isEmpty else { return }
    let next = waiting.removeFirst()
    current = next
    host.begin(next.dialog)
  }
}

/// Shows dialogs as sheets on a window: AppKit centres and dims, makes the
/// sheet modal to its window and keeps Tab inside it (D1).
@MainActor
private final class ClairDialogSheets {
  private weak var parent: NSWindow?
  private var sheets: [ObjectIdentifier: (window: ClairDialogWindow, responder: Weak<NSResponder>)] = [:]

  init(parent: NSWindow) {
    self.parent = parent
  }

  func begin(_ dialog: ClairDialog) {
    guard let parent else { return }
    let sheet = ClairDialogWindow(dialog: dialog)
    sheets[ObjectIdentifier(dialog)] = (sheet, Weak(parent.firstResponder))
    parent.beginSheet(sheet)
    sheet.focusFirstField()
  }

  func end(_ dialog: ClairDialog) {
    guard let (sheet, responder) = sheets.removeValue(forKey: ObjectIdentifier(dialog)) else { return }
    guard let parent else { return }
    parent.endSheet(sheet)
    sheet.orderOut(nil)
    // Focus goes back where it was, as the command bar returns it to the
    // page (D2).
    if let responder = responder.value, parent.firstResponder !== responder,
      (responder as? NSView)?.window === parent
    {
      parent.makeFirstResponder(responder)
    }
  }
}

private struct Weak<T: AnyObject> {
  weak var value: T?
  init(_ value: T?) { self.value = value }
}

/// The sheet: a clear, borderless window holding only the card, so nothing of
/// macOS's sheet shows around it.
final class ClairDialogWindow: NSWindow {
  let dialog: ClairDialog

  init(dialog: ClairDialog) {
    self.dialog = dialog
    super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    isReleasedWhenClosed = false
    identifier = NSUserInterfaceItemIdentifier("clair.dialog")
    setAccessibilityIdentifier("clair.dialog")
    let host = NSHostingView(rootView: ClairDialogView(dialog: dialog))
    contentView = host
    setContentSize(host.fittingSize)
    observePage()
  }

  override var canBecomeKey: Bool { true }

  /// Esc when the card's own key equivalent didn't take it.
  override func cancelOperation(_ sender: Any?) {
    if let cancel = dialog.page.buttons.first(where: { $0.role == .cancel }) {
      dialog.press(cancel)
    }
  }

  /// Gives keyboard focus to the card's first field (D2), or else to its
  /// default button, which only shows with keyboard navigation on.
  func focusFirstField() {
    if let field = contentView.flatMap(Self.firstField(in:)) {
      makeFirstResponder(field)
    } else {
      Task { @MainActor [dialog] in dialog.focusDefaultButton() }
    }
  }

  private static func firstField(in view: NSView) -> NSTextField? {
    if let field = view as? NSTextField, field.isEditable, !field.isHidden {
      return field
    }
    for subview in view.subviews {
      if let field = firstField(in: subview) {
        return field
      }
    }
    return nil
  }

  /// Keeps the window's title, which VoiceOver reads, and its shadow, which
  /// follows the card's shape, up to date as pages swap.
  private func observePage() {
    withObservationTracking {
      title = dialog.page.title
    } onChange: { [weak self] in
      Task { @MainActor in
        guard let self else { return }
        self.observePage()
        self.invalidateShadow()
      }
    }
  }
}

/// The card (D1): an optional icon, a title, a message, the page's content
/// and the button row, the default button last.
struct ClairDialogView: View {
  let dialog: ClairDialog
  @FocusState private var focusedButton: ClairDialogButton.Role?

  static let width: CGFloat = 450
  static let padding: CGFloat = 24
  static let cornerRadius: CGFloat = 16
  static let iconSize: CGFloat = 48
  /// The width the content slot gets.
  static let contentWidth = width - 2 * padding

  var body: some View {
    let page = dialog.page
    let buttons = page.buttons.filter { !$0.isDefault } + page.buttons.filter(\.isDefault)
    let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
    VStack(alignment: .leading, spacing: 0) {
      if let icon = page.icon {
        Image(nsImage: icon)
          .resizable()
          .interpolation(.high)
          .frame(width: Self.iconSize, height: Self.iconSize)
          .padding(.bottom, 14)
          .accessibilityHidden(true)
      }
      Text(page.title)
        .font(.system(size: 17, weight: .semibold))
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("clair.dialogTitle")
      if let message = page.message {
        Text(message)
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 6)
      }
      if let content = page.content {
        content
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.top, 12)
      }
      HStack(spacing: 8) {
        Spacer(minLength: 0)
        ForEach(Array(buttons.enumerated()), id: \.offset) { _, button in
          ClairDialogButtonView(button: button) { dialog.press(button) }
            .focused($focusedButton, equals: button.role)
        }
      }
      .padding(.top, 22)
    }
    .padding(Self.padding)
    .frame(width: Self.width, alignment: .leading)
    .background(shape.fill(Color(nsColor: .windowBackgroundColor)))
    .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
    .clipShape(shape)
    .onChange(of: dialog.defaultFocusRequests) {
      focusedButton = buttons.last { $0.isDefault }?.role
    }
    .accessibilityElement(children: .contain)
  }
}

/// A row button with its key in a capsule after its title.
private struct ClairDialogButtonView: View {
  let button: ClairDialogButton
  let press: () -> Void

  var body: some View {
    Button(action: press) {
      HStack(spacing: 6) {
        Text(button.title)
        KeyCapsule(label: button.keyLabel, onFill: button.isDefault)
          .accessibilityHidden(true)
      }
    }
    .buttonStyle(ClairDialogButtonStyle(role: button.role))
    .keyboardShortcut(button.shortcut)
    .disabled(!button.isEnabled)
    .accessibilityLabel(button.title)
    .accessibilityIdentifier(button.identifier)
  }
}

private struct KeyCapsule: View {
  let label: String
  let onFill: Bool

  var body: some View {
    Text(label)
      .font(.system(size: 10, weight: .semibold))
      .foregroundStyle(onFill ? Color.white.opacity(0.85) : Color.secondary)
      .padding(.horizontal, 5)
      .frame(minWidth: 18, minHeight: 16)
      .background(Capsule().fill(onFill ? Color.white.opacity(0.22) : Color.primary.opacity(0.1)))
  }
}

private struct ClairDialogButtonStyle: ButtonStyle {
  let role: ClairDialogButton.Role

  func makeBody(configuration: Configuration) -> some View {
    StyledLabel(role: role, configuration: configuration)
  }

  private struct StyledLabel: View {
    let role: ClairDialogButton.Role
    let configuration: Configuration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
      let filled = role != .cancel
      configuration.label
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(filled ? Color.white : Color.primary)
        .padding(.horizontal, 12)
        .frame(minWidth: 72, minHeight: 30)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
    }

    private var fill: Color {
      switch role {
      case .cancel: Color.primary.opacity(0.08)
      case .default: Color.accentColor
      case .destructive: Color(nsColor: .systemRed)
      }
    }
  }
}
