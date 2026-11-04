// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_MAC_CLAIR_UPDATE_RELAUNCH_H_
#define CHROME_BROWSER_MAC_CLAIR_UPDATE_RELAUNCH_H_

#include <string>
#include <vector>

#include "base/containers/span.h"

// When Clair quits with an update waiting, Sparkle's installer replaces the app
// at the moment Chromium's relauncher would reopen it. Sparkle can reopen the
// app itself, but always in the foreground and without Chromium's quit handling,
// so Clair leaves that to the relauncher, which waits for the installer here.
namespace clair {

// Records that Sparkle's installer will replace the running app once it quits.
// Any relaunch from now on waits for that, whatever started it. Call it from
// the browser process.
void NoteUpdateWillInstallOnQuit();

// Adds the running build number to a relauncher's arguments, if an update is
// due to replace it.
void AddUpdateRelauncherArgument(std::vector<std::string>& relauncher_args);

// In the relauncher: if `args` ask for it, waits until `app_bundle` no longer
// has the build it was given. Gives up after a minute, so a failed install
// reopens the old version rather than nothing.
void WaitForUpdateInstall(base::span<const char* const> args,
                          const std::string& app_bundle);

}  // namespace clair

#endif  // CHROME_BROWSER_MAC_CLAIR_UPDATE_RELAUNCH_H_
