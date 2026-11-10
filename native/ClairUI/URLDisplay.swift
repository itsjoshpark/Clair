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

  /// Whether the URL field shows the not-secure icon (arc-site-control-center
  /// design D9). Chromium decides; ClairUI has no rules of its own.
  static func showsNotSecure(for tab: (any ClairTab)?) -> Bool {
    tab?.isNotSecure == true
  }

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
        return withoutWWW(host)
      }
      return urlText
    default:
      return urlText.isEmpty ? url.absoluteString : urlText
    }
  }

  /// The host without a leading "www.", as Arc shows it, unless nothing
  /// would be left but a public suffix's worth ("www.com").
  static func withoutWWW(_ host: String) -> String {
    let prefix = "www."
    guard host.lowercased().hasPrefix(prefix) else { return host }
    let rest = host.dropFirst(prefix.count)
    return rest.contains(".") ? String(rest) : host
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
