// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_CLAIR_VERSION_H_
#define CHROME_BROWSER_CLAIR_CLAIR_VERSION_H_

#include <string>

namespace clair {

// The Clair version and build number, for example "0.1.0 (123)". Packaging
// writes them into the main bundle's Info.plist, so this reads them at run time
// and they are not part of the engine. Call it only from the browser process.
std::string GetVersionString();

// The engine Clair is built on, for example
// "Chromium 156.0.8078.73 (ungoogled-chromium 156.0.8078.73-1)".
std::string GetEngineVersionString();

}  // namespace clair

#endif  // CHROME_BROWSER_CLAIR_CLAIR_VERSION_H_
