// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#include "chrome/browser/clair/window/clair_peek_session.h"

#include <algorithm>

#include "chrome/browser/clair/window/clair_browser_window.h"
#include "chrome/browser/clair/window/clair_peeks.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/sessions/session_service.h"
#include "chrome/browser/sessions/session_service_factory.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "components/sessions/content/session_tab_helper.h"
#include "components/sessions/core/session_types.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/web_contents.h"

namespace clair {

namespace {

bool IsTagged(const sessions::SessionTab& tab) {
  auto it = tab.extra_data.find(kPeekSessionKey);
  return it != tab.extra_data.end() && it->second == "1";
}

}  // namespace

bool IsPeekTab(content::WebContents* contents) {
  ClairBrowserWindow* window =
      contents ? ClairBrowserWindow::FromWebContents(contents) : nullptr;
  return window && window->peeks() &&
         window->peeks()->ParentOf(contents) != nullptr;
}

void TagPeekInSession(BrowserWindowInterface* browser,
                      content::WebContents* contents,
                      bool is_peek) {
  if (!browser || !contents) {
    return;
  }
  SessionService* service =
      SessionServiceFactory::GetForProfileIfExisting(browser->GetProfile());
  if (!service) {
    return;
  }
  service->AddTabExtraData(browser->GetSessionID(),
                           sessions::SessionTabHelper::IdForTab(contents),
                           kPeekSessionKey, is_peek ? "1" : "0");
}

void AddPeekExtraData(tabs::TabInterface* tab,
                      std::map<std::string, std::string>* extra_data) {
  if (tab && extra_data && IsPeekTab(tab->GetContents())) {
    (*extra_data)[kPeekSessionKey] = "1";
  }
}

void DropPeeks(std::vector<std::unique_ptr<sessions::SessionWindow>>* windows) {
  if (!windows) {
    return;
  }
  for (std::unique_ptr<sessions::SessionWindow>& window : *windows) {
    std::vector<std::unique_ptr<sessions::SessionTab>> kept;
    int selected = window->selected_tab_index;
    int new_selected = -1;
    for (size_t i = 0; i < window->tabs.size(); ++i) {
      const bool drop = IsTagged(*window->tabs[i]);
      if (static_cast<int>(i) == selected) {
        // A Peek that was selected hands the selection to its parent, the
        // tab kept just before it.
        new_selected = drop ? std::max(0, static_cast<int>(kept.size()) - 1)
                            : static_cast<int>(kept.size());
      }
      if (!drop) {
        kept.push_back(std::move(window->tabs[i]));
      }
    }
    window->tabs = std::move(kept);
    window->selected_tab_index =
        window->tabs.empty() ? -1 : std::max(0, new_selected);
  }
  std::erase_if(*windows, [](const std::unique_ptr<sessions::SessionWindow>& w) {
    return w->tabs.empty();
  });
}

}  // namespace clair
