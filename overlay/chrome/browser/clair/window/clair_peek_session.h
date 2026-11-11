// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_WINDOW_CLAIR_PEEK_SESSION_H_
#define CHROME_BROWSER_CLAIR_WINDOW_CLAIR_PEEK_SESSION_H_

#include <map>
#include <memory>
#include <string>
#include <vector>

class BrowserWindowInterface;

namespace content {
class WebContents;
}  // namespace content

namespace sessions {
struct SessionWindow;
}  // namespace sessions

namespace tabs {
class TabInterface;
}  // namespace tabs

// add-peek design D9: Peeks end with the session. Chromium saves them like any
// tab, tagged with this key, and session restore and Reopen Closed Window
// leave tagged tabs out (patches/clair/peek-session.patch). The key is
// spelled out again in components/sessions, which can't include this.
namespace clair {

inline constexpr char kPeekSessionKey[] = "clair_peek";

// Whether `contents` is a Peek, for the session file's rebuild.
bool IsPeekTab(content::WebContents* contents);

// Records in the session whether `contents`, a tab of `browser`, is a Peek:
// when it becomes one, and when it stops being one but stays a tab.
void TagPeekInSession(BrowserWindowInterface* browser,
                      content::WebContents* contents,
                      bool is_peek);

// Adds the tag to a tab's extra data for Reopen Closed Window.
void AddPeekExtraData(tabs::TabInterface* tab,
                      std::map<std::string, std::string>* extra_data);

// Removes the tagged tabs from the windows session restore is about to
// restore, keeping each window's selected tab on the parent of a removed
// one, and drops a window left without tabs.
void DropPeeks(std::vector<std::unique_ptr<sessions::SessionWindow>>* windows);

}  // namespace clair

#endif  // CHROME_BROWSER_CLAIR_WINDOW_CLAIR_PEEK_SESSION_H_
