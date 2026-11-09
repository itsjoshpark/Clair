# Tasks

Where a verification below needs a running app, it means a `quality.yml` run dispatched on the branch (`gh workflow run quality.yml --ref <branch>`) against the engine published for the branch's key. "By hand" means a check through `scripts/run-local.sh` with a throwaway profile; the owner runs the checks marked **(owner)**. Engine builds go through `engine.yml` as `CLAUDE.md` describes. Chromium's source can be read, never written, in the runner's workspace (`build/base` before Clair's layer).

Runtime tests cover the fundamentals only:
- the extension popup, as a window;
- `chrome.action.openPopup()`.

Store installs, updates, the confirmation sheets and the store's wording need Google's servers or Arc side by side, so they're checked by hand.

Suggested order: 1 and 2 (one engine build), then 3 and 4 in `ClairUI` (they can start against `FakeBrowser` during the build), then 5.

## 1. Restore the Web Store and updates

- [x] 1.1 Add `utils/domain_substitution_exclude.list` naming `extensions/common/extension_urls.cc`, `extensions/common/api/_api_features.json` and `extensions/browser/updater/safe_manifest_parser.cc`. Add `scripts/filter-domain-substitution.sh`, which writes ungoogled-chromium's list without them and stops with an error naming any listed file that isn't in ungoogled-chromium's list (D1). Call it from `build.sh`'s `apply_layer`, and add it to `scripts/engine-key.sh`'s inputs. Verify:
  - `scripts/filter-domain-substitution.test.sh` covers filtering and the missing-file error, and passes in CI;
  - after `./build.sh fetch prepare` in the patch check, `build/src` has `https://chromewebstore.google.com/` in both files, and `qjz9zk` hosts everywhere else.
- [x] 1.2 Add `patches/clair/restore-web-store.patch` (D2), each hunk headed with the upstream patch and hunk it reverts:
  - `ExtensionDownloader::DoStartAllPending`'s update checks;
  - `SanitizeUpdateURL`'s HTTPS rule (not its default update URL);
  - the store origins' dedicated process;
  - `WebstoreInstaller::DownloadCrx`, `StartCrxInstaller` and the `Webstore Downloads` folder.

  Add one hunk that isn't a revert, making `ExtensionUpdater::CanUseUpdateService` return false so store updates use the restored downloader.

  Verify that the patch check applies the series without fuzz.
- [x] 1.3 Add the store fixups component under `overlay/components/clair_store_fixups/` (D3): the manifest and an isolated-world script adapted from Helium's `extstore_fixups`, with its GPL-3.0 credit in `CREDITS.md`. Add `patches/clair/store-fixups-component.patch`, which registers it in `component_loader.cc`, the component allowlist, the component resource manager, `chrome_paks.gni`, `chrome/browser/extensions/BUILD.gn` and `resource_ids.spec`. Verify that the engine builds.
- [x] 1.4 Leave store-installer downloads (`DownloadSource::EXTENSION_INSTALLER`) out of `ClairDownloads`' snapshot and Dock progress (D8). Verify by hand that a store install adds nothing to the sidebar's downloads.

## 2. Contract and engine hooks

- [x] 2.1 Add `ClairExtensionPrompt`, `-[ClairWindow showExtensionPrompt:]`, `-[ClairWindow dismissExtensionPrompt:]` and `-[ClairBrowser answerExtensionPrompt:accepted:]` to `native/ClairHost.h` (D4), with `FakeBrowser` support for scripting prompts and recording answers. Verify that `ClairUI`'s build and unit tests pass in CI.
- [x] 2.2 In the overlay, implement the install and remove prompt bridge in `ClairExtensions`: prompts keyed by ID, the done callbacks with withheld permissions, cancel when the window closes, and dismiss on Chromium's `Close()` (D4). Add the hooks to `native-window-hook.patch`:
  - `ShowExtensionInstallDialogImpl`, falling back to Chromium's dialog for non-Clair parents and for prompts that need input;
  - `ExtensionUninstallDialogImpl::Show` and `Close()`;
  - `ExtensionInstallUIDesktop::OnInstallSuccess`, which pins instead of showing the post-install box (D5).

  Verify that `engine.yml` builds the engine for the branch's key.
