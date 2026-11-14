// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_CLAIR_PROFILES_H_
#define CHROME_BROWSER_CLAIR_CLAIR_PROFILES_H_

#include <string>
#include <string_view>
#include <vector>

#include "base/files/file_path.h"
#include "base/functional/callback.h"
#include "base/no_destructor.h"
#include "base/scoped_observation.h"
#include "chrome/browser/profiles/profile_attributes_storage.h"
#include "chrome/browser/profiles/profile_attributes_storage_observer.h"

#if defined(__OBJC__)
#import <Foundation/Foundation.h>
#import "chrome/browser/clair/ClairHost.h"
#endif

class Profile;

namespace clair {

// add-profiles design D1: a profile is a Chromium profile, and Clair stores
// nothing about it. Its ID is its directory's base name ("Default",
// "Profile 1"); its name and existence come from ProfileAttributesStorage
// alone. ClairProfiles wraps Chromium's profile calls for the host, observes
// the storage, and pushes snapshots to the host's observers.
class ClairProfiles : public ProfileAttributesStorageObserver {
 public:
  // One profile as ClairUI sees it.
  struct Info {
    std::string id;
    std::string name;
  };

  // The profiles, created on first use.
  static ClairProfiles* Get();

  // The default profile's ID: Chromium's initial profile.
  static std::string DefaultID();
  // The ID of `profile`, or of the profile it is off the record of.
  static std::string IDOf(const Profile* profile);

  ClairProfiles(const ClairProfiles&) = delete;
  ClairProfiles& operator=(const ClairProfiles&) = delete;

  // Every profile, the default one first, then by name.
  std::vector<Info> List() const;
  bool Exists(std::string_view id) const;
  // The profile's directory, or an empty path for an unknown or malformed ID.
  base::FilePath PathOf(std::string_view id) const;
  // The loaded profile, or null when it isn't loaded or doesn't exist.
  Profile* LoadedProfile(std::string_view id) const;
  // Runs `done` with the profile once it's loaded, or with null.
  void Load(std::string_view id, base::OnceCallback<void(Profile*)> done);

  // Creates a profile named `name`; `done` gets its ID, or an empty string.
  void Create(std::string_view name,
              base::OnceCallback<void(const std::string&)> done);
  // An empty name is ignored.
  void Rename(std::string_view id, std::string_view name);
  // Deletes a profile and its data, unless a Space uses it (D7).
  void Delete(std::string_view id);

  // Called when the host starts telling its observers; starts observing the
  // storage.
  void Start();

  // ProfileAttributesStorageObserver:
  void OnProfileAdded(const base::FilePath& profile_path) override;
  void OnProfileWasRemoved(const base::FilePath& profile_path,
                           const std::u16string& profile_name) override;
  void OnProfileNameChanged(const base::FilePath& profile_path,
                            const std::u16string& old_profile_name) override;
  void OnProfileIsOmittedChanged(const base::FilePath& profile_path) override;

 private:
  friend class base::NoDestructor<ClairProfiles>;

  ClairProfiles();
  ~ClairProfiles() override;

  // Pushes the list to the host's observers.
  void Changed();

  base::ScopedObservation<ProfileAttributesStorage,
                          ProfileAttributesStorageObserver>
      observation_{this};
};

#if defined(__OBJC__)
// Every profile, as snapshots, in order.
NSArray<id<ClairProfile>>* ProfileSnapshots();
#endif

}  // namespace clair

#endif  // CHROME_BROWSER_CLAIR_CLAIR_PROFILES_H_
