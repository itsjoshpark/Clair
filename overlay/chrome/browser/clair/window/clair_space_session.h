// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_WINDOW_CLAIR_SPACE_SESSION_H_
#define CHROME_BROWSER_CLAIR_WINDOW_CLAIR_SPACE_SESSION_H_

#include <map>
#include <string>

namespace content {
class WebContents;
}  // namespace content

namespace tabs {
class TabInterface;
}  // namespace tabs

// add-spaces design D6: each tab's Space and its index in the Space's list
// ride in the tab's session extra data. ClairSpaceTabs writes them through
// SessionService::AddTabExtraData when they change;
// patches/clair/space-session.patch writes them again in the session file's
// rebuild, adds them for Reopen Closed Tab and Window, and reads them back in
// CreateRestoredTab, before the restored tab joins a strip.
namespace clair {

inline constexpr char kSpaceSessionKey[] = "clair_space";
inline constexpr char kOrderSessionKey[] = "clair_order";

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

}  // namespace clair

#endif  // CHROME_BROWSER_CLAIR_WINDOW_CLAIR_SPACE_SESSION_H_