- [x] 2.3 Pin newly installed extensions from `ClairExtensions` (D5), including when the action is added after `OnInstallSuccess`. Make `ClairBrowserWindow::IsToolbarVisible()` return true (D7). Verify with the runtime test in 4.2 and by hand: installing a CRX through "Always prompt for install" pins its button, and updating an unpinned extension leaves it unpinned.

- [ ] 2.4 Add `-[ClairBrowser contextMenuForExtension:]` to `native/ClairHost.h`, with `FakeBrowser` support, and build the menu in `ClairExtensions` (D9). Verify that `engine.yml` builds the engine for the branch's key.
- [ ] 2.5 Add `patches/clair/no-extension-uninstall-page.patch` (D10). Verify with 5.5.

## 3. Native confirmation sheets

- [x] 3.1 Add the sheets in `ClairUI` (D4):
  - an install alert with the extension's icon, "Add "<name>" to Clair?", "It can:" and its permissions, and Add Extension (default) / Cancel;
  - a remove alert with "Remove "<name>" from Clair?" and a destructive Remove Extension / Cancel;
  - other prompts with Chromium's strings;
  - one sheet at a time, and a cancel when the window closes.

  Add unit tests against `FakeBrowser` for each kind's text and buttons, for an install with no permissions (no "It can:"), for accept and cancel answering once with the prompt's ID, and for a dismissed prompt answering nothing. Verify that they pass in CI.

- [ ] 3.2 Show the menu on a right click or Control-click of a pinned button and of a row in the extensions list (D9). Verify with 5.5.

## 4. Popup window

- [x] 4.1 Make `ExtensionPopupWindow` a titled, closable window without miniaturize or resize, with the extension's name as its accessibility title and no corner mask (D6). It keeps its starting position, outside-click, Esc and anchor-click dismissal, and closes when the browser window moves. Dragging its title bar moves it without closing it, and growth keeps its top-leading corner. Update `testPinnedActionOpensItsPopup` to check that the popup window has an enabled close button, that clicking it closes the popup, and that the popup page is loaded. Verify that it passes in `quality.yml` on the branch.
- [x] 4.2 Add a runtime test using the `popup-badge` fixture: its background script calls `chrome.action.openPopup()`, and the popup window opens. Verify that it passes in `quality.yml` on the branch.

## 5. Verification and release notes

- [ ] 5.1 **(owner)** Check by hand against Arc, on the Reddit Image Opener store page and with uBlock Origin Lite:
  - the button reads "Add to Clair", and then "Remove from Clair", with no "Switch to Chrome" banner or popup;
  - the install sheet's text and permissions, Return to install, Esc to cancel;
  - no post-install box, and the new button pinned in the sidebar;
  - the remove sheet, with Remove Extension removing it and Esc keeping it;
  - the popup window's look, dragging it, Esc, outside click and the close button;
  - all of it in Light and Dark Mode.

  Note the results in the PR, and decide on the open question in design.md (the main-world script).
- [x] 5.2 By hand, with `--log-net-log`:
  - install a store extension;
  - force an update check from `chrome://extensions` (Developer mode, "Update");
  - leave Clair idle on a new tab for an hour.

  Verify that the only Google hosts contacted are the store page itself (by the user's navigation), `clients2.google.com` and its download redirect host. Turn off anything else that appears before shipping. Also verify that an older version of a store extension, installed from its CRX, updates to the store's version.
- [x] 5.3 Run `quality.yml` on the branch with the new engine. Verify that the whole runtime suite passes, including 4.1 and 4.2.
- [x] 5.4 Add a Changie fragment: Web Store installs and automatic updates (saying Clair now contacts Google for store extensions), native install and remove confirmations, auto-pinned new extensions, popups in a window, and the `chrome.action.openPopup()` fix. Verify that `changie batch --dry-run` renders it.
- [ ] 5.5 By hand: right-click a pinned button and a list row, and check Pin/Unpin, Options, Remove (through the sheet) and Manage, with no side panel or Inspect Popup item. Remove an extension that sets an uninstall URL, and check that no tab opens.

## Workflow follow-up

- Archive this change once it has merged and its quality checks pass.
