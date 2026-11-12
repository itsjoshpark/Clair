// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#include "chrome/browser/clair/clair_native_layer.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <climits>
#include <string>

#include "base/apple/bundle_locations.h"
#include "base/apple/foundation_util.h"
#include "base/check.h"
#include "base/files/file_path.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/memory/scoped_refptr.h"
#include "base/process/process.h"
#include "base/strings/sys_string_conversions.h"
#include "base/time/time.h"
#import "chrome/browser/app_controller_mac.h"
#import "chrome/browser/clair/ClairHost.h"
#include "chrome/browser/clair/clair_space_store.h"
#import "chrome/browser/clair/clair_space_tabs.h"
#include "chrome/browser/clair/ungoogled_version.h"
#include "chrome/browser/clair/window/clair_window_hooks.h"
#include "chrome/browser/download/download_core_service.h"
#include "chrome/browser/lifetime/application_lifetime.h"
#include "chrome/browser/lifetime/browser_shutdown.h"
#include "chrome/browser/mac/clair_update_relaunch.h"
#include "chrome/browser/media/webrtc/media_capture_devices_dispatcher.h"
#include "chrome/browser/media/webrtc/media_stream_capture_indicator.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface_iterator.h"
#include "chrome/browser/ui/navigator/browser_navigator.h"
#include "chrome/browser/ui/navigator/browser_navigator_params.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "components/tabs/public/tab_interface.h"
#include "components/version_info/version_info.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/page_transition_types.h"
#include "ui/base/window_open_disposition.h"
#include "url/gurl.h"

namespace {

// Set in the user defaults by a relaunch from the background, for the process
// that replaces it.
NSString* const kRelaunchedInBackgroundKey = @"ClairRelaunchedInBackground";

// Opens `url` in a new foreground tab of `profile`'s most recently active
// tabbed window. With no browser to hold the tab, Navigate creates a window.
void OpenURLInProfile(const GURL& url, Profile* profile) {
  if (!profile) {
    LOG(ERROR) << "ClairUI: no profile to open " << url.possibly_invalid_spec()
               << " in";
    return;
  }
  NavigateParams params(profile, url, ui::PAGE_TRANSITION_AUTO_BOOKMARK);
  params.disposition = WindowOpenDisposition::NEW_FOREGROUND_TAB;
  params.window_action = NavigateParams::WindowAction::kShowWindow;
  Navigate(&params);
}

}  // namespace

// Chromium's side of the contract: what ClairUI may ask of the browser.
@interface ClairChromiumHost : NSObject <ClairHost>
@end

@implementation ClairChromiumHost

- (NSString*)chromiumVersion {
  return base::SysUTF8ToNSString(version_info::GetVersionNumber());
}

- (NSString*)ungoogledChromiumVersion {
  return @CLAIR_UNGOOGLED_CHROMIUM_VERSION;
}

- (ClairRelaunchBlockers)silentRelaunchBlockers {
  CHECK([NSThread isMainThread]);
  ClairRelaunchBlockers blockers = ClairRelaunchBlockersNone;
  if (DownloadCoreService::BlockingShutdownCountAllProfiles() > 0) {
    blockers |= ClairRelaunchBlockersDownloadInProgress;
  }
  scoped_refptr<MediaStreamCaptureIndicator> capture =
      MediaCaptureDevicesDispatcher::GetInstance()
          ->GetMediaStreamCaptureIndicator();
  ForEachCurrentBrowserWindowInterfaceOrderedByActivation(
      [&](BrowserWindowInterface* browser) {
        // Incognito and guest windows don't come back after a relaunch.
        if (browser->GetProfile()->IsOffTheRecord()) {
          blockers |= ClairRelaunchBlockersIncognitoWindow;
        }
        TabStripModel* tabs = browser->GetTabStripModel();
        for (int i = 0; i < tabs->count(); ++i) {
          content::WebContents* contents = tabs->GetWebContentsAt(i);
          if (contents->IsCurrentlyAudible()) {
            blockers |= ClairRelaunchBlockersAudibleTab;
          }
          if (capture && (capture->IsCapturingUserMedia(contents) ||
                          capture->IsBeingMirrored(contents) ||
                          capture->IsCapturingTab(contents) ||
                          capture->IsCapturingWindow(contents) ||
                          capture->IsCapturingDisplay(contents))) {
            blockers |= ClairRelaunchBlockersCapturingTab;
          }
        }
        return true;
      });
  return blockers;
}

