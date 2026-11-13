// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_WINDOW_CLAIR_PEEKS_H_
#define CHROME_BROWSER_CLAIR_WINDOW_CLAIR_PEEKS_H_

#include <memory>
#include <optional>
#include <set>
#include <vector>

#include "base/functional/callback_forward.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/time/time.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/keyboard_event_processing_result.h"
#include "ui/base/window_open_disposition.h"

class ClairBrowserWindow;
class GURL;
class TabStripModel;

namespace content {
class NavigationHandle;
class WebContents;
struct OpenURLParams;
}  // namespace content

namespace input {
struct NativeWebKeyboardEvent;
}  // namespace input

// One native window's Peeks (add-peek design D1). A Peek is an ordinary tab
// directly after its parent in the tab strip; this keeps the table that links
// the two, opens and closes Peeks, keeps each Peek next to its parent, and
// handles the tab commands and Esc that treat them as one.
class ClairPeeks : public TabStripModelObserver {
 public:
  // How long an Esc the page kept arms the next one to close the Peek (D6).
  static constexpr base::TimeDelta kConfirmDuration = base::Seconds(1);

  explicit ClairPeeks(ClairBrowserWindow* window);
  ClairPeeks(const ClairPeeks&) = delete;
  ClairPeeks& operator=(const ClairPeeks&) = delete;
  ~ClairPeeks() override;

  // The Peek of `parent`, or null.
  tabs::TabInterface* PeekOf(const tabs::TabInterface* parent) const;
  // The Peek shown with `parent`: its Peek unless that is closing, or null.
  // ClairUI gets this as the parent's peekID, so a closing Peek's parent
  // shows alone at once (D4).
  tabs::TabInterface* ShownPeekOf(const tabs::TabInterface* parent) const;
  // The tab `peek` is a Peek of, or null for a normal tab.
  tabs::TabInterface* ParentOf(const tabs::TabInterface* peek) const;
  // The ID ClairUI gets as `peek`'s parent: its parent's handle, or a null
  // handle's for a Peek about to close with its parent; nullopt for a normal
  // tab.
  std::optional<int32_t> ParentIDOf(const tabs::TabInterface* peek) const;
  // The same for the tabs showing `contents`.
  content::WebContents* PeekOf(content::WebContents* parent) const;
  content::WebContents* ParentOf(content::WebContents* peek) const;

  // The pages shown in the card while `active` is the active tab: the tab,
  // and its Peek or its parent (D4).
  std::set<content::WebContents*> PagesShownWith(
      content::WebContents* active) const;

  // D2: opens a Shift+clicked link from `source`, which is in this window.
  // A link from a Peek opens a new tab at the top; a link from a tab that
  // already has a Peek navigates it; otherwise it opens in a new Peek. Returns
  // the contents it opened or navigated.
  content::WebContents* OpenURL(
      content::WebContents* source,
      const content::OpenURLParams& params,
      base::OnceCallback<void(content::NavigationHandle&)>&
          navigation_handle_callback);
  content::WebContents* AddContents(
      content::WebContents* source,
      std::unique_ptr<content::WebContents> new_contents,
      const GURL& target_url,
      bool user_gesture);

  // Closes the Peek of `tab` (its parent or the Peek itself), with its
  // leave-page confirmation, after making the parent active.
  void Close(tabs::TabInterface* tab);
  // Closes the Peek after the current task, as from a key event the Peek's
  // own WebContents is still handling.
  void CloseSoon(tabs::TabInterface* peek);
  // Turns the Peek of `tab` into a normal, active tab (D8).
  void Expand(tabs::TabInterface* tab);

  // share-tabs-across-windows D1: `parent` and its Peek are about to move to
  // another window. Forgets the pair here without closing or unlinking the
  // Peek, and returns it, or null when `parent` has none.
  tabs::TabInterface* Release(tabs::TabInterface* parent);
  // The pair moved here from another window: `peek` sits right after
  // `parent`. Links them again without activating either.
  void Adopt(tabs::TabInterface* parent, tabs::TabInterface* peek);

  // Moves `tab` to `to_index` in the tab strip, taking its Peek along, so that
  // `tab` ends at `to_index` and its Peek right after it.
  void MoveTab(tabs::TabInterface* tab, int to_index);
  // Closes `tab`; its Peek closes with it once it's gone (D8).
  void CloseTab(tabs::TabInterface* tab);
  // The tab Close Tabs Below counts from: `tab`'s Peek, if it has one.
  tabs::TabInterface* LastOfFamily(tabs::TabInterface* tab) const;

