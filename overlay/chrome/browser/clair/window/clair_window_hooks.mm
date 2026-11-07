// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#include "chrome/browser/clair/window/clair_window_hooks.h"

#import <AppKit/AppKit.h>

#include <set>

#include "base/apple/foundation_util.h"
#include "base/files/file_path.h"
#include "base/no_destructor.h"
#include "base/values.h"
#include "chrome/app/chrome_command_ids.h"
#import "chrome/browser/clair/ClairHost.h"
#include "chrome/browser/clair/clair_native_layer.h"
#include "chrome/browser/clair/window/clair_browser_window.h"
#import "chrome/browser/clair/window/clair_native_window.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface_iterator.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/browser/ui/tabs/tab_enums.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model_delegate.h"
#include "components/autofill/core/common/autofill_prefs.h"
#include "components/download/public/common/download_item.h"
#include "components/password_manager/core/common/password_manager_pref_names.h"
#include "components/pref_registry/pref_registry_syncable.h"
#include "components/prefs/pref_service.h"
#include "content/public/browser/download_item_utils.h"
#include "content/public/browser/web_contents.h"
#include "ui/menus/simple_menu_model.h"
#include "url/gurl.h"

namespace {

// D17's prefs, all off.
constexpr const char* kOffPrefs[] = {
    password_manager::prefs::kCredentialsEnableService,
    password_manager::prefs::kCredentialsEnableAutosignin,
    autofill::prefs::kAutofillProfileEnabled,
    autofill::prefs::kAutofillCreditCardEnabled,
};

ClairBrowserWindow* KeyNativeWindow() {
  ClairNativeWindow* window =
      base::apple::ObjCCast<ClairNativeWindow>(NSApp.keyWindow);
  return window ? window.browserWindow : nullptr;
}

}  // namespace

// View > Hide Sidebar (D10): toggles the key native window's sidebar, and
// reads "Show Sidebar" while it's hidden.
@interface ClairSidebarMenuTarget : NSObject <NSMenuItemValidation>
@end

@implementation ClairSidebarMenuTarget

- (void)toggleSidebar:(id)sender {
  if (ClairBrowserWindow* window = KeyNativeWindow()) {
    [window->clair_window() toggleSidebar];
  }
}

- (BOOL)validateMenuItem:(NSMenuItem*)item {
  ClairBrowserWindow* window = KeyNativeWindow();
  id<ClairWindow> clair_window = window ? window->clair_window() : nil;
  item.title = clair_window.isSidebarHidden ? @"Show Sidebar" : @"Hide Sidebar";
  return clair_window != nil;
}

@end

