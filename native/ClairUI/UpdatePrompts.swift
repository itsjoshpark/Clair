// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit

/// What the update flow asks or tells the user.
protocol UpdatePrompting {
  func showUpToDate(version: String)
  func showCheckFailed(reason: String)
  /// Returns true if the user chose "Restart and Update".
  func askToRestart(forVersion version: String) -> Bool
  /// Returns true if the user chose to restart anyway.
  func askToCloseIncognitoWindows() -> Bool
}

/// Small alerts, the only update UI Clair shows (design D4).
struct UpdateAlerts: UpdatePrompting {
  func showUpToDate(version: String) {
    run(title: "Clair is up to date", message: "You're running Clair \(version).", buttons: ["OK"])
  }

  func showCheckFailed(reason: String) {
    run(title: "Clair couldn't check for updates", message: reason, buttons: ["OK"])
  }

  func askToRestart(forVersion version: String) -> Bool {
    run(
      title: "Clair \(version) is ready",
      message: "Restart Clair to finish updating. Your windows and tabs will come back.",
      buttons: ["Restart and Update", "Later"]
    ) == .alertFirstButtonReturn
  }

  func askToCloseIncognitoWindows() -> Bool {
    run(
      title: "Restart Clair and close your incognito windows?",
      message: "Your other windows and tabs will come back, but incognito windows won't reopen.",
      buttons: ["Restart and Update", "Later"]
    ) == .alertFirstButtonReturn
  }

  @discardableResult
  private func run(title: String, message: String, buttons: [String]) -> NSApplication.ModalResponse {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    for button in buttons {
      alert.addButton(withTitle: button)
    }
    NSApp.activate()
    return alert.runModal()
  }
}
