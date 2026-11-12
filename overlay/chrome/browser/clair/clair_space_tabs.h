// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_CLAIR_SPACE_TABS_H_
#define CHROME_BROWSER_CLAIR_CLAIR_SPACE_TABS_H_

#import <Foundation/Foundation.h>

#include <map>
#include <memory>
#include <optional>
#include <set>
#include <string>
#include <vector>

#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/scoped_multi_source_observation.h"
#include "base/supports_user_data.h"
#include "chrome/browser/clair/clair_space_store.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "components/infobars/core/infobar_manager.h"
#include "components/tabs/public/tab_interface.h"

#if !defined(__OBJC__)
#error "clair_space_tabs.h returns Objective-C snapshots; include it from .mm files"
#endif

#import "chrome/browser/clair/ClairHost.h"

class Browser;
class ClairBrowserWindow;
class Profile;
class TabStripModel;

namespace content {
class WebContents;
}  // namespace content

// add-spaces design D2: one per profile. It observes the tab strip of every
// native window of the profile and keeps, for each Space, an ordered list of
// tab handles across all of them. The order is Clair's: the tab strip's order
// no longer means anything to the user, except that a Peek directly follows
// its parent. Each tab carries its Space as WebContents user data, which
// moves with it between windows and comes back with it from a session.
//
// It also owns what ClairUI hears about tabs (D9): their snapshots, and the
// Space lists and tab changes it pushes to the host's ClairSpacesObserver,
// coalesced to once per run-loop turn per Space and per tab.
//
// An off-the-record profile (incognito, guest) has no Spaces: all its tabs
// belong to one Space of its own, which isn't in ClairSpaceStore.
class ClairSpaceTabs : public base::SupportsUserData::Data,
                       public TabStripModelObserver,
                       public infobars::InfoBarManager::Observer {
 public:
  // The lists of `profile`'s tabs, created on first use.
  static ClairSpaceTabs* ForProfile(Profile* profile);
  // The lists holding `contents`, or null.
  static ClairSpaceTabs* ForWebContents(content::WebContents* contents);
  // Every profile's lists.
  static std::vector<ClairSpaceTabs*> All();
  // Pushes every profile's pending changes now, before a window hears that
  // its active tab changed (D9).
  static void FlushAll();

  // D6: a restored tab's Space and its place in the Space's list, read from
  // the session before the tab joins a strip.
  static void SetRestoredTag(content::WebContents* contents,
                             const std::string& space,
                             std::optional<int> rank);
  // The tags session restore and Reopen Closed Tab need to put `contents`
  // back: its Space and its index in the Space's list. Empty for a tab with
  // no Space, as an incognito one.
  static std::map<std::string, std::string> SessionTags(
      content::WebContents* contents);

  explicit ClairSpaceTabs(Profile* profile);
  ClairSpaceTabs(const ClairSpaceTabs&) = delete;
  ClairSpaceTabs& operator=(const ClairSpaceTabs&) = delete;
  ~ClairSpaceTabs() override;

  Profile* profile() const { return profile_; }
  // Whether the profile's tabs belong to the user's Spaces.
  bool is_regular() const { return private_space_.empty(); }
  // An off-the-record profile's own Space; empty for a regular profile.
  const std::string& private_space() const { return private_space_; }

  // A native window of the profile opened or is closing.
  void AddBrowser(ClairBrowserWindow* window);
  void RemoveBrowser(ClairBrowserWindow* window);

  // The Space `contents` belongs to, or empty while it isn't listed.
  std::string SpaceOf(content::WebContents* contents) const;
  std::string SpaceOf(const tabs::TabInterface* tab) const;
  // The Space `tab` belongs to, or will once it's listed: a tab restored from
  // a session or moved from another window carries its Space before the
  // lists hear of it, and Chromium may make it active first. Empty for a new
  // tab, which joins the Space its window shows.
  std::string IntendedSpaceOf(tabs::TabInterface* tab) const;
  // A Space's tabs in its order, Peeks included; with `browser`, only those
  // the browser holds.
  std::vector<tabs::TabInterface*> TabsIn(const std::string& space) const;
  std::vector<tabs::TabInterface*> TabsIn(const std::string& space,
                                          const Browser* browser) const;
  // The Spaces that have tabs here, in no particular order.
  std::vector<std::string> SpacesWithTabs() const;

  // A tab's snapshot for ClairUI.
  id<ClairTab> Snapshot(content::WebContents* contents) const;
  NSArray<id<ClairTab>>* Snapshots(const std::string& space) const;

  // D2: moves `tab`, with its Peek, to `index` in its Space's list: the tab
  // ends at `index` and its Peek right after it. Touches no strip.
  void MoveTab(tabs::TabInterface* tab, int index);
  // D5: moves `tab`, with its Peek, to right after `anchor` and its Peek, or
  // to right before `anchor`. Both are rows of the same Space.
  void MoveTabBeside(tabs::TabInterface* tab,
                     tabs::TabInterface* anchor,
                     bool after);
  // D7: moves `tab`, with its Peek, to the top of `space`'s list.
  void SetSpace(tabs::TabInterface* tab, const std::string& space);
  // add-peek: `peek`, right after `parent` in the strip, became its Peek; it
  // joins the parent's Space, right after it.
  void PeekLinked(tabs::TabInterface* parent, tabs::TabInterface* peek);
  // D7: `space` was deleted; any tab still in it, as one whose leave-page
  // confirmation is up, joins `fallback`.
  void SpaceRemoved(const std::string& space, const std::string& fallback);

  // What to push at the end of this run-loop turn.
  void ListChanged(const std::string& space);
  void TabChanged(content::WebContents* contents);
  // Pushes now.
  void Flush();

  // TabStripModelObserver:
  void OnTabStripModelChanged(TabStripModel* model,
                              const TabStripModelChange& change,
                              const TabStripSelectionChange& selection) override;
  void OnTabChangedAt(tabs::TabInterface* tab,
                      TabChangeType change_type) override;
  void OnTabStripModelDestroyed(TabStripModel* model) override;

  // infobars::InfoBarManager::Observer:
  void OnInfoBarAdded(infobars::InfoBar* infobar) override;
  void OnInfoBarRemoved(infobars::InfoBar* infobar, bool animate) override;
  void OnInfoBarReplaced(infobars::InfoBar* old_infobar,
                         infobars::InfoBar* new_infobar) override;
  void OnManagerWillBeDestroyed(infobars::InfoBarManager* manager) override;

 private:
  class ProgressObserver;

  // Lists `tab`, just inserted at `index` in `model`, by D2's rules.
  void Insert(TabStripModel* model, tabs::TabInterface* tab, int index);
  // Takes `tab` out of its list; returns its Space, or empty.
  std::string Remove(const tabs::TabInterface* tab);
  // `tab` and its Peek, if it has one in the same window.
  std::vector<tabs::TabInterface*> FamilyOf(tabs::TabInterface* tab) const;
  // Takes `tab`'s family out of `list` and returns its handles, in order.
  std::vector<tabs::TabHandle> TakeFamily(std::vector<tabs::TabHandle>& list,
                                          tabs::TabInterface* tab) const;
  // The window holding `model`, or null.
  ClairBrowserWindow* WindowFor(const TabStripModel* model) const;

  // Watches a tab's infobars and load progress.
  void Watch(content::WebContents* contents);
  void Unwatch(content::WebContents* contents);
  void InfobarChanged(infobars::InfoBar* infobar);

  // D6: records each tab's Space and index in the session where they changed.
  void WriteSessionTags(const std::string& space);
  void PostFlush();

  const raw_ptr<Profile> profile_;
  std::string private_space_;
  std::map<std::string, std::vector<tabs::TabHandle>> lists_;
  std::vector<raw_ptr<ClairBrowserWindow>> windows_;
  std::set<std::string> changed_spaces_;
  std::set<int32_t> changed_tabs_;
  bool flush_posted_ = false;
  base::ScopedMultiSourceObservation<infobars::InfoBarManager,
                                     infobars::InfoBarManager::Observer>
      infobar_observations_{this};
  std::vector<std::unique_ptr<ProgressObserver>> progress_observers_;
  base::WeakPtrFactory<ClairSpaceTabs> weak_factory_{this};
};

