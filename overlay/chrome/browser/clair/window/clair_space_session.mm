// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#include "chrome/browser/clair/window/clair_space_session.h"

#include <optional>

#include "base/strings/string_number_conversions.h"
#include "base/uuid.h"
#import "chrome/browser/clair/clair_space_tabs.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/web_contents.h"

namespace clair {

std::map<std::string, std::string> SpaceSessionData(
    content::WebContents* contents) {
  return ClairSpaceTabs::SessionTags(contents);
}

void AddSpaceExtraData(tabs::TabInterface* tab,
                       std::map<std::string, std::string>* extra_data) {
  if (!tab || !extra_data) {
    return;
  }
  for (const auto& [key, value] : ClairSpaceTabs::SessionTags(tab->GetContents())) {
    (*extra_data)[key] = value;
  }
}

void ReadSpaceExtraData(content::WebContents* contents,
                        const std::map<std::string, std::string>& extra_data) {
  auto space = extra_data.find(kSpaceSessionKey);
  // Only a Space's UUID: anything else is left to the window's Space (D2).
  if (!contents || space == extra_data.end() ||
      !base::Uuid::ParseLowercase(space->second).is_valid()) {
    return;
  }
  std::optional<int> rank;
  if (auto order = extra_data.find(kOrderSessionKey);
      order != extra_data.end()) {
    int value = 0;
    if (base::StringToInt(order->second, &value) && value >= 0) {
      rank = value;
    }
  }
  ClairSpaceTabs::SetRestoredTag(contents, space->second, rank);
}

}  // namespace clair
