// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import SwiftUI

/// What the overlays above the card ask the window to do.
@MainActor
protocol OverlayActions: AnyObject {
  func find(_ text: String, forward: Bool)
  func closeFind()
  func infobar(_ infobarID: Int, didChoose action: InfobarAction)
  func reloadCrashedPage()
}

/// The command bar (design D11): a field and up to five rows, floating over
/// the window.
/// Colours for the views over the page. They're solid rather than a material:
/// over the page's layer a material can't sample what's behind it, and shows
/// flat grey with its vibrant secondary text gone.
enum OverlayStyle {
  static let background = Color(nsColor: .windowBackgroundColor)
  static let secondary = Color(nsColor: .secondaryLabelColor)
}

struct CommandBarView: View {
  let model: CommandBarModel
  @FocusState private var isFieldFocused: Bool
  /// The row under the pointer. As in Arc, it only tints the row grey; the
  /// selection stays where the keyboard put it.
  @State private var hoveredSuggestionID: Int?
  @Environment(\.colorScheme) private var colorScheme

  static let width: CGFloat = 764
  /// Arc's metrics: a 64 pt field row, then 50 pt rows.
  static let fieldHeight: CGFloat = 64
  static let rowHeight: CGFloat = 50

  /// The panel's top, about a third of the way down the window, as in Arc.
  static func top(inWindowHeight height: CGFloat) -> CGFloat {
    (height * 0.34).rounded()
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 16, weight: .regular))
          .frame(width: 18, height: 18)
        if let keywordName = model.keywordName {
          Text(keywordName)
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.18), in: .capsule)
            .accessibilityIdentifier("clair.commandBarKeyword")
        }
        // In keyword mode the field only searches that engine.
        TextField(
          model.keywordName == nil ? "Search or Enter URL…" : "Search…",
          text: Binding(get: { model.text }, set: { model.setText($0) })
        )
        .textFieldStyle(.plain)
        .font(.system(size: 19, weight: .medium))
        .focused($isFieldFocused)
        .accessibilityIdentifier("clair.commandBarField")
        .onKeyPress(.upArrow) {
          model.moveSelection(by: -1)
          return .handled
        }
        .onKeyPress(.downArrow) {
          model.moveSelection(by: 1)
          return .handled
        }
        // Tab enters keyword mode when one is offered; otherwise it does
        // nothing, rather than move focus out of the field.
        .onKeyPress(.tab) {
          _ = model.acceptKeyword()
          return .handled
        }
        .onKeyPress(.escape) {
          model.cancel()
          return .handled
        }
        .onKeyPress(.return, phases: .down) { press in
          model.submit(newTab: press.modifiers.contains(.shift) || press.modifiers.contains(.command))
          return .handled
        }
        if let offered = model.offeredKeywordName {
          // Arc's hint, measured: 13 pt text, (182) on (251) in Light Mode and
          // (119) on (31) in Dark, 9 pt before a flat "Tab" key.
          HStack(spacing: 7) {
            Text("Search \(offered)")
              .font(.system(size: 13))
              .foregroundStyle(Color.primary.opacity(0.39))
            KeyHint(key: "Tab")
          }
          .lineLimit(1)
          .accessibilityElement(children: .combine)
        }
      }
      .padding(.horizontal, 20)
      .frame(height: Self.fieldHeight)
      // Option+Command+Delete deletes the selected suggestion, as in Arc. A
      // shortcut rather than onKeyPress, which never sees Command keys in the
      // field, so the field never gets it either. (Delete in an empty field
      // in keyword mode is caught by BrowserWindowController.)
      .background {
        Button("Delete Suggestion") { model.deleteSelected() }
          .keyboardShortcut(.delete, modifiers: [.option, .command])
          .opacity(0)
          .allowsHitTesting(false)
          .focusable(false)
          .accessibilityHidden(true)
      }
      if !model.suggestions.isEmpty {
        Divider().padding(.horizontal, 12)
        ScrollView {
          VStack(spacing: 0) {
            ForEach(Array(model.suggestions.enumerated()), id: \.element.suggestionID) { index, suggestion in
              SuggestionRow(
                suggestion: suggestion,
                isSelected: index == model.selection,
                isHovered: hoveredSuggestionID == suggestion.suggestionID,
                onDelete: suggestion.canDelete ? { model.delete(suggestion) } : nil
              )
              .onHover { inside in
                if inside {
                  hoveredSuggestionID = suggestion.suggestionID
                } else if hoveredSuggestionID == suggestion.suggestionID {
                  hoveredSuggestionID = nil
                }
              }
              .onTapGesture {
                model.select(index)
                model.submit()
              }
            }
          }
          .padding(.horizontal, 10)
          .padding(.top, 4)
          .padding(.bottom, 8)
        }
        .frame(maxHeight: 5 * Self.rowHeight + 12)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
    // In Dark Mode, Arc's darker fill, about (30, 32, 32) as measured.
    .background(
      colorScheme == .dark ? Color(red: 0.085, green: 0.093, blue: 0.093) : OverlayStyle.background,
      in: .rect(cornerRadius: 14))
    // Arc's border, measured: in Light Mode a hairline of solid mid-grey; in
    // Dark Mode a point of grey, its inner half lighter. Each value is set to
    // measure as Arc's, as the window draws greys a little lighter.
    .overlay {
      if colorScheme == .dark {
        RoundedRectangle(cornerRadius: 14).strokeBorder(Color(white: 0.235), lineWidth: 0.5)
        RoundedRectangle(cornerRadius: 13.5).strokeBorder(Color(white: 0.3), lineWidth: 0.5).padding(0.5)
      } else {
        RoundedRectangle(cornerRadius: 14).strokeBorder(Color(white: 0.65), lineWidth: 0.5)
      }
    }
    // Flattened first, so only the panel casts the shadow: on its own, the
    // shadow falls from every view inside too, the selected row's fill among
    // them, which Arc's doesn't.
    .compositingGroup()
    .shadow(color: .black.opacity(0.25), radius: 30, y: 12)
    // The field can take focus only once it's laid out in the window, a
    // moment after it's added; keep asking until it has.
    .task {
      for _ in 0..<20 where !isFieldFocused {
        isFieldFocused = true
        try? await Task.sleep(for: .milliseconds(25))
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("clair.commandBar")
    // Pinned to the top of its host, so a host not yet resized to new
    // results never moves the field (design D18).
    .frame(maxHeight: .infinity, alignment: .top)
  }
}

struct SuggestionRow: View {
  let suggestion: any ClairSuggestion
  let isSelected: Bool
  var isHovered = false
  /// Deletes the suggestion, for one that can be deleted; its × shows while
  /// the row is hovered.
  var onDelete: (() -> Void)?
  @Environment(\.colorScheme) private var colorScheme

  var symbol: String {
    switch suggestion.kind {
    case .search: "magnifyingglass"
    case .URL: "globe"
    case .history: "clock"
    case .openTab: "square.on.square"
    @unknown default: "globe"
    }
  }

  /// The URL's domain, when it differs from the title.
  var domain: String? {
    guard suggestion.kind != .search, let host = suggestion.destination?.host() else { return nil }
    return host == suggestion.contents ? nil : host
  }

  /// The row as VoiceOver reads it: its text, its domain, and whether it
  /// switches to an open tab.
  var accessibilityText: String {
    var parts = [suggestion.contents]
    if let domain { parts.append(domain) }
    if suggestion.hasTabMatch { parts.append("Switch to Tab") }
    return parts.joined(separator: ", ")
  }

  var body: some View {
    HStack(spacing: 12) {
      Group {
        if let icon = suggestion.icon {
          Image(nsImage: icon).resizable().interpolation(.high)
        } else {
          Image(systemName: symbol)
        }
      }
      .frame(width: 16, height: 16)
      .foregroundStyle(isSelected ? .white : OverlayStyle.secondary)
      // The domain follows the title after a dash, in the same line.
      (Text(suggestion.contents).fontWeight(.medium)
        + Text(domain.map { " — \($0)" } ?? "")
        .foregroundStyle(isSelected ? .white.opacity(0.75) : OverlayStyle.secondary.opacity(0.8)))
        .font(.system(size: 15))
        .lineLimit(1)
        .truncationMode(.middle)
      Spacer(minLength: 0)
      if suggestion.hasTabMatch {
        Text("Switch to Tab")
          .font(.caption)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background((isSelected ? Color.white : Color.primary).opacity(0.15), in: .capsule)
      }
      if isHovered, let onDelete {
        DeleteSuggestionButton(isOnSelectedRow: isSelected, action: onDelete)
          // Arc's ends 15 pt inside the row.
          .padding(.trailing, 4)
      }
    }
    .foregroundStyle(isSelected ? .white : .primary)
    .padding(.horizontal, 11)
    .frame(height: CommandBarView.rowHeight - 4)
    // Arc's hovered row measures (242) on its (251) panel in Light Mode, about
    // 4% black, and (47) on (31) in Dark Mode, about 7% white.
    .background(
      isSelected
        ? Color.accentColor
        : isHovered ? Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.04) : .clear,
      in: .rect(cornerRadius: 8))
    .padding(.vertical, 2)
    .contentShape(Rectangle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
    .accessibilityIdentifier("clair.suggestion")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    // The row reads as one element, so its × is offered as an action.
    .accessibilityActions {
      if let onDelete {
        Button("Delete Suggestion", action: onDelete)
      }
    }
  }
}

/// A key in the command bar's keyword hint, flat as Arc's: 30 × 24 pt, filled
/// like a hovered row, its label (137) on (242) in Light Mode and (193) on
/// (46) in Dark. Not the tooltip's KeyCap, which is tinted and raised.
private struct KeyHint: View {
  let key: String
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let isDark = colorScheme == .dark
    Text(key)
      .font(.system(size: 13))
      .foregroundStyle(Color.primary.opacity(isDark ? 0.77 : 0.6))
      .padding(.horizontal, 5)
      .frame(minWidth: 30, minHeight: 24)
      .background(
        Color.primary.opacity(isDark ? 0.07 : 0.04),
        in: .rect(cornerRadius: 6, style: .continuous))
  }
}

