# Design

## Context

See proposal.md, "Why". What stands in the way today, from reading the engine tree on the runner (`build/base` before Clair's layer, `build/src` after it):

- **Domain substitution** rewrites every Google host in the files on ungoogled-chromium's `domain_substitution.list`. `build.sh` applies it after Clair's patches and overlay, so Clair's own text is rewritten too. Two files name the store:
  - `extensions/common/extension_urls.cc` holds the store's base URLs, the CRX update URL `https://clients2.google.com/service/update2/crx` and the store API URL.
  - `extensions/common/api/_api_features.json` holds the `webstorePrivate` and `management` matches for `https://chromewebstore.google.com/*`.
  - Substituted, the real store isn't the store: it gets no `webstorePrivate`, so its page disables "Add to Chrome".
  - Both files hold nothing else that substitution affects, apart from the hosts `IsSafeBrowsingUrl()` matches, which is only a predicate.
- **Installed store extensions update through `UpdateService`, not `ExtensionDownloader`.** `ExtensionUpdater::CanUseUpdateService` picks it for an installed extension whose update URL is the store's or empty. It posts to `update.googleapis.com`, which comes from `components/component_updater/component_updater_url_constants.cc` and stays substituted, so those checks can only fail.
- **`disable-webstore-urls.patch` (ungoogled-chromium)** does four things:
  - `ExtensionDownloader::DoStartAllPending` no longer starts update checks.
  - `SanitizeUpdateURL()` no longer fills in the store's update URL for extensions that have none.
  - The store's origins no longer get a dedicated renderer process.
  - Store extensions are no longer content-verified.
- **`0005-disable-default-extensions.patch` (inox)** empties `WebstoreInstaller::DownloadCrx` and `StartCrxInstaller`, so even an approved store install downloads nothing.
- **Install and remove prompts.**
  - Store installs reach `ShowExtensionInstallDialogImpl` (`extension_install_dialog_view.cc`), which shows a Views browser-modal dialog.
  - Removals reach `ExtensionUninstallDialogImpl::Show` (`extension_uninstall_dialog_impl.cc`). Like the post-install box, it calls `ShowDialog(parent, …)`, which falls back to a browser-modal dialog because the native window has no `ExtensionsContainerViews`.
  - The post-install box has no buttons on desktop, so only Esc closes it.
- **The popup** is `ExtensionPopupWindow` (`native/ClairUI/ExtensionPopupWindow.swift`): a borderless child window with a 10 pt corner mask, positioned by `ClairExtensions::Popup` (`overlay/chrome/browser/clair/window/clair_extensions.mm`).
  - Measured against Arc with uBlock Origin Lite, both pages are 273×374. Arc's window adds a title bar, with the close button enabled and minimise and zoom disabled. A click outside or Esc closes Arc's.
- **`chrome.action.openPopup()`** fails in `OpenPopupInBrowser` (`extension_action_api.cc`) because `ClairBrowserWindow::IsToolbarVisible()` returns false. Its only other callers are the iOS promo and Views-only code.
- **Helium** (GPL-3.0) solves the store with:
  - its own `domain_substitution.list`;
  - a component extension, `extstore_fixups`, whose content scripts rename the store's button and remove its "Switch to Chrome" prompts;
  - a download proxy, which Clair doesn't need.

## Goals / Non-Goals

**Goals:**
- Undo exactly what ungoogled-chromium and inox removed for store installs and updates, with each restored hunk traceable to the hunk it reverts.
- Keep the rest of the extension UI native and owned by `ClairUI`, behind small hooks.

**Non-Goals:**
- Restoring the store's hosted app, content verification, update pings' "days since active" bookkeeping, or OAuth credentials for update fetches.
- Replacing Chromium's other extension dialogs, such as the extensions menu's site access or blocked-action bubbles.

## Decisions

### D1. A Clair list of files that domain substitution leaves out

`utils/domain_substitution_exclude.list` names the two files. Before domain substitution, `build.sh` calls a new `scripts/filter-domain-substitution.sh`, which writes ungoogled-chromium's list without them to a temporary file. `build.sh` passes that file to `domain_substitution.py` with `-f`. A listed file that isn't in ungoogled-chromium's list stops the build with an error naming it, so a renamed file can't silently drop out. The script has its own `*.test.sh`, like the other build helpers. The list is under `utils/`, already an engine input; the script joins `scripts/engine-key.sh`'s inputs.

*Alternatives:*
- **Splitting the hosts in Clair's patched C++** (`"chromewebstore.google" ".com"`) dodges the regex. But it doesn't work in JSON, and it hides the hosts from anyone reading the source.
- **Turning on `webstorePrivate` through `_api_features.json`'s delegated availability check** would need a hook in the extensions client, and the URLs in `extension_urls.cc` would still be wrong.
- **Forking ungoogled-chromium's list**, as Helium does, means re-merging it on every engine bump.

### D2. `patches/clair/restore-web-store.patch` reverts the store and update hunks only

The patch puts back these hunks:
- the update check loop in `ExtensionDownloader::DoStartAllPending`;
- the HTTPS rule in `SanitizeUpdateURL`, but not its default update URL, so an extension with no update URL is never checked against the store (spec "Extensions update automatically");
- the dedicated process for the store's origins, which is a security property of the page that can install extensions;
- `WebstoreInstaller::DownloadCrx`, `StartCrxInstaller` and the `Webstore Downloads` folder.

It adds one hunk that isn't a revert: `ExtensionUpdater::CanUseUpdateService` returns false, so store updates use the restored `ExtensionDownloader` and `clients2.google.com`. Helium does the same.

It leaves the rest of both upstream patches as they are: content verification, the extension migrator's blank URL, the removed "days since active" ping, the cookies-only credentials, the web store app, and the histogram changes.

Each revert hunk names the upstream patch and hunk it undoes. The `chromium-engine` spec allows this one category of behavior patch.

*Alternatives:*
- **Removing the two upstream patches from the series** would bring back everything else they turn off, and Clair's series doesn't edit ungoogled-chromium's.
- **Leaving the component updater's URL file out of domain substitution** would let `UpdateService` work, but adds a Google host and un-substitutes the address the component updater uses.

### D3. The store fixes ship as a component extension in the overlay

`overlay/components/clair_store_fixups/` holds `manifest.json`, the two content scripts and their `BUILD.gn`/grd, adapted from Helium's `extstore_fixups` and credited in `CREDITS.md`.

| Script | World | What it does |
|---|---|---|
| Isolated-world script | isolated | Replaces "Chrome" / "Google Chrome" in the main install button's text with "Clair", which gives "Add to Clair" and "Remove from Clair". Removes the promo popup and the "Switch to Chrome" banner. Re-runs through a `MutationObserver` as the single-page store re-renders. |
| Main-world script | main | Forces the store's Chrome-eligibility check, as Helium's does. Only added if the banner can't be removed in the isolated world. |

A hook in `component_loader.cc` registers it, the extension's ID and manifest resource are added to the component allowlist, its resources join `ChromeComponentExtensionResourceManager`, and its grd is wired into `chrome_paks.gni`, `chrome/browser/extensions/BUILD.gn` and `resource_ids.spec`. These small hunks are in a new `patches/clair/store-fixups-component.patch`.

Component extensions may script the store, which other extensions may not. No other part of the store's text is changed (spec "Store wording names Clair").

*Alternative:* doing the same from ClairUI with a user script injected into the store tab. That needs a new contract call per navigation and races the page's rendering.

### D4. Install and remove confirmations: two contract calls, `NSAlert` sheets in ClairUI

Contract additions to `native/ClairHost.h`:
- A snapshot `ClairExtensionPrompt` with:
  - `promptID`;
  - `kind`: install, remove, or other;
  - `extensionName` and `icon`;
  - for other prompts, Chromium's `title`, `permissionsHeading`, `permissions` (each line with its details folded in, indented), `acceptLabel` and `cancelLabel`.
- `-[ClairWindow showExtensionPrompt:]` and `-[ClairWindow dismissExtensionPrompt:]`.
- `-[ClairBrowser answerExtensionPrompt:accepted:]`.

These follow the contract's rules: a snapshot with an ID, and a command naming an ID that's gone does nothing.

ClairUI owns the wording:
- **Install:** "Add "<name>" to Clair?", "It can:", "Add Extension".
- **Remove:** "Remove "<name>" from Clair?", "Remove Extension", with `hasDestructiveAction`.
- **Other:** Chromium's strings.

ClairUI shows the prompt with `NSAlert.beginSheetModal(for:)`, queueing one behind another if two arrive. A window that closes with a prompt pending answers it as a cancel.

Chromium side:
- **`ShowExtensionInstallDialogImpl`** gets a first line: `if (clair::ShowExtensionInstallPrompt(...)) return;`. The hook keeps the `DoneCallback` keyed by the prompt's ID in the window's `ClairExtensions`.
  - On an answer it runs the callback with `ACCEPTED` (or `ACCEPTED_WITH_WITHHELD_PERMISSIONS` when `ShouldWithheldPermissionsOnDialogAccept()`) or `USER_CANCELED`.
  - It returns false, and Chromium's own dialog shows, when the parent isn't a Clair window or the prompt needs input the alert can't take: an extension request with a justification field, or parent approval.
- **`ExtensionUninstallDialogImpl::Show`** gets a first line that hands the dialog to `clair::ShowExtensionRemovePrompt`, with a callback that calls `OnDialogClosed(CLOSE_ACTION_UNINSTALL)` or `OnDialogClosed(CLOSE_ACTION_CANCELED)`. `Close()` and the destructor dismiss it through the contract. There's no report-abuse checkbox, so `CLOSE_ACTION_UNINSTALL_AND_CHECKBOX_CHECKED` never happens.

Both hooks join `native-window-hook.patch`.

*Alternatives:*
- **Arc's custom panel** (two icons, key caps): more ClairUI code for little gain. The owner chose the system alert on 2026-11-08.
- **Keeping Chromium's Views dialogs and only fixing their fallback:** not Arc-like, and the post-install box would still need its own fix.

### D5. No post-install box; pin instead

In `ExtensionInstallUIDesktop::OnInstallSuccess`, before `TriggerPostInstallDialog`, a hook asks `clair::ExtensionInstalled(browser_window, extension)`. For a Clair window, it records the extension ID with that window's `ClairExtensions` and returns true, and Chromium skips the dialog. `OnInstallSuccess` only runs for installs with UI that aren't updates (`skip_post_install_ui()`), so updates, policy and sync never reach it. That matches the spec's "keeps their pinned state".

`ClairExtensions` pins the ID with `ToolbarActionsModel::SetActionVisibility(id, true)`: at once if the model already has the action, otherwise from `OnToolbarActionAdded`. It drops the ID if the extension has no action. Chromium's own post-install path waits on `ExtensionInstalledWatcher` for the same race.

### D6. The popup becomes a titled `NSWindow`

`ExtensionPopupWindow` changes:
- **Style:** `[.titled, .closable]`, with no miniaturize or resize, so those buttons show disabled as Arc's do. The title is hidden, but the window's accessibility title is the extension's name, taken from ClairUI's action snapshot.
- **Size:** the system's standard title bar, not Arc's 32 pt, following the owner's preference for native metrics over Arc's (Settings window, 2026-11-07). The page fills the content rect, and the corner mask goes away.
- **Kept:** the child-window relationship (it stays above its browser window), the starting position beside the anchor, the local event monitor (outside click, Esc, a click on the anchor), and closing when the browser window moves.
- **New:**
  - A drag of the popup's own title bar moves it and doesn't close it.
  - Resizes keep the window's current top-leading corner rather than re-anchoring to the button, then clamp to the screen's visible frame.
  - The close button calls `dismiss()`, which notifies Chromium as a user close.
- The window becomes key, as today. Arc's also becomes main, but Clair's doesn't need to: no menu acts on it.

### D7. `IsToolbarVisible()` returns true

The native window has a toolbar in Chromium's sense: the sidebar shows the location, navigation and extension controls. `IsToolbarShowing()` stays false, which keeps Chromium's toolbar-animation code paths off. `OpenPopupInBrowser` then reaches `ClairExtensions::ShowToolbarActionPopupForAPICall`, which already exists.

### D8. Store downloads stay out of the sidebar

The restored `WebstoreInstaller` downloads through the download manager with `DownloadSource::EXTENSION_INSTALLER`. `ClairDownloads` leaves those items out of its snapshot and Dock progress, as Chrome's download bubble does.

## Risks / Trade-offs

- **[Google sees installed extensions]** Update checks send each store extension's ID and version, the Chromium version and the platform to `clients2.google.com` every few hours. → This is the owner's choice. It's limited to profiles with store extensions; the Changie fragment says it; and `chromium-engine`'s idle-launch scenario still holds.
- **[The store changes its page]** Its button markup or eligibility check can change without notice, and the button would then say "Chrome" or a nag would return. → The scripts fail open: installs keep working. The runtime suite doesn't cover the store (it needs Google), so it's a by-hand check at each engine bump.
- **[The update server treats `chromiumcrx` differently]** Helium reports `prod=chromecrx` and a Windows platform to Google, for reasons not documented. → Check by hand that updates arrive with Chromium's own parameters. Spoof only if they don't, as a follow-up.
- **[Other code reaches the un-substituted store API]** `extension_urls.cc`'s `chromewebstore.googleapis.com` becomes real. It's used by `WebstoreDataFetcher` (standalone installs) and possibly the store info service (`cws_info_service`). This proposal hasn't checked whether either runs in ungoogled-chromium. → A task checks the network log of an install, an update check and an idle hour, and fixes any other request before shipping (spec scenario "Google contacted only for store extensions").
- **[An NSAlert can't show everything Chromium's dialog can]** Ratings, user counts, and expandable permission details flattened into lines. → Acceptable for Arc parity. Prompts that need input fall back to Chromium's dialog (D4).
- **[Sheets queue behind each other]** An install prompt over a JavaScript alert, or two prompts at once, wait their turn. → Rare, and Chromium allows only one install prompt per store tab anyway.
- **[Rebase cost]** The store restoration and the component hook touch files ungoogled-chromium and Chromium change. → No fuzz (`patch-no-fuzz.sh`), so the patch check names any hunk that stops applying at an engine bump.

## Migration Plan

Nothing to migrate.
- Extensions installed before this change have no update URL, or the substituted one, unless they set their own. A store extension installed from a CRX already carries `update_url: https://clients2.google.com/service/update2/crx` in its manifest, so it starts updating.
- Rolling back is a revert of the change. Installed extensions keep working; they just stop updating.

## Open Questions

- Whether the main-world eligibility script (D3) is needed at all with Clair's user agent. To be decided when the store page is checked with the isolated-world script alone.