namespace clair {

BrowserWindow* CreateNativeBrowserWindow(BrowserWindowInterface* browser) {
  if (!IsNativeLayerRunning() ||
      browser->GetType() != BrowserWindowInterface::Type::TYPE_NORMAL) {
    return nullptr;
  }
  // Browser is the only desktop BrowserWindowInterface.
  return new ClairBrowserWindow(static_cast<Browser*>(browser));
}

bool IsInNativeWindow(gfx::NativeView view) {
  NSView* ns_view = view.GetNativeNSView();
  return base::apple::ObjCCast<ClairNativeWindow>(ns_view.window) != nil;
}

void RemoveUnavailableContextMenuItems(ui::SimpleMenuModel* model) {
  for (size_t i = model->GetItemCount(); i > 0; --i) {
    switch (model->GetCommandIdAt(i - 1)) {
      case IDC_CONTENT_CONTEXT_OPENLINKSPLITVIEW:
      case IDC_CONTENT_CONTEXT_OPEN_IN_READING_MODE:
      case IDC_CONTENT_CONTEXT_LISTEN_TO_THIS_PAGE:
      case IDC_CONTENT_CONTEXT_GENERATE_QR_CODE:
      case IDC_SEND_TAB_TO_SELF:
      case IDC_CONTENT_CONTEXT_LENS_REGION_SEARCH:
      case IDC_CONTENT_CONTEXT_SEARCHLENSFORIMAGE:
      case IDC_CONTENT_CONTEXT_TRANSLATE:
      case IDC_CONTENT_CONTEXT_PARTIAL_TRANSLATE:
        model->RemoveItemAt(i - 1);
        break;
      default:
        break;
    }
  }
  for (size_t i = model->GetItemCount(); i > 0; --i) {
    const size_t index = i - 1;
    if (model->GetTypeAt(index) != ui::MenuModel::TYPE_SEPARATOR) {
      continue;
    }
    const bool at_end = index == 0 || index + 1 == model->GetItemCount();
    const bool doubled =
        index + 1 < model->GetItemCount() &&
        model->GetTypeAt(index + 1) == ui::MenuModel::TYPE_SEPARATOR;
    if (at_end || doubled) {
      model->RemoveItemAt(index);
    }
  }
}

bool IsNativeWindow(const BrowserWindowInterface* browser) {
  return browser && ClairBrowserWindow::FromBrowser(browser);
}

int NewTabIndex(const TabStripModel& model,
                int index,
                ui::PageTransition transition,
                int add_types) {
  TabStripModelDelegate* delegate = model.delegate();
  if (!delegate || !IsNativeWindow(delegate->GetBrowserWindowInterface())) {
    return -1;
  }
  const bool forced = add_types & AddTabTypes::ADD_FORCE_INDEX;
  const bool link = ui::PageTransitionTypeIncludingQualifiersIs(
      transition, ui::PAGE_TRANSITION_LINK);
  // A link without a forced position, or any tab with none, goes to the top.
  // Session restore and Reopen Closed Tab insert at their old positions and
  // don't come through here.
  if ((link && !forced) || index < 0) {
    return 0;
  }
  return -1;
}

bool UpdateDevTools(content::WebContents* inspected_contents) {
  ClairBrowserWindow* window =
      ClairBrowserWindow::FromWebContents(inspected_contents);
  if (!window) {
    return false;
  }
  if (window->browser()->tab_strip_model()->GetActiveWebContents() ==
      inspected_contents) {
    window->UpdateDevTools();
  }
  return true;
}

bool CanDockDevTools(content::WebContents* inspected_contents) {
  return ClairBrowserWindow::FromWebContents(inspected_contents) != nullptr;
}

gfx::Rect PageInfoAnchorRect(BrowserWindowInterface* browser) {
  ClairBrowserWindow* window = ClairBrowserWindow::FromBrowser(browser);
  return window ? window->SiteControlsAnchorInScreen() : gfx::Rect();
}

bool ShowToast(BrowserWindowInterface* browser, const std::u16string& text) {
  ClairBrowserWindow* window = ClairBrowserWindow::FromBrowser(browser);
  if (!window) {
    return false;
  }
  window->ShowToast(text);
  return true;
}

bool UpdateTargetURL(content::WebContents* source, const GURL& url) {
  ClairBrowserWindow* window = ClairBrowserWindow::FromWebContents(source);
  if (!window) {
    return false;
  }
  if (window->browser()->tab_strip_model()->GetActiveWebContents() == source) {
    window->SetStatusURL(url);
  }
  return true;
}

bool ContentsMouseEvent(content::WebContents* source, bool exited) {
  ClairBrowserWindow* window = ClairBrowserWindow::FromWebContents(source);
  if (!window) {
    return false;
  }
  if (exited) {
    window->SetStatusURL(GURL());
  }
  return true;
}

bool ShowNewDownload(download::DownloadItem* item) {
  BrowserWindowInterface* browser = nullptr;
  if (content::WebContents* contents =
          content::DownloadItemUtils::GetWebContents(item)) {
    browser = GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(contents);
  }
  if (!browser) {
    // A download without a tab belongs to the last active window of its
    // profile.
    Profile* profile = Profile::FromBrowserContext(
        content::DownloadItemUtils::GetBrowserContext(item));
    ForEachCurrentBrowserWindowInterfaceOrderedByActivation(
        [&](BrowserWindowInterface* candidate) {
          if (profile && candidate->GetProfile()->GetOriginalProfile() ==
                             profile->GetOriginalProfile()) {
            browser = candidate;
            return false;
          }
          return true;
        });
  }
  // The sidebar's downloads button shows it; Chromium's bubble doesn't.
  return IsNativeWindow(browser);
}

void RegisterProfilePrefOverrides(user_prefs::PrefRegistrySyncable* registry) {
  for (const char* pref : kOffPrefs) {
    registry->SetDefaultPrefValue(pref, base::Value(false));
  }
}

void ApplyPasswordAndAutofillOverrides(Profile* profile) {
  static base::NoDestructor<std::set<base::FilePath>> applied;
  Profile* original = profile->GetOriginalProfile();
  if (!applied->insert(original->GetPath()).second) {
    return;
  }
  PrefService* prefs = original->GetPrefs();
  for (const char* pref : kOffPrefs) {
    // A 0.1.x profile may have turned them on; follow the new default.
    if (prefs->HasPrefPath(pref)) {
      prefs->ClearPref(pref);
    }
  }
}

void InstallNativeWindowMenus() {
  NSMenu* main_menu = NSApp.mainMenu;
  // D10: no Bookmarks menu.
  [main_menu itemWithTag:IDC_BOOKMARKS_MENU].hidden = YES;

  // Hide the items of features the window doesn't host, and drop their key
  // equivalents, which a hidden item would still fire.
  NSMutableArray<NSMenu*>* menus = [NSMutableArray arrayWithObject:main_menu];
  NSMenuItem* save_page = nil;
  NSMenu* view_menu = [main_menu itemWithTag:IDC_VIEW_MENU].submenu;
  while (menus.count) {
    NSMenu* menu = menus.lastObject;
    [menus removeLastObject];
    for (NSMenuItem* item in menu.itemArray) {
      if (item.submenu) {
        [menus addObject:item.submenu];
      }
      if (ClairIsRemovedCommand(static_cast<int>(item.tag))) {
        item.hidden = YES;
        item.keyEquivalent = @"";
      }
      if (item.tag == IDC_SAVE_PAGE) {
        save_page = item;
      }
    }
  }

  // Save Page As… moves to Shift+Cmd+S, as in Arc, and Cmd+S hides the
  // sidebar.
  save_page.keyEquivalent = @"s";
  save_page.keyEquivalentModifierMask =
      NSEventModifierFlagCommand | NSEventModifierFlagShift;

  static ClairSidebarMenuTarget* target = [[ClairSidebarMenuTarget alloc] init];
  if (view_menu && ![view_menu itemWithTag:kClairHideSidebarTag]) {
    NSMenuItem* hide_sidebar =
        [[NSMenuItem alloc] initWithTitle:@"Hide Sidebar"
                                   action:@selector(toggleSidebar:)
                            keyEquivalent:@"s"];
    hide_sidebar.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    hide_sidebar.tag = kClairHideSidebarTag;
    hide_sidebar.target = target;
    [view_menu insertItem:hide_sidebar atIndex:0];
    [view_menu insertItem:[NSMenuItem separatorItem] atIndex:1];
  }
}

}  // namespace clair
