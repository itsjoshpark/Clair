# Proposal

## Why

Arc users install and update extensions from the Chrome Web Store without thinking about it. In Clair they can't. ungoogled-chromium rewrites the store's addresses, removes the store installer's download and turns off extension update checks, so the store's "Add to Chrome" button stays disabled and installed extensions never update. The extension UI around that is also broken or un-Arc-like:

- Chromium's "extension has been added" box falls back to a modal with no buttons, which only Esc closes.
- Install and remove prompts don't look like Arc's.
- The popup is a borderless panel whose rounded corners clip the page.
- `chrome.action.openPopup()` fails with "Browser window has no toolbar".

Arc stops working on 2026-12-22, and extensions are part of what people bring with them.

## What Changes

- **Web Store installs restored.** Clair recognises `chromewebstore.google.com` as the store, gives it its install API again, and downloads the extension from Google when the user installs. Domain substitution leaves out the two files that name the store. A Clair patch restores the store installer's download, which ungoogled-chromium removed.
- **Extension auto-updates restored.** Clair checks Google's extension update server for installed extensions and updates them, as Chrome and Arc do. **BREAKING (privacy baseline):** Clair now contacts Google for extension installs and update checks, and sends the installed extensions' IDs and versions with each check. Until now, Clair has kept ungoogled-chromium's promise not to re-enable Google services. A profile with no store extensions still makes no such requests.
- **"Add to Clair" / "Remove from Clair".** A built-in component extension, adapted from Helium's `extstore_fixups`, renames the store's install button and removes the store's "Switch to Chrome" prompts.
- **Native install and remove confirmations.** Chromium's install prompt and uninstall dialog become sheets on the window (`NSAlert`):
  - **Install:** "Add "<name>" to Clair?" with an "It can:" list of permissions, and Add Extension / Cancel buttons.
  - **Remove:** "Remove "<name>" from Clair?" with a destructive Remove Extension / Cancel. There's no "report abuse" checkbox.
  - **Other install prompts** (re-enabling after an update that asks for new permissions, an extension's optional permission request) use the same sheet, with Chromium's own text.
- **No "extension has been added" box.** A newly installed extension is pinned to the sidebar instead, as Arc does.
- **Popups in a window.** An extension's popup becomes a small titled window with only a close button. It can be dragged by its title bar and still opens beside the button that opened it. A click outside it or Esc closes it, as Arc's does, and its page is no longer clipped by rounded corners.
- **Right-click menus.** Right-clicking a pinned extension or a row in the extensions list shows Chromium's extension menu natively, including Options, Pin/Unpin and Remove.
- **No uninstall pages.** Removing an extension doesn't open the page it set with `chrome.runtime.setUninstallURL`.
- **`chrome.action.openPopup()` works.** The native window reports a visible toolbar, so the API opens the popup through the sidebar.

**Out of scope:**
- Arc's custom-drawn dialog panel; the system alert replaces it.
- A Clair proxy for extension downloads, as Helium has.
- Content verification of store extensions, which ungoogled-chromium turns off and Clair leaves off.
- Other extension dialogs that still use Chromium's modal fallback (`ShowDialog` with no Views extensions container).

## Capabilities

### New Capabilities

- `extensions`: how extensions are installed, updated, confirmed, pinned and shown, including the Web Store, auto-updates, native install and remove confirmations, auto-pinning, popups in a window, and the extension action API.

### Modified Capabilities

- `chromium-engine`:
  - Its baseline now allows two exceptions: the Web Store and extension updates, and domain substitution that leaves out the store's files.
  - Patches may restore the store installer and update checks that ungoogled-chromium removed.
  - "Extension installation as in ungoogled-chromium" moves to `extensions`.
- `sidebar`: "Extension actions" opens the popup in a window beside the button, instead of attached to it.
- `browser-window`: extension popups and install prompts leave the list of bubbles attached to the sidebar.
- `native-layer`: the contract also covers extension install and remove confirmations.

## Impact

- **Engine:**
  - `build.sh` gains a short list of files left out of domain substitution: `extensions/common/extension_urls.cc` and `extensions/common/api/_api_features.json`.
  - A new patch, `patches/clair/restore-web-store.patch`, partly reverts ungoogled-chromium's `disable-webstore-urls.patch` and the store installer hunks of inox's `0005-disable-default-extensions.patch`.
  - A component extension is added under `overlay/`, with a small registration hook.
  - The extension hooks join `native-window-hook.patch`: the install prompt, the uninstall dialog, the post-install box, and `IsToolbarVisible()`.
  - The engine key changes, so `engine.yml` builds one new engine.
- **Contract:** `native/ClairHost.h` gains two confirmation requests, install and remove, and a call for an extension's context menu.
- **Native layer:** the confirmation sheets and the titled popup window, in `native/ClairUI/`, with unit tests for the sheets' content against `FakeBrowser`.
- **Tests:**
  - The existing runtime popup test is updated for the window.
  - One runtime test is added for `chrome.action.openPopup()`.
  - Store installs, updates and the sheets are checked by hand against Arc, since they need Google's servers.
- **Users:** a Changie fragment, which says that Clair now contacts Google for store installs and extension updates.
- **Credits:** `CREDITS.md` names Helium (GPL-3.0) for the component extension and the store fixes.
