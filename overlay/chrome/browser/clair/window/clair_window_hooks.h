// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_WINDOW_CLAIR_WINDOW_HOOKS_H_
#define CHROME_BROWSER_CLAIR_WINDOW_CLAIR_WINDOW_HOOKS_H_

#include <string>

#include "ui/base/page_transition_types.h"
#include "ui/gfx/geometry/rect.h"

// The calls patches/clair/native-window-hook.patch adds to Chromium's own
// files (replace-browser-window design D13). Each does nothing for Chromium's
// own windows, so a bare engine, which has no ClairUI, behaves as Chromium.

class BrowserWindow;
class BrowserWindowInterface;
class Profile;
class TabStripModel;

class GURL;

namespace content {
class WebContents;
}  // namespace content

namespace download {
class DownloadItem;
}  // namespace download

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

// download_ui_controller.cc: hands a new download to the sidebar of the
// native window it belongs to (D7). False when it belongs to none, and
// Chromium shows its own download UI.
bool ShowNewDownload(download::DownloadItem* item);

// browser_prefs.cc: Clair's defaults for passwords and autofill, which are off
// (D17). Called after Chromium registers its profile prefs.
void RegisterProfilePrefOverrides(user_prefs::PrefRegistrySyncable* registry);

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
