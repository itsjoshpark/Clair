// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import ClairHost
import Foundation
import Testing

@testable import ClairUI

/// The fake host reaches a window through the calls Chromium makes, so the
/// window's logic can be tested without an engine (design D14).
@MainActor
struct FakeBrowserTests {
  @Test func tabChangesReachTheWindow() {
    let browser = FakeBrowser()
    let window = RecordingWindow()
    browser.clairWindow = window

    let first = browser.addTab(title: "One", url: "https://one.example/")
    let second = browser.addTab(title: "Two", url: "https://two.example/", activate: false)
    browser.change(first.with(title: "One!", isLoading: true))
    browser.moveTab(first.tabID, to: 0)
    browser.closeTabNow(first.tabID)

    #expect(
      window.calls == [
        "tabs 1", "active 1",
        "tabs 2,1",
        "tab 1",
        "tabs 1,2",
        "tabs 2", "active 2",
      ])
    #expect(window.tabs.map(\.tabID) == [second.tabID])
    #expect(window.lastTab?.title == "One!")
    #expect(window.lastTab?.isLoading == true)
  }

  @Test func suggestionsReachTheDelegate() {
    final class Delegate: NSObject, ClairAutocompleteDelegate {
      var received: [[String]] = []
      func autocomplete(_ session: any ClairAutocomplete, didUpdate suggestions: [any ClairSuggestion], finished: Bool) {
        received.append(suggestions.map(\.contents))
      }
    }
    let browser = FakeBrowser()
    let delegate = Delegate()
    let session = browser.startAutocomplete(mode: .newTab, delegate: delegate)
    session.query("wiki")
    browser.autocomplete?.post([FakeSuggestion(id: 1, contents: "Wikipedia"), FakeSuggestion(id: 2, contents: "wiki")])
    session.stop()
    browser.autocomplete?.post([FakeSuggestion(id: 3, contents: "late")])

    #expect(browser.autocomplete?.queries == ["wiki"])
    #expect(delegate.received == [["Wikipedia", "wiki"]])
  }

  @Test func closedBrowserIgnoresCommands() {
    let browser = FakeBrowser()
    let window = RecordingWindow()
    browser.clairWindow = window
    browser.addTab()
    browser.closeWindow()
    browser.goBack()
    #expect(window.calls.last == "closed")
    #expect(browser.commands.isEmpty)
  }
}
