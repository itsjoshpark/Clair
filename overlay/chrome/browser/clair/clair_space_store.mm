// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#include "chrome/browser/clair/clair_space_store.h"

#include <algorithm>
#include <set>
#include <utility>

#include "base/check.h"
#include "base/no_destructor.h"
#include "base/strings/string_util.h"
#include "base/uuid.h"
#include "base/values.h"
#include "chrome/browser/browser_process.h"
#include "components/prefs/pref_registry_simple.h"
#include "components/prefs/pref_service.h"

namespace clair {

namespace {

constexpr int kVersion = 1;
constexpr char kVersionKey[] = "version";
constexpr char kOrderKey[] = "order";
constexpr char kSpacesKey[] = "spaces";
constexpr char kNameKey[] = "name";
constexpr char kIconKey[] = "icon";

// `text` without surrounding whitespace, cut to `max` bytes on a character
// boundary.
std::string Clean(std::string_view text, size_t max) {
  std::string trimmed(base::TrimWhitespaceASCII(text, base::TRIM_ALL));
  std::string cut;
  base::TruncateUTF8ToByteSize(trimmed, max, &cut);
  return cut;
}

// An icon is kept only whole: a cut emoji would be a different one.
std::string CleanIcon(std::string_view icon) {
  std::string trimmed(base::TrimWhitespaceASCII(icon, base::TRIM_ALL));
  return trimmed.size() <= ClairSpaceStore::kMaxIconLength &&
                 base::IsStringUTF8(trimmed)
             ? trimmed
             : std::string();
}

}  // namespace

// static
void ClairSpaceStore::RegisterPrefs(PrefRegistrySimple* registry) {
  registry->RegisterDictionaryPref(kSpacesPref);
  registry->RegisterStringPref(kLastSpacePref, std::string());
}

// static
ClairSpaceStore* ClairSpaceStore::Get() {
  static base::NoDestructor<ClairSpaceStore> store(
      g_browser_process->local_state());
  return store.get();
}

ClairSpaceStore::ClairSpaceStore(PrefService* local_state)
    : prefs_(local_state) {
  CHECK(prefs_);
  Load();
}

void ClairSpaceStore::Load() {
  spaces_.clear();
  const base::DictValue& stored = prefs_->GetDict(kSpacesPref);
  const std::optional<int> version = stored.FindInt(kVersionKey);
  const base::ListValue* order = stored.FindList(kOrderKey);
  const base::DictValue* entries = stored.FindDict(kSpacesKey);
  if (version == kVersion && order && entries) {
    std::set<std::string> seen;
    for (const base::Value& value : *order) {
      const std::string* id = value.GetIfString();
      if (!id || !base::Uuid::ParseLowercase(*id).is_valid() ||
          !seen.insert(*id).second) {
        continue;
      }
      const base::DictValue* entry = entries->FindDict(*id);
      const std::string* name = entry ? entry->FindString(kNameKey) : nullptr;
      if (!name) {
        continue;
      }
      Space space{*id, Clean(*name, kMaxNameLength), std::string()};
      if (space.name.empty()) {
        continue;
      }
      if (const std::string* icon = entry->FindString(kIconKey)) {
        space.icon = CleanIcon(*icon);
      }
      spaces_.push_back(std::move(space));
    }
  }
  // There are no existing users to migrate (design, Context): anything else
  // starts over with one Space.
  if (spaces_.empty()) {
    spaces_.push_back({base::Uuid::GenerateRandomV4().AsLowercaseString(),
                       kFirstSpaceName, std::string()});
    Save();
  }
}

void ClairSpaceStore::Save() {
  base::ListValue order;
  base::DictValue entries;
  for (const Space& space : spaces_) {
    order.Append(space.id);
    base::DictValue entry;
    entry.Set(kNameKey, space.name);
    if (!space.icon.empty()) {
      entry.Set(kIconKey, space.icon);
    }
    entries.Set(space.id, std::move(entry));
  }
  base::DictValue stored;
  stored.Set(kVersionKey, kVersion);
  stored.Set(kOrderKey, std::move(order));
  stored.Set(kSpacesKey, std::move(entries));
  prefs_->SetDict(kSpacesPref, std::move(stored));
}

void ClairSpaceStore::Changed() {
  Save();
  for (Observer& observer : observers_) {
    observer.OnSpacesChanged();
  }
}

const Space* ClairSpaceStore::Find(std::string_view id) const {
  auto it = std::ranges::find(spaces_, id, &Space::id);
  return it == spaces_.end() ? nullptr : &*it;
}

std::optional<size_t> ClairSpaceStore::IndexOf(std::string_view id) const {
  auto it = std::ranges::find(spaces_, id, &Space::id);
  if (it == spaces_.end()) {
    return std::nullopt;
  }
  return static_cast<size_t>(it - spaces_.begin());
}

std::string ClairSpaceStore::Create(std::string_view name,
                                    std::string_view icon) {
  Space space{base::Uuid::GenerateRandomV4().AsLowercaseString(),
              Clean(name, kMaxNameLength), CleanIcon(icon)};
  if (space.name.empty()) {
    return std::string();
  }
  std::string id = space.id;
  spaces_.push_back(std::move(space));
  Changed();
  return id;
}

void ClairSpaceStore::Rename(std::string_view id, std::string_view name) {
  std::string cleaned = Clean(name, kMaxNameLength);
  auto it = std::ranges::find(spaces_, id, &Space::id);
  if (it == spaces_.end() || cleaned.empty() || it->name == cleaned) {
    return;
  }
  it->name = std::move(cleaned);
  Changed();
}

void ClairSpaceStore::SetIcon(std::string_view id, std::string_view icon) {
  std::string cleaned = CleanIcon(icon);
  auto it = std::ranges::find(spaces_, id, &Space::id);
  if (it == spaces_.end() || it->icon == cleaned) {
    return;
  }
  it->icon = std::move(cleaned);
  Changed();
}

void ClairSpaceStore::Move(std::string_view id, int index) {
  std::optional<size_t> from = IndexOf(id);
  if (!from) {
    return;
  }
  const size_t to = static_cast<size_t>(
      std::clamp(index, 0, static_cast<int>(spaces_.size()) - 1));
  if (to == *from) {
    return;
  }
  Space space = std::move(spaces_[*from]);
  spaces_.erase(spaces_.begin() + *from);
  spaces_.insert(spaces_.begin() + to, std::move(space));
  Changed();
}

bool ClairSpaceStore::Remove(std::string_view id) {
  std::optional<size_t> index = IndexOf(id);
  if (!index || spaces_.size() <= 1) {
    return false;
  }
  spaces_.erase(spaces_.begin() + *index);
  Changed();
  return true;
}

std::string ClairSpaceStore::last_space() const {
  const std::string& last = prefs_->GetString(kLastSpacePref);
  return Contains(last) ? last : first();
}

void ClairSpaceStore::SetLastSpace(std::string_view id) {
  if (Contains(id) && prefs_->GetString(kLastSpacePref) != id) {
    prefs_->SetString(kLastSpacePref, std::string(id));
  }
}

void ClairSpaceStore::AddObserver(Observer* observer) {
  observers_.AddObserver(observer);
}

void ClairSpaceStore::RemoveObserver(Observer* observer) {
  observers_.RemoveObserver(observer);
}

}  // namespace clair
