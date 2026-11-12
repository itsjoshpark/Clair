// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_WINDOW_CLAIR_WINDOW_HOOKS_H_
#define CHROME_BROWSER_CLAIR_WINDOW_CLAIR_WINDOW_HOOKS_H_

#include <memory>
#include <string>

#include "base/functional/callback_forward.h"
#include "extensions/browser/extension_install_prompt_client.h"
#include "ui/base/page_transition_types.h"
#include "ui/base/window_open_disposition.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/native_ui_types.h"

// The calls patches/clair/native-window-hook.patch adds to Chromium's own
// files (replace-browser-window design D13). Each does nothing for Chromium's
// own windows, so a bare engine, which has no ClairUI, behaves as Chromium.

class BrowserWindow;
class BrowserWindowInterface;
class ExtensionInstallPromptShowParams;
class PrefRegistrySimple;
class Profile;
class TabStripModel;

class GURL;

namespace content {
class NavigationHandle;
class WebContents;
struct OpenURLParams;
}  // namespace content

namespace download {
class DownloadItem;
}  // namespace download

namespace extensions {
class Extension;
class InstallPromptData;
}  // namespace extensions

namespace gfx {
class ImageSkia;
}  // namespace gfx

namespace ui {
class SimpleMenuModel;
}  // namespace ui

namespace user_prefs {
class PrefRegistrySyncable;
}  // namespace user_prefs

namespace clair {

// browser_window_factory.cc: the native window for a normal browser while
// ClairUI runs, or null for Chromium to build its own (D2).
BrowserWindow* CreateNativeBrowserWindow(BrowserWindowInterface* browser);

// Whether `browser` shows in a native window.
bool IsNativeWindow(const BrowserWindowInterface* browser);

// tab_strip_model.cc: where a native window puts a tab added without a
// position it must keep, which is the top of its sidebar (D12); or -1, to let
// Chromium decide. `index`, `transition` and `add_types` are AddTab's.
int NewTabIndex(const TabStripModel& model,
                int index,
                ui::PageTransition transition,
                int add_types);

// devtools_window(_views).cc: docks or undocks the inspected tab's DevTools in
// its native window's card (D5). False when the tab isn't in a native window.
bool UpdateDevTools(content::WebContents* inspected_contents);

// devtools_window.cc: whether the inspected tab's window can dock DevTools,
// which a native window can though it has no DevtoolsUIController.
bool CanDockDevTools(content::WebContents* inspected_contents);

// bubble_anchor_util_views.cc: where Chromium's bubbles attach in a native
// window, in screen coordinates: the site controls in the sidebar, or the
// card's top-leading corner (D7).
gfx::Rect PageInfoAnchorRect(BrowserWindowInterface* browser);

// toast_controller.cc: shows a toast's text in a native window (D8). False
// when `browser` isn't one.
bool ShowToast(BrowserWindowInterface* browser, const std::u16string& text);

// browser_web_contents_delegate.cc: the URL of the link under the pointer,
// and the pointer leaving the page, for a native window's status capsule
// (D8). Chromium's own status bubbles are Views; a native window has none.
// False when `source` isn't in a native window.
bool UpdateTargetURL(content::WebContents* source, const GURL& url);
bool ContentsMouseEvent(content::WebContents* source, bool exited);

// browser_web_contents_delegate.cc, at the start of OpenURLFromTab and
// AddNewContents: a link Shift+clicked in a native window's page opens in a
// Peek of its tab (add-peek D2), or, from a Peek, in a new tab at the top.
// False when that doesn't apply, and Chromium goes on: another window, another
// disposition than NEW_WINDOW, no user gesture or not from the page (the
// context menu), or the preference off. True when it handled the link, with
// `*result` the contents it opened or navigated, or null.
bool MaybeOpenPeek(BrowserWindowInterface* browser,
                   content::WebContents* source,
                   const content::OpenURLParams& params,
                   base::OnceCallback<void(content::NavigationHandle&)>&
                       navigation_handle_callback,
                   content::WebContents** result);
bool MaybeOpenPeek(BrowserWindowInterface* browser,
                   content::WebContents* source,
                   std::unique_ptr<content::WebContents>& new_contents,
                   const GURL& target_url,
                   WindowOpenDisposition disposition,
                   bool user_gesture,
                   content::WebContents** result);

// download_ui_controller.cc: hands a new download to the sidebar of the
// native window it belongs to (D7). False when it belongs to none, and
// Chromium shows its own download UI.
bool ShowNewDownload(download::DownloadItem* item);

// extension_install_dialog_view.cc: shows an install or permission prompt as
// a sheet on its native window (arc-extension-experience D4), and takes
// `done_callback` and `prompt`. False, leaving both, when the prompt's parent
// isn't a native window or the prompt needs input the sheet can't take.
bool ShowExtensionInstallPrompt(
    ExtensionInstallPromptShowParams* show_params,
    extensions::ExtensionInstallPromptClient::DoneCallback& done_callback,
    std::unique_ptr<extensions::InstallPromptData>& prompt);

// Destroying it dismisses the sheet if it's still showing, without answering.
class ExtensionPromptHandle {
 public:
  virtual ~ExtensionPromptHandle() = default;
};

// extension_uninstall_dialog_impl.cc: shows the remove confirmation as a sheet
// on its native window (D4). Null when `parent` isn't one. `answered` runs
// once, unless the handle is destroyed first.
std::unique_ptr<ExtensionPromptHandle> ShowExtensionRemovePrompt(
    gfx::NativeWindow parent,
    const extensions::Extension* extension,
    const gfx::ImageSkia& icon,
    base::OnceCallback<void(bool accepted)> answered);

// extension_install_ui_desktop.cc: pins a newly installed extension to a
// native window's sidebar (D5). False when `browser` isn't a native window,
// and Chromium shows its post-install box.
bool ExtensionInstalled(BrowserWindowInterface* browser,
                        const extensions::Extension* extension);

// browser_prefs.cc: Clair's profile defaults, set after Chromium registers its
// profile prefs: passwords and autofill are off (D17), and "On startup"
// continues where the user left off (add-spaces D11). They're defaults, not
// forced values: chrome://settings still changes them.
void RegisterProfilePrefOverrides(user_prefs::PrefRegistrySyncable* registry);

// browser_prefs.cc: Clair's own Local State prefs, which hold the Spaces
// (add-spaces D1).
void RegisterLocalStatePrefs(PrefRegistrySimple* registry);

// render_view_context_menu_mac_cocoa.mm: whether `view` is in a native
// window, where a page's context menu shows without a Views widget (D9).
bool IsInNativeWindow(gfx::NativeView view);

// render_view_context_menu_mac_cocoa.mm: removes the context menu items of
// D9's unavailable features (split view, reading mode, QR code, send tab to
// self, Lens, translate) and the separators that leaves doubled or at an end.
void RemoveUnavailableContextMenuItems(ui::SimpleMenuModel* model);

// Not a hook: called once ClairUI has started. Applies D10's menu changes:
// no Bookmarks menu, the unavailable features' items hidden, View > Hide
// Sidebar on Cmd+S and Save Page As on Shift+Cmd+S.
void InstallNativeWindowMenus();

// Not a hook: called by the overlay when the first native window of
// `profile` opens. Clears values the user set for D17's prefs before Clair
// turned them off, once per profile.
void ApplyPasswordAndAutofillOverrides(Profile* profile);

}  // namespace clair

#endif  // CHROME_BROWSER_CLAIR_WINDOW_CLAIR_WINDOW_HOOKS_H_