- (void)relaunch {
  CHECK([NSThread isMainThread]);
  // Chromium's own relaunch: it restores the session, and its quit flow still
  // asks about downloads in progress.
  NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
  if (!NSApp.active) {
    [defaults setBool:YES forKey:kRelaunchedInBackgroundKey];
  }
  chrome::AttemptRelaunch();
  // The quit flow asks about downloads in a nested run loop, so by now the user
  // may have said no. Chromium would keep the relaunch requested, and the next
  // plain quit would reopen Clair.
  if (!browser_shutdown::IsTryingToQuit()) {
    browser_shutdown::SetTryingToQuit(false);
    [defaults removeObjectForKey:kRelaunchedInBackgroundKey];
  }
}

- (void)updateWillInstallOnQuit {
  CHECK([NSThread isMainThread]);
  clair::NoteUpdateWillInstallOnQuit();
}

- (void)openURL:(NSURL*)url {
  CHECK([NSThread isMainThread]);
  GURL gurl(base::SysNSStringToUTF8(url.absoluteString));
  if (!gurl.is_valid()) {
    LOG(ERROR) << "ClairUI: not opening an invalid URL";
    return;
  }
  // The same profile Chromium's own menu commands use, loaded if it isn't yet.
  app_controller_mac::RunInLastProfileSafely(
      base::BindOnce(&OpenURLInProfile, gurl),
      app_controller_mac::kShowProfilePickerOnFailure);
}

// --- Spaces (add-spaces design D1, D2, D7, D9) ---

- (NSArray<id<ClairSpace>>*)spaces {
  CHECK([NSThread isMainThread]);
  return clair::SpaceSnapshots();
}

- (NSArray<id<ClairTab>>*)tabsInSpace:(ClairSpaceID)spaceID {
  CHECK([NSThread isMainThread]);
  return spaceID ? clair::TabsInSpace(base::SysNSStringToUTF8(spaceID)) : @[];
}

- (void)addObserver:(id<ClairSpacesObserver>)observer {
  CHECK([NSThread isMainThread]);
  if (observer) {
    clair::AddSpacesObserver(observer);
  }
}

- (ClairSpaceID)createSpaceNamed:(NSString*)name icon:(NSString*)icon {
  CHECK([NSThread isMainThread]);
  const std::string id = clair::ClairSpaceStore::Get()->Create(
      base::SysNSStringToUTF8(name ?: @""), base::SysNSStringToUTF8(icon ?: @""));
  return id.empty() ? nil : base::SysUTF8ToNSString(id);
}

- (void)renameSpace:(ClairSpaceID)spaceID to:(NSString*)name {
  CHECK([NSThread isMainThread]);
  clair::ClairSpaceStore::Get()->Rename(base::SysNSStringToUTF8(spaceID ?: @""),
                                        base::SysNSStringToUTF8(name ?: @""));
}

- (void)setIcon:(NSString*)icon forSpace:(ClairSpaceID)spaceID {
  CHECK([NSThread isMainThread]);
  clair::ClairSpaceStore::Get()->SetIcon(base::SysNSStringToUTF8(spaceID ?: @""),
                                         base::SysNSStringToUTF8(icon ?: @""));
}

- (void)moveSpace:(ClairSpaceID)spaceID toIndex:(NSInteger)index {
  CHECK([NSThread isMainThread]);
  clair::ClairSpaceStore::Get()->Move(
      base::SysNSStringToUTF8(spaceID ?: @""),
      static_cast<int>(std::clamp<NSInteger>(index, 0, INT_MAX)));
}

- (void)deleteSpace:(ClairSpaceID)spaceID {
  CHECK([NSThread isMainThread]);
  clair::DeleteSpace(base::SysNSStringToUTF8(spaceID ?: @""));
}

