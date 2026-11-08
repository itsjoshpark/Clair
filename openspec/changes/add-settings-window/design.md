# Design

## Context

See proposal.md for why, and `specs/settings-window/spec.md` for the required behavior.

**Chromium's Settings item today** (read from the patched tree of the last engine build):
- `chrome/browser/ui/cocoa/main_menu_builder.mm` builds it in the application menu as `Item(IDS_PREFERENCES).tag(IDC_OPTIONS).target(app_delegate).action(@selector(showPreferences:))`, with the shortcut Cmd+,. `IDC_OPTIONS` is 40015.
- On macOS, `IDS_PREFERENCES` is "Preferences...". Arc's item, and Clair's planned menu (`arc-reference/clair-menus.md`), read "Settings…".
- `AppController` enables the item only while it's the item's target: the `IDC_OPTIONS` case in its `validateUserInterfaceItem:` requires that a browser can open and that the key window isn't modal.

**What ClairUI already does with Chromium's menu** (`native/ClairUI/NativeLayer.swift`): at start-up it retargets About Clair to `AboutWindowController`, retitles File › Open Location… by its tag (`MainMenuTitles`), and adds Edit › Copy URL. About's controller is the model for this change: one window, created when first opened, hidden on close, with `install(in:)` returning false and leaving Chromium's item alone when the menu isn't as expected.

**Preferences ClairUI owns today:** `ClairDragWindowFromPageTop` (`WindowDragPreference`, registered as true and read at each press, so open windows follow a change at once), and the sidebar's remembered width and hidden state, which aren't settings.

**Arc's window** (`arc-reference/look-and-behaviour.md`, Settings window): an icon toolbar of pages with the page's name as the title, each page's rows in rounded grouped cards with controls on the right.

## Goals / Non-Goals

**Goals:**
- Settings… opens a native window with Arc's structure, built so that later features add a page or a row without reworking the window.
- No engine change: the work stays in `ClairUI`, so the change builds in minutes against the current engine.

**Non-Goals:**
- A settings model shared with Chromium, or any `ClairHost` API for Chromium's preferences.
- Matching Arc's pages pixel for pixel. The look comes from AppKit's and SwiftUI's standard settings controls.

## Decisions

### D1. Take over Chromium's item by its tag, and retitle it

`SettingsWindowController.install(in:)` finds the application menu's item with tag `IDC_OPTIONS` (40015), sets its target and action to the controller, and sets its title to "Settings…". The shortcut stays Chromium's Cmd+,. If no item in the application menu has that tag, it logs an error, returns false and changes nothing, so Settings… keeps opening `chrome://settings`.

- **Matching by tag**, as `MainMenuTitles` does, rather than by title as About does: the title is the part this change rewrites, and it's a localized string, while the tag is Chromium's command ID.
- **Retargeting the existing item** keeps exactly one Settings item. Adding a second item would leave Chromium's in place; removing Chromium's and adding Clair's would lose its place and shortcut if Chromium rebuilds the menu.
- **Once retargeted**, `AppController` no longer validates the item, so it stays enabled even while a browser window shows a modal sheet. That's fine for a window that doesn't depend on any browser window.
- **Alternatives:** a patch to `main_menu_builder.mm` that sends the item to `ClairUI` changes the engine key for no gain over retargeting at start-up, which About already relies on.

### D2. An NSTabViewController in toolbar style, with SwiftUI pages

The window is an `NSWindow` whose content view controller is an `NSTabViewController` with `tabStyle = .toolbar`. Each page is a tab view item with a label and an SF Symbol (`gearshape` for General, `slider.horizontal.3` for Advanced), and an `NSHostingController` around a SwiftUI `Form` with `.formStyle(.grouped)`, which draws the rounded cards. Each hosting controller uses `sizingOptions = .preferredContentSize`, so the window takes each page's height at a fixed width of 520 points; the tab view controller animates the change. The window is titled and closable, not resizable, with the title following the selected page.

- **Alternatives:** SwiftUI's `Settings` scene, whose `TabView` becomes the toolbar of pages, needs a SwiftUI `App`, and `ClairUI` is a framework inside Chromium's `NSApplication`. A SwiftUI `TabView` in a single hosting controller draws a segmented control in the content, not Arc's toolbar of icons. `NSTabViewController` gives the toolbar, its selection and the title for free.
- **Adding a page later** means adding a case to a `SettingsPage` enum (identifier, label, symbol, view), in the toolbar order.

### D3. The last page is a user default