  // D7: runs a tab command for the active Peek. Returns whether it ran;
  // otherwise the window runs it over its rows (add-spaces D5), or Chromium
  // as usual.
  bool ExecuteCommand(int command);

  // D6: Esc while the active tab is a Peek.
  content::KeyboardEventProcessingResult PreHandleKeyboardEvent(
      const input::NativeWebKeyboardEvent& event);
  bool HandleKeyboardEvent(const input::NativeWebKeyboardEvent& event);
  // The Peek's page used an Esc: arms Confirm.
  void EscapeKept(content::WebContents* peek);

  // TabStripModelObserver:
  void OnTabStripModelChanged(TabStripModel* model,
                              const TabStripModelChange& change,
                              const TabStripSelectionChange& selection) override;
  void OnTabStripModelDestroyed(TabStripModel* model) override;

 private:
  class EscapeWatcher;
  struct Pair {
    Pair(tabs::TabHandle parent, tabs::TabHandle peek);
    Pair(Pair&&);
    Pair& operator=(Pair&&);
    ~Pair();

    tabs::TabHandle parent;
    tabs::TabHandle peek;
    std::unique_ptr<EscapeWatcher> escape_watcher;
    // The Peek is closing: its parent shows alone, and activating the parent
    // doesn't bring the Peek back. Cleared if the Peek becomes active again,
    // as after its leave-page confirmation is declined.
    bool closing = false;
    // CloseWebContentsAt ran for the Peek, so it isn't asked again.
    bool close_requested = false;
  };

  TabStripModel* strip() const { return model_; }
  std::vector<Pair>::iterator FindByParent(const tabs::TabInterface* parent);
  std::vector<Pair>::iterator FindByPeek(const tabs::TabInterface* peek);
  std::vector<Pair>::const_iterator FindByParent(
      const tabs::TabInterface* parent) const;
  std::vector<Pair>::const_iterator FindByPeek(
      const tabs::TabInterface* peek) const;

  // Links `peek`, which sits right after `parent`, as its Peek and shows it.
  void Link(tabs::TabInterface* parent, tabs::TabInterface* peek);
  // Forgets the pair; the Peek, if still there, becomes a normal tab.
  void Unlink(std::vector<Pair>::iterator pair);
  // Marks the Peek as closing before its parent becomes active.
  void BeginClosing(std::vector<Pair>::iterator pair);
  // Closes the Peek's tab, once.
  void RequestClose(tabs::TabInterface* peek, uint32_t close_types);
  // After the active tab changed: a parent made active some other way than
  // its Peek closing shows its Peek again (D4).
  void ActiveTabChanged(tabs::TabInterface* active);
  void ShowPeekOf(tabs::TabHandle parent);
  // D9: records in the session that the Peek of `pair` is no longer one,
  // as it stays a tab.
  void Untag(tabs::TabHandle peek);
  // The tab list ClairUI shows changed.
  void Changed();

  void ActivateTab(tabs::TabInterface* tab);

  // Moves the tab at `from` to `to` without unlinking anything.
  void MoveQuietly(int from, int to);
  // After the tab strip changes: puts each Peek back right after its parent,
  // closes the Peeks whose parent has gone, and activates the parent of a
  // Peek that closed while it was active.
  void ScheduleRepair();
  void Repair();

  // The tab of the active Peek, or null.
  tabs::TabInterface* ActivePeek() const;
  bool IsConfirmArmed(const tabs::TabInterface* peek) const;

  const raw_ptr<ClairBrowserWindow> window_;
  raw_ptr<TabStripModel> model_;
  std::vector<Pair> pairs_;
  // Peeks whose parent has gone, to close.
  std::vector<tabs::TabHandle> orphans_;
  // Parents to activate because their Peek closed while active.
  std::vector<tabs::TabHandle> parents_to_activate_;
  // Parents whose Peek left on its own, to hide unless shown (D8).
  std::vector<tabs::TabHandle> parents_to_hide_;
  bool repair_posted_ = false;
  // While this moves tabs itself, moves don't unlink anything.
  bool moving_ = false;
  // Confirm (D6): the Peek it's armed for, and until when.
  std::optional<tabs::TabHandle> confirm_peek_;
  base::TimeTicks confirm_until_;
  base::WeakPtrFactory<ClairPeeks> weak_factory_{this};
};

#endif  // CHROME_BROWSER_CLAIR_WINDOW_CLAIR_PEEKS_H_
