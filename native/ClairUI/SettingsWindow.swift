// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import SwiftUI

/// The Settings window's pages, in toolbar order (design D2). A later feature
/// adds its page here.
enum SettingsPage: String, CaseIterable {
  case general
  case advanced

  /// The user default holding the page last shown (design D3).
  static let key = "ClairSettingsPage"

  var label: String {
    switch self {
    case .general: "General"
    case .advanced: "Advanced"
    }
  }

  var symbol: String {
    switch self {
    case .general: "gearshape"
    case .advanced: "slider.horizontal.3"
    }
  }

  /// The page the window opens on: the one last shown, or General.
  static func stored(in defaults: UserDefaults) -> SettingsPage {
    defaults.string(forKey: key).flatMap(SettingsPage.init(rawValue:)) ?? .general
  }
}

/// Whether Clair is the default web browser, and the request to make it so
/// (design D4).
@Observable
final class DefaultBrowser {
  static let bundleIdentifier = "dev.joshuapark.Clair"

  private(set) var isClair = false

  /// Re-reads the default from Launch Services.
  func refresh() {
    let probe = URL(string: "https://example.com")!
    let app = NSWorkspace.shared.urlForApplication(toOpen: probe)
    isClair = app.flatMap { Bundle(url: $0)?.bundleIdentifier } == Self.bundleIdentifier
  }

  /// Asks macOS to make this copy of Clair the default browser. macOS confirms
  /// with the user; the state is re-read either way.
  func makeDefault() {
    NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "http") {
      [weak self] error in
      let reason = error?.localizedDescription
      Task { @MainActor in
        if let reason {
          NativeLayer.logger.info("Clair didn't become the default browser: \(reason, privacy: .public)")
        }
        self?.refresh()
      }
    }
  }
}

struct GeneralSettingsView: View {
  let defaultBrowser: DefaultBrowser

  var body: some View {
    Form {
      Section {
        LabeledContent {
          if !defaultBrowser.isClair {
            Button("Make Default") { defaultBrowser.makeDefault() }
          }
        } label: {
          Text("Default browser")
          Text(defaultBrowser.isClair ? "Clair is your default browser." : "Clair isn't your default browser.")
        }
      }
    }
    .formStyle(.grouped)
    .scrollDisabled(true)
    .frame(width: SettingsWindowController.width)
    .fixedSize(horizontal: false, vertical: true)
  }
}

struct AdvancedSettingsView: View {
  /// Opens chrome://settings in a browser tab (design D6).
  let openMoreSettings: () -> Void

  @AppStorage(WindowDragPreference.key) private var dragFromPageTop = true

  var body: some View {
    Form {
      Section {
        Toggle("Allow window dragging from the top of webpages", isOn: $dragFromPageTop)
      }
      Section {
        LabeledContent("Search, privacy and more") {
          Button("More Settings…", action: openMoreSettings)
        }
      }
    }
    .formStyle(.grouped)
    .scrollDisabled(true)
    .frame(width: SettingsWindowController.width)
    .fixedSize(horizontal: false, vertical: true)
  }
}

/// The toolbar of pages. It stores the page shown, and the window takes the
/// page's name as its title from the selected child.
final class SettingsTabViewController: NSTabViewController {
  var defaults: UserDefaults = .standard

  override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
    super.tabView(tabView, didSelect: tabViewItem)
    if let page = (tabViewItem?.identifier as? String).flatMap(SettingsPage.init(rawValue:)) {
      defaults.set(page.rawValue, forKey: SettingsPage.key)
    }
  }
}

/// The Settings window, which Settings… in the application menu opens instead
/// of Chromium's chrome://settings tab (design D1, D7).
final class SettingsWindowController: NSObject {
  /// Chromium's IDC_OPTIONS, the application menu's Settings item.
  static let menuTag = 40015
  static let menuTitle = "Settings…"
  /// The window's width.
  static let width: CGFloat = 520
  static let moreSettingsURL = URL(string: "chrome://settings")!

  private let host: any ClairHost
  private let defaults: UserDefaults
  private let defaultBrowser = DefaultBrowser()

  /// The one Settings window, once it has been opened. Closing only hides it.
  private(set) var window: NSWindow?
  private var becameKey: NSObjectProtocol?

  init(host: any ClairHost, defaults: UserDefaults = .standard) {
    self.host = host
    self.defaults = defaults
  }

  /// Points Chromium's Settings item in the application menu at this window
  /// and titles it as Arc does. If the item isn't there, it's left alone, so it
  /// still opens chrome://settings.
  @discardableResult
  func install(in mainMenu: NSMenu?) -> Bool {
    guard let item = mainMenu?.items.first?.submenu?.items.first(where: { $0.tag == Self.menuTag }) else {
      NativeLayer.logger.error("The application menu has no Settings item; leaving it to Chromium")
      return false
    }
    item.title = Self.menuTitle
    item.target = self
    item.action = #selector(choose)
    return true
  }

  /// Brings the Settings window to the front, opening it the first time.
  func show() {
    let window = self.window ?? makeWindow()
    defaultBrowser.refresh()
    NSApplication.shared.activate()
    window.makeKeyAndOrderFront(nil)
  }

  /// Opens chrome://settings in a browser tab and closes the Settings window,
  /// so the tab is in front.
  func openMoreSettings() {
    host.open(Self.moreSettingsURL)
    window?.close()
  }

  @objc private func choose() {
    show()
  }

  private func page(_ page: SettingsPage) -> NSViewController {
    let view: AnyView =
      switch page {
      case .general: AnyView(GeneralSettingsView(defaultBrowser: defaultBrowser))
      case .advanced: AnyView(AdvancedSettingsView { [weak self] in self?.openMoreSettings() })
      }
    let controller = NSHostingController(rootView: view.defaultAppStorage(defaults))
    controller.sizingOptions = .preferredContentSize
    controller.title = page.label
    return controller
  }

  private func makeWindow() -> NSWindow {
    let tabs = SettingsTabViewController()
    tabs.defaults = defaults
    tabs.tabStyle = .toolbar
    for page in SettingsPage.allCases {
      let item = NSTabViewItem(viewController: self.page(page))
      item.identifier = page.rawValue
      item.label = page.label
      item.image = NSImage(systemSymbolName: page.symbol, accessibilityDescription: page.label)
      tabs.addTabViewItem(item)
    }
    tabs.selectedTabViewItemIndex = SettingsPage.allCases.firstIndex(of: .stored(in: defaults)) ?? 0

    let window = NSWindow(contentViewController: tabs)
    window.styleMask = [.titled, .closable]
    window.toolbarStyle = .preference
    window.isReleasedWhenClosed = false
    window.center()
    becameKey = NotificationCenter.default.addObserver(
      forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.defaultBrowser.refresh() }
    }
    self.window = window
    return window
  }
}
