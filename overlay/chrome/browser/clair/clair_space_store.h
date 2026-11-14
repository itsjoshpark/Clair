// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_CLAIR_SPACE_STORE_H_
#define CHROME_BROWSER_CLAIR_CLAIR_SPACE_STORE_H_

#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <vector>

#include "base/memory/raw_ptr.h"
#include "base/no_destructor.h"
#include "base/observer_list.h"
#include "base/observer_list_types.h"

class PrefRegistrySimple;
class PrefService;

namespace clair {

// Local State prefs (add-spaces design D1).
inline constexpr char kSpacesPref[] = "clair.spaces";
inline constexpr char kLastSpacePref[] = "clair.last_space";
// add-profiles design D2: each window group's UUID and the Space it shows.
inline constexpr char kWindowsPref[] = "clair.windows";

// One Space: a named set of tabs with an optional emoji icon, using one
// profile (add-profiles design D2).
struct Space {
  // A lowercase UUID, which never changes.
  std::string id;
  // Never empty.
  std::string name;
  // One emoji, or empty.
  std::string icon;
  // The profile's directory name, such as "Default"; never empty.
  std::string profile;
};

// The app's Spaces, in the user's order, kept in Chromium's Local State
// (add-spaces design D1):
//
//   clair.spaces      { "version": 1,
//                       "order": ["<uuid>", …],
//                       "spaces": { "<uuid>": { "name": "Work",
//                                               "icon": "💼",
//                                               "profile": "Profile 1" } } }
//   clair.last_space  "<uuid>"   // the Space last shown in a key window
//   clair.windows     { "<group uuid>": "<space uuid>" }
//
// There is always at least one Space: with none stored it creates "Home", and
// it refuses to delete the last. A Space without "profile", as stored before
// add-profiles, uses the default profile, as does one whose profile is gone
// (add-profiles design D2).
class ClairSpaceStore {
 public:
  class Observer : public base::CheckedObserver {
   public:
    // Spaces were added, removed, renamed, given an icon or reordered.
    virtual void OnSpacesChanged() = 0;
  };

  // The name of the first Space (design, Open Questions).
  static constexpr char kFirstSpaceName[] = "Home";
  // Names and icons longer than this are cut or dropped as invalid.
  static constexpr size_t kMaxNameLength = 200;
  static constexpr size_t kMaxIconLength = 64;

  // browser_prefs.cc, through clair::RegisterLocalStatePrefs.
  static void RegisterPrefs(PrefRegistrySimple* registry);

  // The store, created on first use from the browser process's Local State.
  static ClairSpaceStore* Get();

  ClairSpaceStore(const ClairSpaceStore&) = delete;
  ClairSpaceStore& operator=(const ClairSpaceStore&) = delete;

  const std::vector<Space>& spaces() const { return spaces_; }
  const Space* Find(std::string_view id) const;
  std::optional<size_t> IndexOf(std::string_view id) const;
  bool Contains(std::string_view id) const { return Find(id) != nullptr; }
  // The first Space's ID.
  const std::string& first() const { return spaces_.front().id; }

  // Adds a Space after the last one, using `profile`, and returns its ID, or
  // an empty string for an empty name or an unknown profile.
  std::string Create(std::string_view name,
                     std::string_view icon,
                     std::string_view profile);
  // add-profiles D9: makes the Space use `profile`. Returns whether it
  // changed. Reopening its tabs is the caller's.
  bool SetProfile(std::string_view id, std::string_view profile);
  // D2: `profile` is gone; its Spaces use the default profile.
  void ProfileRemoved(std::string_view profile);
  // How many Spaces use `profile`.
  int SpaceCountOf(std::string_view profile) const;
  // The profile a Space uses, or an empty string for an unknown Space.
  std::string ProfileOf(std::string_view id) const;
  // An empty name is ignored.
  void Rename(std::string_view id, std::string_view name);
  // An empty icon removes it.
  void SetIcon(std::string_view id, std::string_view icon);
  // Moves the Space to `index` in the order, clamped.
  void Move(std::string_view id, int index);
  // Removes the Space from the store, unless it's the only one. Returns
  // whether it did. Closing its tabs is the caller's.
  bool Remove(std::string_view id);

  // The Space last shown in a key window, if it still exists; otherwise the
  // first.
  std::string last_space() const;
  void SetLastSpace(std::string_view id);

  // add-profiles D2, D6: the Space a window group shows, or empty.
  std::string WindowSpace(std::string_view group) const;
  void SetWindowSpace(std::string_view group, std::string_view space);
  // Drops the entries of groups not in `groups`, once session restore has
  // finished.
  void KeepWindows(const std::set<std::string>& groups);

  void AddObserver(Observer* observer);
  void RemoveObserver(Observer* observer);

 private:
  friend class base::NoDestructor<ClairSpaceStore>;

  explicit ClairSpaceStore(PrefService* local_state);

  // Reads clair.spaces, keeping only valid entries, and creates the first
  // Space when none is left.
  void Load();
  void Save();
  void Changed();

  const raw_ptr<PrefService> prefs_;
  std::vector<Space> spaces_;
  base::ObserverList<Observer> observers_;
};

}  // namespace clair

#endif  // CHROME_BROWSER_CLAIR_CLAIR_SPACE_STORE_H_
