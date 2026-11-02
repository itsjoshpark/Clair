// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#include "chrome/browser/clair/clair_native_layer.h"

#import <Foundation/Foundation.h>

#include "base/apple/bundle_locations.h"
#include "base/apple/foundation_util.h"
#include "base/check.h"
#include "base/files/file_path.h"
#include "base/logging.h"
#include "base/memory/scoped_refptr.h"
#include "base/strings/sys_string_conversions.h"
#import "chrome/browser/clair/ClairHost.h"
#include "chrome/browser/clair/ungoogled_version.h"
#include "chrome/browser/download/download_core_service.h"
#include "chrome/browser/lifetime/application_lifetime.h"
#include "chrome/browser/media/webrtc/media_capture_devices_dispatcher.h"
#include "chrome/browser/media/webrtc/media_stream_capture_indicator.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface_iterator.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "components/version_info/version_info.h"
#include "content/public/browser/web_contents.h"

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
  chrome::AttemptRelaunch();
}

@end

namespace clair {

namespace {

// The host ClairUI was started with, kept for the life of the process.
ClairChromiumHost* __strong g_host = nil;

}  // namespace

void StartNativeLayer() {
  CHECK([NSThread isMainThread]);
  if (g_host) {
    LOG(ERROR) << "ClairUI: already started";
    return;
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
    LOG(ERROR) << "ClairUI: could not load " << path << ": "
               << base::SysNSStringToUTF8(error.description)
               << "; running without the native layer";
    return;
  }
  Class principal = bundle.principalClass;
  if (!principal ||
      ![principal conformsToProtocol:@protocol(ClairUIEntryPoint)]) {
    LOG(ERROR) << "ClairUI: the principal class of " << path
               << " doesn't conform to ClairUIEntryPoint"
               << "; running without the native layer";
    return;
  }

  g_host = [[ClairChromiumHost alloc] init];
  [(Class<ClairUIEntryPoint>)principal startWithHost:g_host];
  LOG(INFO) << "ClairUI: started from " << path;
}

}  // namespace clair