/// The × on a suggestion that can be deleted (design D5), measured on Arc's.
private struct DeleteSuggestionButton: View {
  let isOnSelectedRow: Bool
  let action: () -> Void
  @State private var isHovered = false
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Button(action: action) {
      Image(systemName: "xmark")
        .font(.system(size: 12, weight: .regular))
        .foregroundStyle(isOnSelectedRow ? Color.white : OverlayStyle.secondary)
        .frame(width: 24, height: 24)
        // Arc's darkens the selected row by about 6% in Light Mode and
        // lightens it by about 7% in Dark Mode.
        .background(
          isHovered ? Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.06) : .clear,
          in: .rect(cornerRadius: 6)
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .focusable(false)
    .onHover { isHovered = $0 }
    .tooltip("Delete Suggestion", shortcut: ["⌥", "⌘", "⌫"])
  }
}

/// The find field at the card's top-trailing corner (design D8).
struct FindFieldView: View {
  let model: BrowserWindowModel
  weak var actions: (any OverlayActions)?
  @State private var text = ""
  @FocusState private var isFocused: Bool

  var body: some View {
    let find = model.find
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass").foregroundStyle(OverlayStyle.secondary)
      TextField("Find", text: $text)
        .textFieldStyle(.plain)
        .frame(width: 180)
        .focused($isFocused)
        .accessibilityIdentifier("clair.findField")
        .onChange(of: text) { _, newValue in actions?.find(newValue, forward: true) }
        .onKeyPress(.return, phases: .down) { press in
          actions?.find(text, forward: !press.modifiers.contains(.shift))
          return .handled
        }
        .onKeyPress(.escape) {
          actions?.closeFind()
          return .handled
        }
      Text(find?.resultText ?? "")
        .font(.caption.monospacedDigit())
        .foregroundStyle(OverlayStyle.secondary)
        .frame(minWidth: 44, alignment: .trailing)
        .accessibilityIdentifier("clair.findResult")
      // The keys do what these buttons do (Return, Shift+Return, Esc), so
      // only the field takes focus, even with keyboard navigation on.
      Button { actions?.find(text, forward: false) } label: { Image(systemName: "chevron.up") }
        .buttonStyle(.plain).disabled(text.isEmpty).focusable(false)
        .tooltip("Previous match", shortcut: ["⇧", "↩"]).accessibilityLabel("Previous match")
      Button { actions?.find(text, forward: true) } label: { Image(systemName: "chevron.down") }
        .buttonStyle(.plain).disabled(text.isEmpty).focusable(false)
        .tooltip("Next match", shortcut: ["↩"]).accessibilityLabel("Next match")
      Button { actions?.closeFind() } label: { Image(systemName: "xmark") }
        .buttonStyle(.plain).focusable(false)
        .tooltip("Close", shortcut: ["esc"]).accessibilityLabel("Close")
    }
    .padding(.horizontal, 10)
    .frame(height: 36)
    .background(OverlayStyle.background, in: .rect(cornerRadius: 10))
    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.1)))
    .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
    .onAppear { text = find?.text ?? "" }
    // The field can take focus only once it's laid out in the window, which
    // happens a moment after it's added; keep asking until it has.
    .task {
      for _ in 0..<20 where !isFocused {
        isFocused = true
        try? await Task.sleep(for: .milliseconds(25))
      }
    }
    .onChange(of: model.findFocusRequest) { isFocused = true }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("clair.find")
  }
}

