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

  static let width: CGFloat = 760

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Image(systemName: "magnifyingglass").foregroundStyle(OverlayStyle.secondary)
        if let keywordName = model.keywordName {
          Text(keywordName)
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.18), in: .capsule)
            .accessibilityIdentifier("clair.commandBarKeyword")
        }
        TextField(
          "Search or Enter URL…",
          text: Binding(get: { model.text }, set: { model.setText($0) })
        )
        .textFieldStyle(.plain)
        .font(.system(size: 20))
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
        .onKeyPress(.tab) {
          model.acceptKeyword() ? .handled : .ignored
        }
        .onKeyPress(.delete) {
          model.deleteBackwardInEmptyField() ? .handled : .ignored
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
          Text("Search \(offered) ⇥")
            .font(.caption)
            .foregroundStyle(OverlayStyle.secondary)
        }
      }
      .padding(.horizontal, 16)
      .frame(height: 54)
      if !model.suggestions.isEmpty {
        Divider()
        ScrollView {
          VStack(spacing: 2) {
            ForEach(Array(model.suggestions.enumerated()), id: \.element.suggestionID) { index, suggestion in
              SuggestionRow(suggestion: suggestion, isSelected: index == model.selection)
                .onHover { if $0 { model.select(index) } }
                .onTapGesture {
                  model.select(index)
                  model.submit()
                }
            }
          }
          .padding(6)
        }
        .frame(maxHeight: 340)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
    .background(OverlayStyle.background, in: .rect(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.08)))
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
  }
}

struct SuggestionRow: View {
  let suggestion: any ClairSuggestion
  let isSelected: Bool

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

  var body: some View {
    HStack(spacing: 10) {
      Group {
        if let icon = suggestion.icon {
          Image(nsImage: icon).resizable().interpolation(.high)
        } else {
          Image(systemName: symbol)
        }
      }
      .frame(width: 18, height: 18)
      .foregroundStyle(isSelected ? .white : OverlayStyle.secondary)
      Text(suggestion.contents).lineLimit(1)
      if let domain {
        Text("— \(domain)").lineLimit(1).foregroundStyle(isSelected ? .white.opacity(0.8) : OverlayStyle.secondary)
      }
      Spacer(minLength: 0)
      if suggestion.hasTabMatch {
        Text("Switch to Tab")
          .font(.caption)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background((isSelected ? Color.white : Color.primary).opacity(0.15), in: .capsule)
      }
    }
    .foregroundStyle(isSelected ? .white : .primary)
    .padding(.horizontal, 10)
    .frame(height: 40)
    .background(isSelected ? Color.accentColor : .clear, in: .rect(cornerRadius: 8))
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("clair.suggestion")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
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
      Button { actions?.find(text, forward: true) } label: { Image(systemName: "chevron.down") }
        .buttonStyle(.plain).disabled(text.isEmpty).focusable(false)
      Button { actions?.closeFind() } label: { Image(systemName: "xmark") }
        .buttonStyle(.plain).focusable(false)
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
