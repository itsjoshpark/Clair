// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import ClairHost
import Foundation
import Observation

/// The command bar's state and keyboard handling (design D11), on one
/// autocomplete session of Chromium's per opening.
@Observable
final class CommandBarModel: NSObject, ClairAutocompleteDelegate {
  /// Why it's open.
  let mode: CommandBarMode
  /// What's in the field, without the keyword in keyword mode.
  private(set) var text: String
  /// The suggestions, best first.
  private(set) var suggestions: [any ClairSuggestion] = []
  /// The selected row; the first is selected whenever results change, except
  /// after a deletion.
  private(set) var selection = 0
  /// The search engine in keyword mode, as its name.
  private(set) var keywordName: String?
  /// Set once the bar closed; it does nothing more.
  private(set) var isClosed = false

  @ObservationIgnored private var keyword: String?
  /// The row to select on the update after a deletion, instead of the first.
  @ObservationIgnored private var selectionAfterDeletion: Int?
  @ObservationIgnored private var session: (any ClairAutocomplete)?
  @ObservationIgnored private let onClose: (Bool) -> Void

  /// Opens a session on `browser`. `onClose` runs once when the bar closes,
  /// with whether something was opened.
  init(
    mode: CommandBarMode, text: String = "", browser: any ClairBrowser,
    onClose: @escaping (Bool) -> Void
  ) {
    self.mode = mode
    self.text = text
    self.onClose = onClose
    super.init()
    session = browser.startAutocomplete(mode: mode, delegate: self)
    session?.query(text)
  }

  var selectedSuggestion: (any ClairSuggestion)? {
    suggestions.indices.contains(selection) ? suggestions[selection] : nil
  }

  /// Whether the selected suggestion offers "Search <engine>" with Tab.
  var offeredKeywordName: String? {
    guard keyword == nil, let suggestion = selectedSuggestion, suggestion.keyword != nil else {
      return nil
    }
    return suggestion.keywordName ?? suggestion.keyword
  }

  // MARK: Typing and keys

  func setText(_ newText: String) {
    guard !isClosed, newText != text else { return }
    text = newText
    selectionAfterDeletion = nil
    session?.query(newText)
  }

  /// Up and Down.
  func moveSelection(by delta: Int) {
    guard !suggestions.isEmpty else { return }
    selection = min(max(selection + delta, 0), suggestions.count - 1)
  }

  /// Picks a row with the pointer.
  func select(_ index: Int) {
    if suggestions.indices.contains(index) {
      selection = index
    }
  }

  /// Return, Shift+Return or Cmd+Return. Returns whether something opened.
  @discardableResult
  func submit(newTab: Bool = false) -> Bool {
    guard !isClosed, let suggestion = selectedSuggestion else {
      return false
    }
    let disposition: OpenDisposition =
      mode == .currentTab && !newTab ? .currentTab : .newForegroundTab
    session?.open(suggestion: suggestion.suggestionID, disposition: disposition)
    close(opened: true)
    return true
  }

  /// Tab: enters keyword mode for the selected suggestion's engine. Returns
  /// whether it did, so Tab otherwise does what it normally does.
  @discardableResult
  func acceptKeyword() -> Bool {
    guard !isClosed, keyword == nil, let suggestion = selectedSuggestion,
      let offered = suggestion.keyword
    else {
      return false
    }
    // The rest of the query, after the keyword, searches that engine.
    var rest = text
    if rest.lowercased().hasPrefix(offered.lowercased()) {
      rest = String(rest.dropFirst(offered.count))
    }
    rest = rest.trimmingCharacters(in: .whitespaces)
    keyword = offered
    keywordName = suggestion.keywordName ?? offered
    text = rest
    selectionAfterDeletion = nil
    session?.acceptKeyword(ofSuggestion: suggestion.suggestionID, text: rest)
    return true
  }

  /// The ×: deletes a suggestion wherever Chromium keeps it, such as history.
  /// The selected row stays selected, or, if it's the one deleted, the row
  /// that takes its place. Returns whether it asked to.
  @discardableResult
  func delete(_ suggestion: any ClairSuggestion) -> Bool {
    guard !isClosed, suggestion.canDelete,
      let index = suggestions.firstIndex(where: { $0.suggestionID == suggestion.suggestionID })
    else {
      return false
    }
    // Set first: Chromium sends the shorter list during the call.
    selectionAfterDeletion = index < selection ? selection - 1 : selection
    session?.delete(suggestion: suggestion.suggestionID)
    return true
  }

  /// Option+Command+Delete: deletes the selected suggestion if it can be.
  @discardableResult
  func deleteSelected() -> Bool {
    guard let suggestion = selectedSuggestion else { return false }
    return delete(suggestion)
  }

  /// Delete with an empty field: leaves keyword mode, putting the keyword
  /// back as text, as the omnibox does. Returns whether it did.
  @discardableResult
  func deleteBackwardInEmptyField() -> Bool {
    guard !isClosed, let keyword, text.isEmpty else {
      return false
    }
    self.keyword = nil
    keywordName = nil
    text = keyword
    selectionAfterDeletion = nil
    session?.clearKeyword(text: keyword)
    return true
  }

  /// Esc, or a click outside.
  func cancel() {
    close(opened: false)
  }

  private func close(opened: Bool) {
    guard !isClosed else { return }
    isClosed = true
    session?.stop()
    session = nil
    onClose(opened)
  }

  // MARK: ClairAutocompleteDelegate

  func autocomplete(_ session: any ClairAutocomplete, didUpdate suggestions: [any ClairSuggestion], finished: Bool) {
    guard !isClosed else { return }
    self.suggestions = suggestions
    selection = min(selectionAfterDeletion ?? 0, max(suggestions.count - 1, 0))
    selectionAfterDeletion = nil
  }
}
