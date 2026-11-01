// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_CLAIR_NATIVE_LAYER_H_
#define CHROME_BROWSER_CLAIR_CLAIR_NATIVE_LAYER_H_

namespace clair {

// Loads ClairUI.framework from the app's Contents/Frameworks and starts it with
// Chromium's implementation of the ClairHost protocol (ClairHost.h). Call once,
// on the main thread, after the main menu is built. When the framework is
// missing or doesn't load, it logs why and returns, so a bare engine runs
// without the native layer.
void StartNativeLayer();

}  // namespace clair

#endif  // CHROME_BROWSER_CLAIR_CLAIR_NATIVE_LAYER_H_