namespace infobars {
class InfoBar;
}  // namespace infobars

namespace clair {

// The IDs ClairUI knows a tab and an infobar by: what a snapshot carries and
// what the bridge resolves.
ClairTabID TabIDOf(content::WebContents* contents);
NSInteger InfobarIDOf(const infobars::InfoBar* infobar);

// The host's Space calls (add-spaces design D9), for clair_native_layer.mm.
// They keep the store, the lists and the windows in step.

// Starts telling `observer` what changes; kept weakly.
void AddSpacesObserver(id<ClairSpacesObserver> observer);
// Every Space, as snapshots, in order.
NSArray<id<ClairSpace>>* SpaceSnapshots();
// A Space's tabs in every profile, or an off-the-record profile's own Space's.
NSArray<id<ClairTab>>* TabsInSpace(const std::string& space);
// Pushes a Space's tab list to the observers.
void NotifyTabsInSpace(const std::string& space);
// Pushes one tab's snapshot to the observers.
void NotifyTab(id<ClairTab> tab);
// D7.
void DeleteSpace(const std::string& space);
void MoveTabToSpace(tabs::TabInterface* tab, const std::string& space);

}  // namespace clair

#endif  // CHROME_BROWSER_CLAIR_CLAIR_SPACE_TABS_H_
