// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import ClairHost
import Foundation

/// What the sidebar's URL field shows for a tab (sidebar spec, "URL field"):
/// the host of a web page, the full URL of a page without one (chrome://
/// pages, files), and the placeholder on the new tab page.
enum URLDisplay {
  static let placeholder = "Search or Enter URL…"

  /// The text to show, or nil for the placeholder.
  static func text(for tab: (any ClairTab)?) -> String? {
    guard let tab, !tab.isNewTabPage else {
      return nil
    }
    return text(url: tab.url, urlText: tab.urlText, displayHost: tab.displayHost)
  }

  static func text(url: URL?, urlText: String, displayHost: String?) -> String? {
    guard let url else {
      return urlText.isEmpty ? nil : urlText
    }
    switch url.scheme?.lowercased() {
    case "http", "https":
      if let host = displayHost, !host.isEmpty {
        return host
      }
      return urlText
    default:
      return urlText.isEmpty ? url.absoluteString : urlText
    }
  }

  /// What the command bar holds when Cmd+L opens it: the full URL, or empty
  /// on the new tab page.
  static func editingText(for tab: (any ClairTab)?) -> String {
    guard let tab, !tab.isNewTabPage else {
      return ""
    }
    return tab.urlText.isEmpty ? (tab.url?.absoluteString ?? "") : tab.urlText
  }
}
