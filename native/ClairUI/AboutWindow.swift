// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import SwiftUI

/// The text of the About window (design D13), from the app's Info.plist and the
/// engine versions Chromium reports.
struct AboutInfo: Equatable {
  static let name = "Clair"

  /// "Version 0.1.0 (123)": the Clair version and build number.
  let version: String
  /// The Chromium version websites see, then the ungoogled-chromium release.
  let engine: String
  /// Chromium writes it, localized, into InfoPlist.strings.
  let copyright: String?

  /// `value` looks up an Info.plist key, localized where the bundle localizes it.
  init(value: (String) -> Any?, chromiumVersion: String, ungoogledChromiumVersion: String) {
    let short = value("CFBundleShortVersionString") as? String ?? ""
    let build = value("CFBundleVersion") as? String ?? ""
    version = build.isEmpty ? "Version \(short)" : "Version \(short) (\(build))"
    engine = "Chromium Engine Version \(chromiumVersion)\n(ungoogled-chromium \(ungoogledChromiumVersion))"
    copyright = (value("NSHumanReadableCopyright") as? String).flatMap { $0.isEmpty ? nil : $0 }
  }

  init(bundle: Bundle, host: any ClairHost) {
    self.init(
      value: { bundle.object(forInfoDictionaryKey: $0) },
      chromiumVersion: host.chromiumVersion,
      ungoogledChromiumVersion: host.ungoogledChromiumVersion)
  }

  /// The credits and license line, with its links.
  var credits: AttributedString {
    func link(_ text: String, _ destination: AboutLink) -> AttributedString {
      var link = AttributedString(text)
      link.link = destination.url
      return link
    }
    var text = AttributedString("\(Self.name) is made possible by the ")
    text += link("Chromium", .chromium)
    text += AttributedString(" open source project, Chromium's ")
    text += link("open source software", .chromiumCredits)
    text += AttributedString(", as well as other ")
    text += link("open source software", .otherCredits)
    text += AttributedString(". It's free software under the ")
    text += link("GPLv3", .license)
    text += AttributedString(", with no warranty.")
    return text
  }
}

/// Where the About window's links go. They open in a Clair tab, through the host.
enum AboutLink: CaseIterable {
  case chromium
  case chromiumCredits
  case otherCredits
  case license

  var url: URL {
    switch self {
    case .chromium: URL(string: "https://www.chromium.org/")!
    case .chromiumCredits: URL(string: "chrome://credits/")!
    case .otherCredits: URL(string: "https://github.com/itsjoshpark/Clair/blob/main/CREDITS.md")!
    case .license: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!
    }
  }
}

struct AboutView: View {
  let info: AboutInfo
  let icon: NSImage

  var body: some View {
    VStack(spacing: 0) {
      Image(nsImage: icon)
        .resizable()
        .frame(width: 96, height: 96)
        .accessibilityHidden(true)
      Text(AboutInfo.name)
        .font(.title2.bold())
        .padding(.top, 6)
      Text(info.version)
        .padding(.top, 12)
      Text(info.engine)
      if let copyright = info.copyright {
        Text(copyright)
          .padding(.top, 12)
      }
      Text(info.credits)
        .padding(.top, 12)
    }
    .multilineTextAlignment(.center)
    .fixedSize(horizontal: false, vertical: true)
    .padding(.horizontal, 28)
    .padding(.top, 12)
    .padding(.bottom, 24)
    .frame(width: 420)
  }
}

/// The About window, which "About Clair" in the application menu opens instead
/// of Chromium's chrome://settings/help tab (design D13).
final class AboutWindowController: NSObject {
  static let menuTitle = "About Clair"
  static let windowTitle = "About Clair"

  private let host: any ClairHost
  private let info: AboutInfo

  /// The one About window, once it has been opened. Closing only hides it.
  private(set) var window: NSWindow?

  init(host: any ClairHost, info: AboutInfo) {
    self.host = host
    self.info = info
  }

  /// Points Chromium's "About Clair", the first item of the application menu, at
  /// this window. If that item isn't where it's expected, it's left alone, so it
  /// still opens chrome://settings/help.
  @discardableResult
  func install(in mainMenu: NSMenu?) -> Bool {
    guard let item = mainMenu?.items.first?.submenu?.items.first, item.title == Self.menuTitle else {
      NativeLayer.logger.error("The application menu doesn't start with \(Self.menuTitle, privacy: .public); leaving it to Chromium")
      return false
    }
    item.target = self
    item.action = #selector(choose)
    return true
  }

  /// Brings the About window to the front, opening it the first time.
  func show() {
    let window = self.window ?? makeWindow()
    NSApplication.shared.activate()
    window.makeKeyAndOrderFront(nil)
  }

  @objc private func choose() {
    show()
  }

  private func makeWindow() -> NSWindow {
    let host = self.host
    let view = AboutView(info: info, icon: NSApplication.shared.applicationIconImage)
      .environment(
        \.openURL,
        OpenURLAction { url in
          host.open(url)
          return .handled
        })
    let window = NSWindow(contentViewController: NSHostingController(rootView: view))
    window.styleMask = [.titled, .closable]
    window.title = Self.windowTitle
    window.titleVisibility = .hidden
    window.isReleasedWhenClosed = false
    window.center()
    self.window = window
    return window
  }
}
