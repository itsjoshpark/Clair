// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_CLAIR_SPACE_STORE_H_
#define CHROME_BROWSER_CLAIR_CLAIR_SPACE_STORE_H_

#include <optional>
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

// One Space: a named set of tabs with an optional emoji icon.
struct Space {
  // A lowercase UUID, which never changes.
  std::string id;
  // Never empty.
  std::string name;
  // One emoji, or empty.
  std::string icon;
};

// The app's Spaces, in the user's order, kept in Chromium's Local State
// (add-spaces design D1):
//
//   clair.spaces      { "version": 1,
//                       "order": ["<uuid>", …],
//                       "spaces": { "<uuid>": { "name": "Work",
//                                               "icon": "💼" } } }
//   clair.last_space  "<uuid>"   // the Space last shown in a key window
//
// There is always at least one Space: with none stored it creates "Home", and
// it refuses to delete the last.
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

  // Adds a Space after the last one and returns its ID, or an empty string
  // for an empty name.
  std::string Create(std::string_view name, std::string_view icon);
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