The shown page's identifier is stored under `ClairSettingsPage` whenever the selection changes, and read when the window is made. A missing or unknown value opens General, so removing or renaming a page never strands the window.

### D4. The default browser row asks NSWorkspace

- **State:** Clair is the default browser when `NSWorkspace.shared.urlForApplication(toOpen:)` for an `https:` URL names an app whose bundle identifier is `dev.joshuapark.Clair`. Comparing the bundle identifier rather than the app's URL treats every copy of Clair alike (for example, one run from a DMG or a `run-local.sh` package), as macOS does.
- **Make Default:** `NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "http")`. macOS shows its own confirmation, and changing the `http` handler makes the app the default web browser, `https` included. The row re-reads the state when the call completes, whether the user confirmed or not.
- **Freshness:** the row re-reads the state each time the Settings window becomes key, so a change made in System Settings or with Chromium's own Set as Default Browser shows up.
- **Alternatives:** going through Chromium's `shell_integration` would need a new `ClairHost` method, and so an engine build, for what one AppKit call does. The Clair › Set as Default Browser menu item is Chromium's and stays as it is.

### D5. The window dragging toggle binds to the existing preference

The toggle is bound with `@AppStorage(WindowDragPreference.key)` and a default of true, the same default `WindowDragPreference` registers. Since the strip reads the preference at each press, a change applies to open windows with no notification. The label is Arc's: "Allow window dragging from the top of webpages".

### D6. More Settings… goes through the host

The button calls `host.open(URL(string: "chrome://settings")!)` and then closes the Settings window, so the tab it opened is in front. Closing only hides the window (D7), so the next Settings… shows it again on Advanced. `ClairHost`'s `openURL:` already opens a URL, `chrome://` included, in a new foreground tab of the most recently active browser window, or in a new window if none is open, which is what the spec asks for. About's credits links use the same call.

### D7. One window, owned by the native layer

`NativeLayer` creates `SettingsWindowController` next to `AboutWindowController`, installs it, and keeps it. The controller makes the window when first shown, with `isReleasedWhenClosed = false`, so closing hides it and the next Settings… shows the same window on the page last shown. Showing activates Clair and makes the window key, with or without a browser window open.

### D8. Tests: few, on the fundamentals

- **Unit tests** (`native/ClairUITests/SettingsTests.swift`, modelled on `AboutTests.swift`): the takeover retargets and retitles the item tagged `IDC_OPTIONS`, and leaves a menu without it alone; choosing the item twice shows the same window, which opens on the stored page; "More Settings…" calls `open(_:)` with `chrome://settings` on `FakeHost` and closes the window.
- **Runtime test:** `testApplicationMenuNamesClair` already starts Clair and opens the Clair menu, so it grows into `testApplicationMenu`: exactly one item titled "Settings…" and none titled "Preferences…"; choosing it shows a window titled "General" with General and Advanced toolbar items; and then no page target's URL starts with `chrome://settings` (`pageTargets()`). Checking after the window appears gives the "no tab" check a sync point without a fixed sleep. No new browser launch, so quality checks take seconds longer, not a launch longer.
- **Not automated,** at the owner's request to keep tests to fundamentals: the toggle (a plain user default), the default browser row (testing it would change the machine's real default browser), and the look. These are checked by hand.

## Risks / Trade-offs

- [Chromium moves or rebuilds the Settings item, for example on a profile or locale change] → Matching by tag survives a reorder. If the item disappears, `install(in:)` leaves Chromium's behavior in place, and the runtime test fails on the title, so quality checks catch it. About already relies on Chromium not rebuilding the application menu after start-up.
- [Cmd+W doesn't close the Settings window, because Chromium's File › Close Tab owns Cmd+W and Chromium decides per key window whether Close Tab or Close Window gets it] → Checked by hand, with About as the reference. If Cmd+W doesn't close it, the window handles `performClose:` itself; no patch.
- [The title doesn't follow the selected page] → `NSTabViewController` in toolbar style normally sets the window's title from the selected item's label; if it doesn't here, the controller sets it in `tabView(_:didSelect:)`.
- [Checking "Make Default" by hand changes the owner's real default browser] → The hand check notes the current default first and restores it in System Settings afterwards.
- [Two pages with one row each look sparse] → Accepted with the owner: the shape is Arc's, and Peek and Profiles fill it.

## Migration Plan

None. The window only reads and writes user defaults that already exist (`ClairDragWindowFromPageTop`) or are new (`ClairSettingsPage`). Rolling back restores Chromium's Settings… item, which then opens `chrome://settings` again.
