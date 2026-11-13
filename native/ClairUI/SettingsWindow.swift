// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import SwiftUI

/// The Settings window's pages, in toolbar order (design D2). A later feature
/// adds its page here. The window opens on General each time (add-profiles
/// design D12).
enum SettingsPage: String, CaseIterable {
  case general
  case profiles
  case links
  case advanced

  var label: String {
    switch self {
    case .general: "General"
    case .profiles: "Profiles"
    case .links: "Links"
    case .advanced: "Advanced"
    }
  }

  var symbol: String {
    switch self {
    case .general: "gearshape"
    case .profiles: "person.2"
    case .links: "link"
    case .advanced: "slider.horizontal.3"
    }
  }
}

/// Whether Clair reopens the previous session's windows at launch
/// (add-profiles design D6): off unless the user turns it on. The engine reads
/// it once at launch.
enum RestoreWindowsPreference {
  static let key = "ClairRestoreWindows"

  static func isEnabled(in defaults: UserDefaults) -> Bool {
    defaults.bool(forKey: key)
  }
}

/// Chromium's warn-before-quitting setting, through the host (add-profiles
/// design D11).
@MainActor
@Observable
final class WarnBeforeQuitting {
  @ObservationIgnored private let host: (any ClairHost)?
  private(set) var isOn: Bool

  init(host: (any ClairHost)?) {
    self.host = host
    isOn = host?.warnsBeforeQuitting ?? true
  }

  func set(_ on: Bool) {
    host?.warnsBeforeQuitting = on
    isOn = host?.warnsBeforeQuitting ?? on
  }

  /// Re-reads it, as Chromium's own menu item may have changed it.
  func refresh() {
    isOn = host?.warnsBeforeQuitting ?? isOn
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

/// How links open (add-peek design D10).
struct LinksSettingsView: View {
  @AppStorage(PeekPreference.key) private var peekOnShiftClick = true

  var body: some View {
    Form {
      Section {
        Toggle("Open a Peek window when clicking on links with Shift held", isOn: $peekOnShiftClick)
          // Accessibility reads the switch and its label as separate elements.
          .accessibilityIdentifier("clair.peekToggle")
      }
    }
    .formStyle(.grouped)
    .scrollDisabled(true)
    .frame(width: SettingsWindowController.width)
    .fixedSize(horizontal: false, vertical: true)
  }
}

struct AdvancedSettingsView: View {
  let warnBeforeQuitting: WarnBeforeQuitting
  /// Opens chrome://settings in a browser tab (design D6).
  let openMoreSettings: () -> Void

  @AppStorage(WindowDragPreference.key) private var dragFromPageTop = true
  @AppStorage(RestoreWindowsPreference.key) private var restoreWindows = false

  var body: some View {
    Form {
      Section {
        Toggle("Allow window dragging from the top of webpages", isOn: $dragFromPageTop)
        Toggle(
          "Warn before quitting",
          isOn: Binding(get: { warnBeforeQuitting.isOn }, set: { warnBeforeQuitting.set($0) })
        )
        .accessibilityIdentifier("clair.warnBeforeQuittingToggle")
        Toggle("When opening Clair, restore windows from previous session", isOn: $restoreWindows)
          .accessibilityIdentifier("clair.restoreWindowsToggle")
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

/// The toolbar of pages. The window takes the page's name as its title from
/// the selected child.
final class SettingsTabViewController: NSTabViewController {}

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
  let profiles: ProfilesPageState
  private let warnBeforeQuitting: WarnBeforeQuitting
  /// The window's dialogs: the profile dialogs.
  private(set) var dialogs: ClairDialogPresenter?

  /// The one Settings window, once it has been opened. Closing only hides it.
  private(set) var window: NSWindow?
  private var becameKey: NSObjectProtocol?

  /// `spaces` is the app's model of Spaces and profiles, a new one over
  /// `host` when nil.
  init(host: any ClairHost, spaces: SpacesModel? = nil, defaults: UserDefaults = .standard) {
    self.host = host
    self.defaults = defaults
    profiles = ProfilesPageState(spaces: spaces ?? SpacesModel(host: host), host: host)
    warnBeforeQuitting = WarnBeforeQuitting(host: host)
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
    // It opens on General each time (add-profiles D12).
    if !window.isVisible, let tabs = window.contentViewController as? NSTabViewController {
      tabs.selectedTabViewItemIndex = 0
    }
    defaultBrowser.refresh()
    warnBeforeQuitting.refresh()
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
      case .profiles: AnyView(ProfilesSettingsView(state: profiles, actions: self))
      case .links: AnyView(LinksSettingsView())
      case .advanced:
        AnyView(
          AdvancedSettingsView(warnBeforeQuitting: warnBeforeQuitting) { [weak self] in self?.openMoreSettings() })
      }
    let controller = NSHostingController(rootView: view.defaultAppStorage(defaults))
    controller.sizingOptions = .preferredContentSize
    controller.title = page.label
    return controller
  }

  private func makeWindow() -> NSWindow {
    let tabs = SettingsTabViewController()
    tabs.tabStyle = .toolbar
    for page in SettingsPage.allCases {
      let item = NSTabViewItem(viewController: self.page(page))
      item.identifier = page.rawValue
      item.label = page.label
      item.image = NSImage(systemSymbolName: page.symbol, accessibilityDescription: page.label)
      tabs.addTabViewItem(item)
    }
    tabs.selectedTabViewItemIndex = 0

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
    dialogs = ClairDialogPresenter(window: window)
    return window
  }
}

// MARK: The Profiles page's actions (add-profiles design D12)

extension SettingsWindowController: ProfilesPageActions {
  func addProfile() {
    guard let dialogs else { return }
    ProfileDialogs.showNewProfile(on: dialogs, spaces: profiles.spaces) { [weak self] profileID in
      if let profileID {
        self?.profiles.select(profileID)
      }
    }
  }

  func removeProfile(_ profile: any ClairProfile) {
    guard let dialogs, profiles.spaces.canDeleteProfile(profile.profileID) else { return }
    let index = profiles.spaces.profiles.firstIndex { $0.profileID == profile.profileID } ?? 0
    let profileID = profile.profileID
    ProfileDialogs.showDelete(of: profile, on: dialogs, spaces: profiles.spaces) { [weak self] deleted in
      if deleted {
        self?.profiles.removed(profileID, at: index)
      }
    }
  }

  func renameProfile(_ profile: any ClairProfile) {
    guard let dialogs else { return }
    ProfileDialogs.showRename(of: profile, on: dialogs, spaces: profiles.spaces)
  }

  /// "Other…": macOS's folder picker, as a sheet on the Settings window.
  func chooseDownloadFolder() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.prompt = "Select"
    panel.directoryURL = profiles.downloadDirectory
    let done: (NSApplication.ModalResponse) -> Void = { [weak self, weak panel] response in
      guard response == .OK, let url = panel?.url else { return }
      self?.profiles.useFolder(url)
    }
    if let window {
      panel.beginSheetModal(for: window, completionHandler: done)
    } else {
      done(panel.runModal())
    }
  }

  func didOpenLink() {
    window?.close()
  }
}
