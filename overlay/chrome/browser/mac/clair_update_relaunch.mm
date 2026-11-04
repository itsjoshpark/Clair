// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#include "chrome/browser/mac/clair_update_relaunch.h"

#import <Foundation/Foundation.h>

#include <string_view>

#include "base/logging.h"
#include "base/no_destructor.h"
#include "base/strings/strcat.h"
#include "base/strings/string_util.h"
#include "base/strings/sys_string_conversions.h"
#include "base/threading/platform_thread.h"
#include "base/time/time.h"

namespace clair {

namespace {

constexpr std::string_view kWaitArgumentPrefix =
    "--clair-wait-for-update-from-build=";
constexpr base::TimeDelta kWaitLimit = base::Minutes(1);
constexpr base::TimeDelta kPollInterval = base::Milliseconds(100);

// The build an update will replace, or empty if no update is waiting.
std::string& BuildBeingReplaced() {
  static base::NoDestructor<std::string> build;
  return *build;
}

// The bundle's build number, or empty while its Info.plist can't be read, as
// happens if the installer has to move the old app away first.
std::string BuildNumberOf(const std::string& app_bundle) {
  NSString* plist = [base::SysUTF8ToNSString(app_bundle)
      stringByAppendingPathComponent:@"Contents/Info.plist"];
  NSDictionary* info = [NSDictionary dictionaryWithContentsOfFile:plist];
  id build = info[@"CFBundleVersion"];
  return [build isKindOfClass:[NSString class]]
             ? base::SysNSStringToUTF8(build)
             : std::string();
}

}  // namespace

void NoteUpdateWillInstallOnQuit() {
  id build = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"];
  if (![build isKindOfClass:[NSString class]]) {
    LOG(ERROR) << "Clair: the running app has no build number";
    return;
  }
  BuildBeingReplaced() = base::SysNSStringToUTF8(build);
}

void AddUpdateRelauncherArgument(std::vector<std::string>& relauncher_args) {
  if (!BuildBeingReplaced().empty()) {
    relauncher_args.push_back(
        base::StrCat({kWaitArgumentPrefix, BuildBeingReplaced()}));
  }
}

void WaitForUpdateInstall(base::span<const char* const> args,
                          const std::string& app_bundle) {
  std::string old_build;
  for (const std::string arg : args) {
    if (base::StartsWith(arg, kWaitArgumentPrefix)) {
      old_build = arg.substr(kWaitArgumentPrefix.size());
      break;
    }
  }
  if (old_build.empty()) {
    return;
  }

  const base::TimeTicks deadline = base::TimeTicks::Now() + kWaitLimit;
  while (base::TimeTicks::Now() < deadline) {
    const std::string build = BuildNumberOf(app_bundle);
    if (!build.empty() && build != old_build) {
      return;
    }
    base::PlatformThread::Sleep(kPollInterval);
  }
  LOG(ERROR) << "Clair: the update didn't replace build " << old_build
             << "; reopening what's there";
}

}  // namespace clair
