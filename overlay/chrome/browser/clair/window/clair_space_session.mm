// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#include "chrome/browser/clair/window/clair_space_session.h"

#include <algorithm>
#include <optional>

#include "base/strings/string_number_conversions.h"
#include "base/uuid.h"
#import "chrome/browser/clair/clair_space_tabs.h"
#include "chrome/common/webui_url_constants.h"
#include "components/sessions/core/session_types.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/web_contents.h"
#include "content/public/common/url_constants.h"
#include "url/gurl.h"

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
  // add-profiles D6: the window's group, a UUID.
  if (auto group = extra_data.find(kWindowSessionKey);
      contents && group != extra_data.end() &&
      base::Uuid::ParseLowercase(group->second).is_valid()) {
    ClairSpaceTabs::SetRestoredWindowTag(contents, group->second);
  }
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

namespace {

// Whether the tab's current page is the new tab page.
bool IsOnNewTabPage(const sessions::SessionTab& tab) {
  if (tab.navigations.empty()) {
    return false;
  }
  const int index = std::clamp(tab.current_navigation_index, 0,
                               static_cast<int>(tab.navigations.size()) - 1);
  const GURL& url = tab.navigations[index].virtual_url();
  return url.SchemeIs(content::kChromeUIScheme) &&
         (url.host() == chrome::kChromeUINewTabHost ||
          url.host() == chrome::kChromeUINewTabPageHost);
}

}  // namespace

void DropNewTabPages(
    std::vector<std::unique_ptr<sessions::SessionWindow>>* windows) {
  if (!windows) {
    return;
  }
  for (std::unique_ptr<sessions::SessionWindow>& window : *windows) {
    if (window->type != sessions::SessionWindow::TYPE_NORMAL) {
      continue;
    }
    std::vector<std::unique_ptr<sessions::SessionTab>> kept;
    const int selected = window->selected_tab_index;
    int new_selected = 0;
    for (size_t i = 0; i < window->tabs.size(); ++i) {
      const bool drop = IsOnNewTabPage(*window->tabs[i]);
      if (static_cast<int>(i) == selected && !drop) {
        new_selected = static_cast<int>(kept.size());
      }
      if (!drop) {
        kept.push_back(std::move(window->tabs[i]));
      }
    }
    // A window whose selected tab was a new tab page selects its first kept
    // one; with the restore setting on, the window opens a new tab page in
    // its Space again (ClairWindowGroup).
    window->tabs = std::move(kept);
    window->selected_tab_index = window->tabs.empty() ? -1 : new_selected;
  }
  std::erase_if(*windows, [](const std::unique_ptr<sessions::SessionWindow>& w) {
    return w->type == sessions::SessionWindow::TYPE_NORMAL && w->tabs.empty();
  });
}

}  // namespace clair