/// A capsule of text: the link status, a toast or the full-screen notice.
struct CapsuleText: View {
  let text: String
  var font: Font = .system(size: 12)
  var identifier: String

  var body: some View {
    Text(text)
      .font(font)
      .lineLimit(1)
      .truncationMode(.middle)
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(OverlayStyle.background, in: .capsule)
      .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
      .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
      .accessibilityIdentifier(identifier)
  }
}

/// The tab's infobars at the top of the card (design D8).
struct InfobarsView: View {
  let tab: any ClairTab
  weak var actions: (any OverlayActions)?

  var body: some View {
    VStack(spacing: 0) {
      ForEach(tab.infobars, id: \.infobarID) { infobar in
        HStack(spacing: 10) {
          if let icon = infobar.icon {
            Image(nsImage: icon).resizable().frame(width: 16, height: 16)
          }
          Text(infobar.message).lineLimit(2)
          if let link = infobar.linkText {
            Button(link) { actions?.infobar(infobar.infobarID, didChoose: .link) }
              .buttonStyle(.link)
          }
          Spacer(minLength: 0)
          if let cancel = infobar.cancelButtonLabel {
            Button(cancel) { actions?.infobar(infobar.infobarID, didChoose: .cancel) }
          }
          if let ok = infobar.okButtonLabel {
            Button(ok) { actions?.infobar(infobar.infobarID, didChoose: .OK) }
              .keyboardShortcut(.defaultAction)
          }
          Button { actions?.infobar(infobar.infobarID, didChoose: .dismiss) } label: { Image(systemName: "xmark") }
            .buttonStyle(.plain)
            .tooltip("Dismiss")
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 40)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clair.infobar")
      }
    }
  }
}

/// The card when the active tab's page crashed (design D5).
struct CrashedPageView: View {
  weak var actions: (any OverlayActions)?

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 36))
        .foregroundStyle(.secondary)
      Text("This page crashed").font(.title2.weight(.semibold))
      Text("Something went wrong while showing this page.").foregroundStyle(.secondary)
      Button("Reload") { actions?.reloadCrashedPage() }
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier("clair.crashedReload")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("clair.crashedPage")
  }
}
