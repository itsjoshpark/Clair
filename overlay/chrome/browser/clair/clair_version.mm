// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#include "chrome/browser/clair/clair_version.h"

#import <Foundation/Foundation.h>

#include <string_view>

#include "base/apple/bundle_locations.h"
#include "base/apple/foundation_util.h"
#include "base/strings/strcat.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/clair/ungoogled_version.h"
#include "components/version_info/version_info.h"

namespace clair {

namespace {

std::string InfoPlistString(NSString* key) {
  return base::SysNSStringToUTF8(base::apple::ObjCCast<NSString>(
      [base::apple::OuterBundle() objectForInfoDictionaryKey:key]));
}

}  // namespace

std::string GetVersionString() {
  return base::StrCat({InfoPlistString(@"CFBundleShortVersionString"), " (",
                       InfoPlistString(@"CFBundleVersion"), ")"});
}

std::string GetEngineVersionString() {
  return base::StrCat({"Chromium ", version_info::GetVersionNumber(),
                       " (ungoogled-chromium ",
                       CLAIR_UNGOOGLED_CHROMIUM_VERSION, ")"});
}

}  // namespace clair
