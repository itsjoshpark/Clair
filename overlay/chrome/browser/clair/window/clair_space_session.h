// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_WINDOW_CLAIR_SPACE_SESSION_H_
#define CHROME_BROWSER_CLAIR_WINDOW_CLAIR_SPACE_SESSION_H_

#include <map>
#include <memory>
#include <string>
#include <vector>

namespace content {
class WebContents;
}  // namespace content

namespace sessions {
struct SessionWindow;
}  // namespace sessions

namespace tabs {
class TabInterface;
}  // namespace tabs

// add-spaces design D6: each tab's Space and its index in the Space's list
// ride in the tab's session extra data, and add-profiles design D6 adds its
// window's group. ClairSpaceTabs writes them through
// SessionService::AddTabExtraData when they change;
// patches/clair/space-session.patch writes them again in the session file's
// rebuild, adds them for Reopen Closed Tab and Window, and reads them back in
// CreateRestoredTab, before the restored tab joins a strip.
namespace clair {

inline constexpr char kSpaceSessionKey[] = "clair_space";
inline constexpr char kOrderSessionKey[] = "clair_order";
// add-profiles D6: the UUID of the window group the tab's window belongs to.
inline constexpr char kWindowSessionKey[] = "clair_window";

// session_service_base.cc, in the rebuild: the tags to write for `contents`.
std::map<std::string, std::string> SpaceSessionData(
    content::WebContents* contents);

// browser_live_tab_context.cc: adds the tags of `tab` to its extra data for
// Reopen Closed Tab and Window.
void AddSpaceExtraData(tabs::TabInterface* tab,
                       std::map<std::string, std::string>* extra_data);

// browser_tabrestore.cc, in CreateRestoredTab: reads the tags onto the
// restored `contents`.
void ReadSpaceExtraData(content::WebContents* contents,
                        const std::map<std::string, std::string>& extra_data);

// session_restore.cc, beside DropPeeks: drops the tabs on the new tab page and
// the windows left without tabs, so the new tab page a launch opens is the
// only one (add-profiles design D6).
void DropNewTabPages(
    std::vector<std::unique_ptr<sessions::SessionWindow>>* windows);

}  // namespace clair

#endif  // CHROME_BROWSER_CLAIR_WINDOW_CLAIR_SPACE_SESSION_H_
