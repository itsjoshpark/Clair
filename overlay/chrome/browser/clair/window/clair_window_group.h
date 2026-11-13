// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_WINDOW_CLAIR_WINDOW_GROUP_H_
#define CHROME_BROWSER_CLAIR_WINDOW_CLAIR_WINDOW_GROUP_H_

#include <string>
#include <vector>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "components/tabs/public/tab_interface.h"

class ClairBrowserWindow;
class GURL;
class Profile;

// add-profiles design D3: what the user sees as one window. One Chromium
// Browser has one profile, so a window that shows Spaces of several profiles
// is a group of browsers, at most one per profile, of which one is shown and
// the rest are ordered out. Each member keeps its own ClairBrowserWindow,
// ClairNativeWindow and ClairWindow. Switching to a Space of another profile
// swaps the members in place: the incoming one takes the group's frame, is
// shown and made key, and the outgoing one is ordered out, in one run-loop
// turn without window animation. In macOS full screen, the incoming member
// covers the full-screen one instead (D4).
//
// A browser Chromium creates on its own starts a group of its own. Incognito
// and guest windows are groups of one, which never switch.
//
// The groups also hold the windows session restore brings back until it has
// finished, then arrange them by the user's restore setting (D6).
class ClairWindowGroup {
 public:
  ClairWindowGroup(const ClairWindowGroup&) = delete;
  ClairWindowGroup& operator=(const ClairWindowGroup&) = delete;

  // --- Membership ---
  // ClairBrowserWindow's constructor: joins the group that is creating it,
  // or starts a new one.
  static void Join(ClairBrowserWindow* window);
  // ClairBrowserWindow's destructor.
  static void Leave(ClairBrowserWindow* window);
  // The group of `window`, or null.
  static ClairWindowGroup* Of(const ClairBrowserWindow* window);
  // The regular groups, most recently active first.
  static std::vector<ClairWindowGroup*> RegularByActivation();
  // The most recently active regular group other than `except`, or null.
  static ClairWindowGroup* MostRecentlyActive(const ClairWindowGroup* except);

  // A lowercase UUID, which a group's tabs carry in the session (D6).
  const std::string& id() const { return id_; }
  // The member the user sees.
  ClairBrowserWindow* shown() const { return shown_; }
  std::vector<ClairBrowserWindow*> members() const;
  // The member for the profile with `profile_id`, or null.
  ClairBrowserWindow* MemberFor(const std::string& profile_id) const;
  bool IsHidden(const ClairBrowserWindow* window) const {
    return window != shown_.get();
  }
  // Whether it holds a regular profile's windows, which show Spaces.
  bool is_regular() const;
  // The Space the group shows: its shown member's.
  std::string shown_space() const;

  // --- Switching (D3, D4) ---
  // Shows `space`, of any profile: the shown member shows it, or the group
  // swaps to its member for the Space's profile, created hidden if need be.
  // `then` runs with the member showing it, once it does, which may wait for
  // the profile to load; with null if it can't.
  void ShowSpace(const std::string& space,
                 base::OnceCallback<void(ClairBrowserWindow*)> then = {});
  // Runs `done` with the member for `profile_id`, created hidden if the group
  // has none; with null when the profile can't be loaded.
  void EnsureMember(const std::string& profile_id,
                    base::OnceCallback<void(ClairBrowserWindow*)> done);
  // Makes `member`, already showing the Space it should, the shown one.
  // `previous_space` is the Space the group showed, for ClairUI's slide.
  void SwapTo(ClairBrowserWindow* member, const std::string& previous_space);
  // Chromium asked to see a hidden member (Show(), Activate()): the group
  // switches to it.
  void ShowMember(ClairBrowserWindow* member);
  // A member became key: the group is the most recently active.
  void Activated();
  // The shown member shows another Space: clair.windows follows it.
  void ShownSpaceChanged(ClairBrowserWindow* member);

  // D4: the member holding the full-screen NSWindow, or null.
  ClairBrowserWindow* fullscreen_owner() const;
  // Whether the group is in macOS full screen.
  bool IsFullscreen() const;
  // `member` entered or left macOS full screen.
  void FullscreenChanged(ClairBrowserWindow* member, bool entered);

  // --- Closing (D5, D13) ---
  // The user closes the window: each member's tabs go to the most recently
  // active other group's member for that profile, created hidden if need be,
  // and the emptied members close. With no other group, every member closes
  // through Chromium's close flow, hidden ones first. `closing`, if any, is a
  // tab that closes with the window instead of being handed on (D13).
  void CloseByUser(tabs::TabInterface* closing = nullptr);
  // A hidden member whose tabs have all gone closes.
  void MaybeCloseEmptyHiddenMember(ClairBrowserWindow* member);

  // --- Opening (D7, D8) ---
  // Opens `url`, or a new tab page when it's empty, in a new foreground tab
  // of `space`: in the most recently active regular group, or a new window.
  static void OpenInSpace(const std::string& space, const GURL& url);
  // The Space a new window of `profile` shows: the profile's Space shown
  // most recently in this run, or else its first; empty when it has none.
  static std::string SpaceForNewWindow(Profile* profile);
  // The Space of a profile shown most recently in this run, if any.
  static std::string LastShownSpaceOf(const std::string& profile_id);
  // D8: `window` opened in a profile no Space uses. Its pages open in
  // clair.last_space instead, and it closes.
  static void HandOverToLastSpace(ClairBrowserWindow* window);

  // --- Session restore (D6) ---
  // Whether `window`'s Show() waits for session restore to finish.
  static bool HoldsShow(ClairBrowserWindow* window);
  // Session restore activated `window`: it was the last active one.
  static void NoteRestoreActivation(ClairBrowserWindow* window);
  // Reads the restore setting and starts listening for session restore.
  // Called once, when ClairUI starts.
  static void Start();

 private:
  explicit ClairWindowGroup(std::string id);
  ~ClairWindowGroup();

  void Add(ClairBrowserWindow* window);
  void Remove(ClairBrowserWindow* window);
  // Moves `window` from its group into this one, hidden.
  void Adopt(ClairBrowserWindow* window);
  // D4: shows `member` over the full-screen owner, or takes the cover away.
  void Cover(ClairBrowserWindow* member);
  void Uncover();
  // Closes the next member through Chromium's close flow, hidden ones
  // first.
  void CloseNext();

  // D6.
  static void SessionRestored(Profile* profile, int tab_count);
  static void ArrangeRestoredWindows();

  std::string id_;
  std::vector<raw_ptr<ClairBrowserWindow>> members_;
  raw_ptr<ClairBrowserWindow> shown_ = nullptr;
  // D4: the member over the full-screen owner, or null.
  raw_ptr<ClairBrowserWindow> cover_ = nullptr;
  raw_ptr<ClairBrowserWindow> fullscreen_owner_ = nullptr;
  // Closing through Chromium's close flow, one member after another.
  bool closing_ = false;
  base::WeakPtrFactory<ClairWindowGroup> weak_factory_{this};
};

#endif  // CHROME_BROWSER_CLAIR_WINDOW_CLAIR_WINDOW_GROUP_H_