- (void)moveTab:(ClairTabID)tabID toSpace:(ClairSpaceID)spaceID {
  CHECK([NSThread isMainThread]);
  if (tabID == ClairTabIDNone || !spaceID) {
    return;
  }
  tabs::TabInterface* tab = tabs::TabHandle(static_cast<int32_t>(tabID)).Get();
  clair::MoveTabToSpace(tab, base::SysNSStringToUTF8(spaceID));
}

@end

namespace clair {

namespace {

// The host ClairUI was started with, kept for the life of the process.
ClairChromiumHost* __strong g_host = nil;

// ClairUI's entry point, once started.
Class<ClairUIEntryPoint> g_entry_point = nil;

// D2: a ClairUI.framework that is present but doesn't load leaves Clair
// without its interface. Say so and quit before any browser window opens,
// rather than fall back to Chromium's window.
[[noreturn]] void FailToStart(const std::string& reason) {
  LOG(ERROR) << "ClairUI: " << reason << "; quitting";
  NSAlert* alert = [[NSAlert alloc] init];
  alert.alertStyle = NSAlertStyleCritical;
  alert.messageText = @"Clair couldn’t start its interface.";
  alert.informativeText =
      @"Clair can’t open windows without it. Download Clair again from "
      @"github.com/itsjoshpark/Clair to fix it.";
  [alert addButtonWithTitle:@"Quit"];
  [NSApp activateIgnoringOtherApps:YES];
  [alert runModal];
  base::Process::TerminateCurrentProcessImmediately(1);
}

// When to stop keeping a background relaunch in the background. Null otherwise.
base::TimeTicks g_stay_in_background_until;

}  // namespace

bool IsNativeLayerRunning() {
  return g_entry_point != nil;
}

id<ClairWindow> CreateClairWindow(id<ClairBrowser> browser) {
  CHECK([NSThread isMainThread]);
  CHECK(g_entry_point);
  return [g_entry_point windowForBrowser:browser];
}

bool ShouldStayInBackground() {
  if (g_stay_in_background_until.is_null()) {
    return false;
  }
  if (NSApp.active || base::TimeTicks::Now() >= g_stay_in_background_until) {
    g_stay_in_background_until = base::TimeTicks();
    return false;
  }
  return true;
}

void StartNativeLayer() {
  CHECK([NSThread isMainThread]);
  if (g_host) {
    LOG(ERROR) << "ClairUI: already started";
    return;
  }

  NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
  if ([defaults boolForKey:kRelaunchedInBackgroundKey]) {
    [defaults removeObjectForKey:kRelaunchedInBackgroundKey];
    g_stay_in_background_until = base::TimeTicks::Now() + base::Minutes(1);
  }

  const base::FilePath path = base::apple::OuterBundlePath()
                                  .Append("Contents")
                                  .Append("Frameworks")
                                  .Append("ClairUI.framework");
  NSBundle* bundle =
      [NSBundle bundleWithPath:base::apple::FilePathToNSString(path)];
  if (!bundle) {
    LOG(WARNING) << "ClairUI: no framework at " << path
                 << "; running without the native layer";
    return;
  }
  NSError* error = nil;
  if (![bundle loadAndReturnError:&error]) {
    FailToStart("could not load " + path.value() + ": " +
                base::SysNSStringToUTF8(error.description));
  }
  Class principal = bundle.principalClass;
  if (!principal ||
      ![principal conformsToProtocol:@protocol(ClairUIEntryPoint)] ||
      ![principal respondsToSelector:@selector(windowForBrowser:)]) {
    FailToStart("the principal class of " + path.value() +
                " doesn't conform to ClairUIEntryPoint");
  }

  g_host = [[ClairChromiumHost alloc] init];
  g_entry_point = (Class<ClairUIEntryPoint>)principal;
  [g_entry_point startWithHost:g_host];
  clair::InstallNativeWindowMenus();
  LOG(INFO) << "ClairUI: started from " << path;
}

}  // namespace clair
